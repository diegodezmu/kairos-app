import AppKit
import Observation
import SwiftUI
import KairosCore

@MainActor
@Observable
final class DesktopShellModel {
    let settings: SettingsModel

    @ObservationIgnored
    private var abletonLinkBridge: AbletonLinkBridge?
    @ObservationIgnored
    private var usbMIDISyncBridge: USBMIDISyncBridge?
    @ObservationIgnored
    private let presetStore: PresetStore?
    @ObservationIgnored
    private let currentDate: () -> Date
    @ObservationIgnored
    private let gridPreviewDriver = GridPreviewDriver()
    @ObservationIgnored
    private let levelRuntimeDriver = LevelRuntimeDriver()
    @ObservationIgnored
    private let levelTelemetryReceiver = LevelTelemetryReceiver()
    @ObservationIgnored
    private var linkStatusTask: Task<Void, Never>?
    @ObservationIgnored
    private var latestLinkSnapshot: AbletonLinkSnapshot?
    @ObservationIgnored
    private var latestUSBMIDISnapshot: USBMIDISyncSnapshot?
    @ObservationIgnored
    private var levelStatusTask: Task<Void, Never>?
    @ObservationIgnored
    private var loadPresetsTask: Task<Void, Never>?
    @ObservationIgnored
    private var hasStartedRuntime = false
    @ObservationIgnored
    private let metronomeClickEngine = MetronomeClickEngine()
    @ObservationIgnored
    private var metronomeTask: Task<Void, Never>?

    private(set) var presetLibrary: PresetLibrary
    private(set) var storageErrorMessage: String?
    private(set) var levelTelemetrySnapshot = LevelTelemetrySnapshot(
        isListening: false,
        port: 51515,
        errorMessage: nil,
        sources: []
    )
    private(set) var usbMIDISources: [USBMIDISourceDescriptor] = []
    private(set) var laneStatuses: [LaneID: LevelLaneConnectionStatus] = [:]

    var isSidebarVisible = true
    var isPreviewPlaying = false

    @ObservationIgnored
    private var accumulatedElapsed: TimeInterval = 0
    @ObservationIgnored
    private var playbackStartedAt: Date?
    @ObservationIgnored
    private var externalTransportHoldSeconds: TimeInterval = 0
    @ObservationIgnored
    private var externalElapsedResetOriginSeconds: TimeInterval = 0
    @ObservationIgnored
    private var seenTelemetrySlotsByLane: [LaneID: Int] = [:]

    init(
        settings: SettingsModel = SettingsModel(),
        presetStore: PresetStore? = try? PresetStore(),
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.presetStore = presetStore
        self.currentDate = currentDate
        presetLibrary = .factoryDefault
    }

    deinit {
        linkStatusTask?.cancel()
        levelStatusTask?.cancel()
        loadPresetsTask?.cancel()
        metronomeTask?.cancel()
    }

    func startRuntimeIfNeeded() {
        guard !hasStartedRuntime else {
            return
        }

        hasStartedRuntime = true
        synchronizeUSBSourceSelection()
        refreshLinkStatus()
        refreshUSBMIDISyncState()
        startLinkStatusMonitor()
        synchronizeTransportState()
        startMetronomeMonitor()
        refreshMetronomeScheduling(at: currentDate(), reset: true)
        levelTelemetryReceiver.start()
        refreshLevelSidebarState(at: currentDate())
        startLevelStatusMonitor()
        loadPresetsTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.loadPresets()
        }
    }

    func stopRuntime() {
        guard hasStartedRuntime else {
            return
        }

        hasStartedRuntime = false
        loadPresetsTask?.cancel()
        loadPresetsTask = nil
        linkStatusTask?.cancel()
        linkStatusTask = nil
        metronomeTask?.cancel()
        metronomeTask = nil
        levelStatusTask?.cancel()
        levelStatusTask = nil
        metronomeClickEngine.stop()
        levelTelemetryReceiver.stop()
        releaseLinkBridge()
        releaseUSBMIDISyncBridge()
    }

    var canControlTransport: Bool {
        settings.syncSource == .internalClock
    }

    var canEditTempo: Bool {
        settings.syncSource == .internalClock
    }

    var usbSyncInputStatus: SyncInputConnectionStatus? {
        guard settings.syncSource == .usb else {
            return nil
        }

        let snapshot = currentUSBMIDISnapshot()
        if let snapshot, !snapshot.isBridgeAvailable {
            return .disconnected("USB MIDI unavailable")
        }

        let selectedSourceName = currentUSBMIDISourceDisplayName(
            snapshot: snapshot
        )
        if let selectedSourceName {
            if snapshot?.isSelectedSourceAvailable == true {
                return .connected(selectedSourceName)
            }

            if settings.usbMIDISource.uniqueID != nil {
                return .disconnected("\(selectedSourceName) disconnected")
            }
        }

        if usbMIDISources.isEmpty {
            return .waiting("No USB MIDI input connected")
        }

        return .waiting("Select USB MIDI input")
    }

    var activePreset: StoredPreset {
        presetLibrary.storedPreset(for: settings.activePresetID)
            ?? presetLibrary.defaultPreset
    }

    var availablePresets: [StoredPreset] {
        presetLibrary.presets.filter { $0.id != activePreset.id }
    }

    var activePresetToolbarLabel: String {
        activePreset.name
    }

    func loadPresets() async {
        guard let presetStore else {
            storageErrorMessage = "Preset storage unavailable."
            return
        }

        do {
            let library = try await presetStore.loadPresets()
            presetLibrary = library

            let storedPreset = library.storedPreset(for: settings.activePresetID)
                ?? library.defaultPreset
            settings.apply(
                storedPreset.settings,
                activating: storedPreset.id
            )

            synchronizeUSBSourceSelection()
            synchronizeTransportState()
            refreshLevelSidebarState(at: currentDate())
            refreshMetronomeScheduling(at: currentDate(), reset: true)
        } catch {
            presetLibrary = .factoryDefault
            storageErrorMessage = "Presets could not be loaded."
        }
    }

    func saveCurrentPreset() async {
        let targetPreset = activePreset
        var updatedLibrary = presetLibrary
        updatedLibrary.replace(
            preset: settings.makeStoredPreset(
                id: targetPreset.id,
                name: targetPreset.name
            )
        )

        _ = await persistPresetLibrary(
            updatedLibrary,
            errorMessage: "Current preset could not be saved."
        )
    }

    func addPreset() async {
        let newPreset = StoredPreset(
            name: nextCustomPresetName(),
            settings: settings.preset
        )
        var updatedLibrary = presetLibrary
        updatedLibrary.append(preset: newPreset)

        guard await persistPresetLibrary(
            updatedLibrary,
            errorMessage: "New preset could not be created."
        ) else {
            return
        }

        settings.activePresetID = newPreset.id
    }

    func renamePreset(
        _ presetID: String,
        to proposedName: String
    ) async {
        guard let storedPreset = presetLibrary.storedPreset(for: presetID) else {
            return
        }

        guard !storedPreset.isDefault else {
            return
        }

        let trimmedName = proposedName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty else {
            return
        }

        var renamedPreset = storedPreset
        renamedPreset.name = trimmedName

        var updatedLibrary = presetLibrary
        updatedLibrary.replace(preset: renamedPreset)

        _ = await persistPresetLibrary(
            updatedLibrary,
            errorMessage: "Preset name could not be updated."
        )
    }

    func removePreset(_ presetID: String) async {
        guard let storedPreset = presetLibrary.storedPreset(for: presetID) else {
            return
        }

        guard !storedPreset.isDefault else {
            return
        }

        var updatedLibrary = presetLibrary
        updatedLibrary.removePreset(id: presetID)

        guard await persistPresetLibrary(
            updatedLibrary,
            errorMessage: "Preset could not be removed."
        ) else {
            return
        }

        if settings.activePresetID == presetID {
            selectPreset(updatedLibrary.defaultPreset.id, at: currentDate())
        }
    }

    func selectPreset(_ presetID: String) {
        selectPreset(presetID, at: currentDate())
    }

    private func selectPreset(
        _ presetID: String,
        at date: Date
    ) {
        guard let storedPreset = presetLibrary.storedPreset(for: presetID) else {
            return
        }

        settings.apply(
            storedPreset.settings,
            activating: presetID
        )
        synchronizeUSBSourceSelection()
        synchronizeTransportState()
        resetPreview(at: date)
        refreshMetronomeScheduling(at: date, reset: true)
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func togglePlay() {
        togglePlay(at: currentDate())
    }

    private func togglePlay(at date: Date) {
        guard canControlTransport else {
            return
        }

        if isPreviewPlaying {
            accumulatedElapsed = elapsedTime(at: date)
            playbackStartedAt = nil
            isPreviewPlaying = false
        } else {
            playbackStartedAt = date
            isPreviewPlaying = true
        }

        refreshMetronomeScheduling(at: date, reset: true)
    }

    func resetPreview() {
        resetPreview(at: currentDate())
    }

    private func resetPreview(at date: Date) {
        accumulatedElapsed = 0
        playbackStartedAt = isPreviewPlaying ? date : nil
        externalTransportHoldSeconds = 0
        externalElapsedResetOriginSeconds = currentExternalTransportSnapshot()?.elapsedSeconds ?? 0
        gridPreviewDriver.reset()
        levelRuntimeDriver.reset()
        refreshLevelSidebarState(at: date)
        refreshMetronomeScheduling(at: date, reset: true)
    }

    private func persistPresetLibrary(
        _ library: PresetLibrary,
        errorMessage: String
    ) async -> Bool {
        do {
            if let presetStore {
                try await presetStore.savePresets(library)
            }
            presetLibrary = library
            storageErrorMessage = nil
            return true
        } catch {
            storageErrorMessage = errorMessage
            return false
        }
    }

    private func nextCustomPresetName() -> String {
        let existingNames = Set(
            presetLibrary.presets.map {
                $0.name.lowercased()
            }
        )

        var index = 1
        while true {
            let candidate = "preset \(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    func setSyncSource(_ source: SyncSource) {
        setSyncSource(source, at: currentDate())
    }

    func activateUSBMIDISync() {
        activateUSBMIDISync(at: currentDate())
    }

    private func setSyncSource(
        _ source: SyncSource,
        at date: Date
    ) {
        guard settings.syncSource != source else {
            return
        }

        settings.syncSource = source
        synchronizeTransportState()
        resetPreview(at: date)
    }

    private func activateUSBMIDISync(
        at date: Date
    ) {
        refreshUSBMIDISyncState()

        if settings.usbMIDISource.uniqueID == nil,
           usbMIDISources.count == 1,
           let onlySource = usbMIDISources.first {
            selectUSBMIDISource(onlySource, at: date)
            return
        }

        guard settings.syncSource != .usb else {
            return
        }

        settings.syncSource = .usb
        synchronizeTransportState()
        resetPreview(at: date)
    }

    func selectUSBMIDISource(_ source: USBMIDISourceDescriptor) {
        selectUSBMIDISource(source, at: currentDate())
    }

    private func selectUSBMIDISource(
        _ source: USBMIDISourceDescriptor,
        at date: Date
    ) {
        settings.usbMIDISource = USBMIDISourcePreference(
            uniqueID: source.uniqueID,
            displayName: source.displayName
        )
        synchronizeUSBSourceSelection()
        refreshUSBMIDISyncState()

        if settings.syncSource == .usb {
            synchronizeTransportState()
            resetPreview(at: date)
            return
        }

        settings.syncSource = .usb
        synchronizeTransportState()
        resetPreview(at: date)
    }

    func setLatency(_ milliseconds: Double) {
        settings.offset = Offset(milliseconds: milliseconds)
        refreshMetronomeScheduling(at: currentDate(), reset: true)
    }

    func setBPM(_ bpm: Int) {
        settings.bpm = bpm

        guard settings.syncSource == .link else {
            refreshMetronomeScheduling(at: currentDate(), reset: true)
            return
        }

        ensureLinkBridge().seedTempo(Double(settings.bpm))
        refreshLinkStatus()
        refreshMetronomeScheduling(at: currentDate(), reset: true)
    }

    func setMetronomePulse(_ pulse: Pulse) {
        settings.metronomePulse = pulse
        refreshMetronomeScheduling(at: currentDate(), reset: true)
    }

    func toggleMetronome() {
        settings.isMetronomeEnabled.toggle()
        refreshMetronomeScheduling(at: currentDate(), reset: true)
    }

    func setGridPanelVisibility(_ isVisible: Bool) {
        settings.isGridVisible = isVisible
    }

    func setLevelPanelVisibility(_ isVisible: Bool) {
        settings.isLevelVisible = isVisible
    }

    func setCycleEnabled(
        _ isEnabled: Bool,
        slot: CycleSlot
    ) {
        settings.updateGridCycle(slot: slot) { cycle in
            cycle.isEnabled = isEnabled
        }
    }

    func setCycleStepNumber(
        _ stepNumber: StepNumber,
        slot: CycleSlot
    ) {
        settings.updateGridCycle(slot: slot) { cycle in
            cycle.stepNumber = stepNumber
            cycle.customStepModes = SettingsDefaults.normalizedCustomStepModes(
                cycle.customStepModes,
                stepCount: stepNumber.rawValue,
                fallback: cycle.customStepModes?.last ?? .block
            )
        }
    }

    func setCyclePulse(
        _ pulse: Pulse,
        slot: CycleSlot
    ) {
        settings.updateGridCycle(slot: slot) { cycle in
            cycle.pulse = pulse
        }
    }

    func setCycleVisualMode(
        _ mode: GridVisualMode,
        slot: CycleSlot
    ) {
        settings.updateGridCycle(slot: slot) { cycle in
            if mode == .custom, cycle.visualMode != .custom {
                let seedMode = cycle.visualMode.uniformDisplayMode ?? .block
                cycle.customStepModes = SettingsDefaults.normalizedCustomStepModes(
                    cycle.customStepModes,
                    stepCount: cycle.stepNumber.rawValue,
                    fallback: seedMode
                ) ?? Array(
                    repeating: seedMode,
                    count: cycle.stepNumber.rawValue
                )
            }

            cycle.visualMode = mode
        }
    }

    func cycleCustomStepMode(
        slot: CycleSlot,
        stepIndex: Int
    ) {
        settings.updateGridCycle(slot: slot) { cycle in
            guard
                cycle.visualMode == .custom,
                cycle.stepNumber != .oneHundredTwentyEight
            else {
                return
            }

            let stepCount = cycle.stepNumber.rawValue
            var customModes = SettingsDefaults.normalizedCustomStepModes(
                cycle.customStepModes,
                stepCount: stepCount,
                fallback: .block
            ) ?? Array(repeating: .block, count: stepCount)

            guard customModes.indices.contains(stepIndex) else {
                return
            }

            customModes[stepIndex] = customModes[stepIndex].cycled()
            cycle.customStepModes = customModes
        }
    }

    func renameCycle(
        slot: CycleSlot,
        name: String
    ) {
        settings.updateGridCycle(slot: slot) { cycle in
            cycle.name = Self.normalizedName(
                name,
                fallback: "Cycle \(slot.rawValue)"
            )
        }
    }

    func setLaneEnabled(
        _ isEnabled: Bool,
        lane: LaneID
    ) {
        settings.updateLevelLane(lane: lane) { configuration in
            configuration.isEnabled = isEnabled
        }
        if !isEnabled {
            seenTelemetrySlotsByLane.removeValue(forKey: lane)
        }
        refreshLevelSidebarState(at: currentDate())
    }

    func setLaneTargetLevel(
        _ targetLevelDB: Double,
        lane: LaneID
    ) {
        settings.updateLevelLane(lane: lane) { configuration in
            configuration.targetLevelDB = targetLevelDB
        }
    }

    func setLaneTargetMargin(
        _ targetMarginDB: Double,
        lane: LaneID
    ) {
        settings.updateLevelLane(lane: lane) { configuration in
            configuration.targetMarginDB = targetMarginDB
        }
    }

    func setLaneHistoryRange(
        _ historyRange: HistoryRange,
        lane: LaneID
    ) {
        settings.updateLevelLane(lane: lane) { configuration in
            configuration.historyRange = historyRange
        }
    }

    func renameLane(
        lane: LaneID,
        name: String
    ) {
        settings.updateLevelLane(lane: lane) { configuration in
            configuration.name = Self.normalizedName(
                name,
                fallback: "Source \(lane.rawValue)"
            )
        }
    }

    func setLanePreferredSource(
        _ sourceSlot: Int?,
        sourceName: String?,
        lane: LaneID
    ) {
        settings.updateLevelLane(lane: lane) { configuration in
            configuration.preferredSourceSlot = sourceSlot
            configuration.preferredSourceName = sourceName
        }
        if seenTelemetrySlotsByLane[lane] != sourceSlot {
            seenTelemetrySlotsByLane.removeValue(forKey: lane)
        }
        refreshLevelSidebarState(at: currentDate())
    }

    func workspaceSnapshot(at date: Date) -> DesktopWorkspaceSnapshot {
        let externalSnapshot = currentExternalTransportSnapshot()
        let transportBeatContext = transportBeatContext(
            at: date,
            externalSnapshot: externalSnapshot
        )
        let elapsedSeconds = transportBeatContext?.elapsedSeconds ?? 0
        let elapsedMilliseconds = UInt64(
            max((elapsedSeconds * 1_000.0).rounded(), 0)
        )
        let gridFrame = gridPreviewDriver.makeFrame(
            settings: settings.gridCycles,
            beat: transportBeatContext?.effectiveBeat ?? 0
        )
        let levelTelemetry = levelTelemetryReceiver.snapshot(at: date)
        let levelSnapshot = levelRuntimeDriver.snapshot(
            now: date,
            elapsedMilliseconds: elapsedMilliseconds,
            laneConfigurations: settings.levelLanes,
            telemetry: levelTelemetry
        )

        return DesktopWorkspaceSnapshot(
            gridFrame: gridFrame,
            levelExpandedFrame: levelSnapshot.expandedFrame,
            levelSplitFrame: levelSnapshot.splitFrame
        )
    }

    func toolbarSnapshot(at date: Date) -> DesktopToolbarSnapshot {
        let linkSnapshot = currentLinkSnapshot()
        let usbSnapshot = currentUSBMIDISnapshot()
        let externalSnapshot = currentExternalTransportSnapshot(
            linkSnapshot: linkSnapshot,
            usbSnapshot: usbSnapshot
        )
        let transportBeatContext = transportBeatContext(
            at: date,
            externalSnapshot: externalSnapshot
        )

        return DesktopToolbarSnapshot(
            elapsedText: DesktopShellFormatters.elapsedTime(
                transportBeatContext?.elapsedSeconds ?? 0
            ),
            bpmText: displayedBPMText(
                linkSnapshot: linkSnapshot,
                usbSnapshot: usbSnapshot
            ),
            syncStatus: syncStatusDescriptor(
                linkSnapshot: linkSnapshot,
                usbSnapshot: usbSnapshot
            )
        )
    }

    func metronomeToolbarIcon(at date: Date) -> KairosIcon {
        guard settings.isMetronomeEnabled else {
            return .metronomeDefault
        }

        guard let transportBeatContext = transportBeatContext(
            at: date,
            externalSnapshot: currentExternalTransportSnapshot()
        ) else {
            return .metronomeDefault
        }

        return Int(floor(transportBeatContext.effectiveBeat)).isMultiple(of: 2)
            ? .metronomePing
            : .metronomePong
    }

    private func syncStatusDescriptor(
        linkSnapshot: AbletonLinkSnapshot?,
        usbSnapshot: USBMIDISyncSnapshot?
    ) -> SyncStatusDescriptor {
        switch settings.syncSource {
        case .internalClock:
            return SyncStatusDescriptor(
                text: "Internal",
                tone: .neutral,
                showsLinkIcon: false
            )
        case .usb:
            guard let usbSnapshot, usbSnapshot.isBridgeAvailable else {
                return SyncStatusDescriptor(
                    text: "USB unavailable",
                    tone: .danger,
                    showsLinkIcon: false
                )
            }

            guard usbSnapshot.hasSelection else {
                return SyncStatusDescriptor(
                    text: "USB no source",
                    tone: .neutral,
                    showsLinkIcon: false
                )
            }

            guard usbSnapshot.isSelectedSourceAvailable else {
                return SyncStatusDescriptor(
                    text: "USB source lost",
                    tone: .danger,
                    showsLinkIcon: false
                )
            }

            guard usbSnapshot.hasReceivedMessages else {
                return SyncStatusDescriptor(
                    text: "USB waiting",
                    tone: .neutral,
                    showsLinkIcon: false
                )
            }

            return SyncStatusDescriptor(
                text: usbSnapshot.isPlaying ? "USB active" : "USB connected",
                tone: usbSnapshot.isPlaying ? .success : .neutral,
                showsLinkIcon: false
            )
        case .link:
            guard let linkSnapshot, linkSnapshot.isEnabled else {
                return SyncStatusDescriptor(
                    text: "Link off",
                    tone: .danger,
                    showsLinkIcon: true
                )
            }

            if linkSnapshot.peerCount == 0 {
                return SyncStatusDescriptor(
                    text: "Link active - no peers",
                    tone: .neutral,
                    showsLinkIcon: true
                )
            }

            let peerLabel = linkSnapshot.peerCount == 1 ? "peer" : "peers"
            return SyncStatusDescriptor(
                text: "Link active - \(linkSnapshot.peerCount) \(peerLabel)",
                tone: .success,
                showsLinkIcon: true
            )
        }
    }

    private func synchronizeTransportState() {
        switch settings.syncSource {
        case .internalClock:
            externalTransportHoldSeconds = 0
            externalElapsedResetOriginSeconds = 0
            releaseLinkBridge()
        case .usb:
            synchronizeUSBSourceSelection()
            releaseLinkBridge()
            isPreviewPlaying = false
            playbackStartedAt = nil
            accumulatedElapsed = 0
            externalTransportHoldSeconds = 0
            externalElapsedResetOriginSeconds = 0
        case .link:
            let bridge = ensureLinkBridge()
            bridge.setActive(true)
            bridge.seedTempo(Double(settings.bpm))
            isPreviewPlaying = false
            playbackStartedAt = nil
            accumulatedElapsed = 0
            externalTransportHoldSeconds = 0
            externalElapsedResetOriginSeconds = 0
        }
    }

    private func startLinkStatusMonitor() {
        linkStatusTask?.cancel()
        linkStatusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                self.refreshLinkStatus()
                self.refreshUSBMIDISyncState()

                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    private func startMetronomeMonitor() {
        metronomeTask?.cancel()
        metronomeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                self.refreshMetronomeScheduling()

                do {
                    try await Task.sleep(for: .milliseconds(25))
                } catch {
                    return
                }
            }
        }
    }

    private func refreshLinkStatus() {
        guard let bridge = abletonLinkBridge else {
            latestLinkSnapshot = nil
            if settings.linkStatus != .off {
                settings.linkStatus = .off
            }
            return
        }

        let snapshot = bridge.captureSnapshot()
        latestLinkSnapshot = snapshot
        let nextStatus = LinkStatus(
            isEnabled: snapshot.isEnabled,
            peerCount: snapshot.peerCount,
            tempoBPM: snapshot.tempoBPM
        )
        guard settings.linkStatus != nextStatus else {
            return
        }

        settings.linkStatus = nextStatus
    }

    private func refreshUSBMIDISyncState() {
        let bridge = ensureUSBMIDISyncBridge()
        let nextSources = bridge.refreshSources()
        if usbMIDISources != nextSources {
            usbMIDISources = nextSources
        }

        latestUSBMIDISnapshot = bridge.captureSnapshot()
    }

    private func startLevelStatusMonitor() {
        levelStatusTask?.cancel()
        levelStatusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                self.refreshLevelSidebarState(at: self.currentDate())

                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    private func refreshLevelSidebarState(at date: Date) {
        let telemetry = levelTelemetryReceiver.snapshot(at: date)
        let sidebarTelemetry = stableSidebarTelemetry(from: telemetry)
        if levelTelemetrySnapshot != sidebarTelemetry {
            levelTelemetrySnapshot = sidebarTelemetry
        }

        let resolvedLaneStatuses = resolveLaneStatuses(
            telemetry: telemetry
        )
        if laneStatuses != resolvedLaneStatuses {
            laneStatuses = resolvedLaneStatuses
        }
    }

    private func stableSidebarTelemetry(
        from snapshot: LevelTelemetrySnapshot
    ) -> LevelTelemetrySnapshot {
        LevelTelemetrySnapshot(
            isListening: snapshot.isListening,
            port: snapshot.port,
            errorMessage: snapshot.errorMessage,
            sources: snapshot.sources.map { source in
                LevelTelemetrySourceState(
                    sourceSlot: source.sourceSlot,
                    sourceName: source.sourceName,
                    rmsLeft: 0,
                    rmsRight: 0,
                    peakLeft: 0,
                    peakRight: 0,
                    isActive: source.isActive,
                    hasConflict: source.hasConflict,
                    lastReceivedAt: nil,
                    endpoint: nil
                )
            }
        )
    }

    private func resolveLaneStatuses(
        telemetry: LevelTelemetrySnapshot
    ) -> [LaneID: LevelLaneConnectionStatus] {
        var nextSeenTelemetrySlotsByLane = seenTelemetrySlotsByLane
        var statuses: [LaneID: LevelLaneConnectionStatus] = [:]

        for configuration in settings.levelLanes {
            guard configuration.isEnabled else {
                statuses[configuration.lane] = .disabled(for: configuration.lane)
                continue
            }

            if let source = telemetry.source(for: configuration.preferredSourceSlot) {
                nextSeenTelemetrySlotsByLane[configuration.lane] = source.sourceSlot
                statuses[configuration.lane] = .connected(
                    lane: configuration.lane,
                    slot: source.sourceSlot
                )
                continue
            }

            let preferredSlot = configuration.preferredSourceSlot
            let hasSeenPreferredSlot = nextSeenTelemetrySlotsByLane[configuration.lane] == preferredSlot

            statuses[configuration.lane] = hasSeenPreferredSlot
                ? .disconnected(lane: configuration.lane, slot: preferredSlot)
                : .waiting(lane: configuration.lane, slot: preferredSlot)
        }

        seenTelemetrySlotsByLane = nextSeenTelemetrySlotsByLane
        return statuses
    }

    private func currentLinkSnapshot() -> AbletonLinkSnapshot? {
        settings.syncSource == .link
            ? abletonLinkBridge?.captureSnapshot()
            : latestLinkSnapshot
    }

    private func currentUSBMIDISnapshot() -> USBMIDISyncSnapshot? {
        settings.syncSource == .usb
            ? usbMIDISyncBridge?.captureSnapshot()
            : latestUSBMIDISnapshot
    }

    private func currentUSBMIDISourceDisplayName(
        snapshot: USBMIDISyncSnapshot?
    ) -> String? {
        if let selectedSourceName = snapshot?.selectedSourceName,
           !selectedSourceName.isEmpty {
            return selectedSourceName
        }

        if let selectedUniqueID = settings.usbMIDISource.uniqueID,
           let sourceName = usbMIDISources.first(
               where: { $0.uniqueID == selectedUniqueID }
           )?.displayName {
            return sourceName
        }

        return settings.usbMIDISource.displayName
    }

    private func currentExternalTransportSnapshot() -> ExternalTransportSnapshot? {
        currentExternalTransportSnapshot(
            linkSnapshot: currentLinkSnapshot(),
            usbSnapshot: currentUSBMIDISnapshot()
        )
    }

    private func currentExternalTransportSnapshot(
        linkSnapshot: AbletonLinkSnapshot?,
        usbSnapshot: USBMIDISyncSnapshot?
    ) -> ExternalTransportSnapshot? {
        switch settings.syncSource {
        case .internalClock:
            return nil
        case .usb:
            guard let usbSnapshot else {
                return nil
            }

            return ExternalTransportSnapshot(
                isEnabled: usbSnapshot.isBridgeAvailable
                    && usbSnapshot.hasSelection
                    && usbSnapshot.isSelectedSourceAvailable,
                isPlaying: usbSnapshot.isPlaying,
                tempoBPM: usbSnapshot.tempoBPM,
                elapsedSeconds: usbSnapshot.elapsedSeconds
            )
        case .link:
            guard let linkSnapshot else {
                return nil
            }

            return ExternalTransportSnapshot(
                isEnabled: linkSnapshot.isEnabled,
                isPlaying: linkSnapshot.isPlaying,
                tempoBPM: linkSnapshot.tempoBPM,
                elapsedSeconds: linkSnapshot.elapsedSeconds
            )
        }
    }

    private func ensureLinkBridge() -> AbletonLinkBridge {
        if let abletonLinkBridge {
            return abletonLinkBridge
        }

        let bridge = AbletonLinkBridge(initialTempo: Double(settings.bpm))
        abletonLinkBridge = bridge
        return bridge
    }

    private func ensureUSBMIDISyncBridge() -> USBMIDISyncBridge {
        if let usbMIDISyncBridge {
            return usbMIDISyncBridge
        }

        let bridge = USBMIDISyncBridge()
        usbMIDISyncBridge = bridge
        return bridge
    }

    private func synchronizeUSBSourceSelection() {
        ensureUSBMIDISyncBridge().setSelectedSource(settings.usbMIDISource)
    }

    private func releaseLinkBridge() {
        abletonLinkBridge?.setActive(false)
        abletonLinkBridge = nil
        latestLinkSnapshot = nil
        settings.linkStatus = .off
        externalElapsedResetOriginSeconds = 0
    }

    private func releaseUSBMIDISyncBridge() {
        usbMIDISyncBridge = nil
        latestUSBMIDISnapshot = nil
        usbMIDISources = []
    }

    private func refreshMetronomeScheduling(
        at date: Date? = nil,
        reset: Bool = false
    ) {
        if reset {
            metronomeClickEngine.stop()
        }

        guard
            hasStartedRuntime,
            let context = currentMetronomeScheduleContext(
                at: date ?? currentDate()
            )
        else {
            metronomeClickEngine.stop()
            return
        }

        metronomeClickEngine.schedule(context: context)
    }

    private func transportBeatContext(
        at date: Date,
        externalSnapshot: ExternalTransportSnapshot? = nil
    ) -> TransportBeatContext? {
        let resolvedExternalSnapshot = externalSnapshot ?? currentExternalTransportSnapshot()
        let elapsedSeconds = previewElapsedSeconds(
            at: date,
            externalSnapshot: resolvedExternalSnapshot
        )
        let tempoBPM = currentDisplayedBPM(
            externalSnapshot: resolvedExternalSnapshot
        ) ?? Double(settings.bpm)

        return TransportBeatResolver.resolve(
            elapsedSeconds: elapsedSeconds,
            tempoBPM: tempoBPM,
            offset: settings.offset
        )
    }

    private func currentMetronomeScheduleContext(
        at date: Date
    ) -> MetronomeScheduleContext? {
        guard settings.isMetronomeEnabled else {
            return nil
        }

        let externalSnapshot = currentExternalTransportSnapshot()
        guard let beatContext = transportBeatContext(
            at: date,
            externalSnapshot: externalSnapshot
        ) else {
            return nil
        }

        switch settings.syncSource {
        case .internalClock:
            guard isPreviewPlaying else {
                return nil
            }
            return MetronomeScheduleContext(
                currentBeat: beatContext.beat,
                tempoBPM: beatContext.tempoBPM,
                pulse: settings.metronomePulse,
                offset: settings.offset
            )
        case .usb, .link:
            guard
                let externalSnapshot,
                externalSnapshot.isEnabled,
                externalSnapshot.isPlaying,
                beatContext.tempoBPM > 0
            else {
                return nil
            }

            return MetronomeScheduleContext(
                currentBeat: beatContext.beat,
                tempoBPM: beatContext.tempoBPM,
                pulse: settings.metronomePulse,
                offset: settings.offset
            )
        }
    }

    private func previewElapsedSeconds(
        at date: Date,
        externalSnapshot: ExternalTransportSnapshot?
    ) -> TimeInterval {
        switch settings.syncSource {
        case .internalClock:
            return elapsedTime(at: date)
        case .usb, .link:
            guard let externalSnapshot, externalSnapshot.isEnabled else {
                return externalTransportHoldSeconds
            }

            let adjustedElapsedSeconds = TransportBeatResolver.adjustedExternalElapsedSeconds(
                rawElapsedSeconds: externalSnapshot.elapsedSeconds,
                resetOriginSeconds: externalElapsedResetOriginSeconds,
                heldElapsedSeconds: externalTransportHoldSeconds,
                isPlaying: externalSnapshot.isPlaying
            )
            if externalSnapshot.isPlaying {
                externalTransportHoldSeconds = adjustedElapsedSeconds
            }

            return externalTransportHoldSeconds
        }
    }

    private func elapsedTime(at date: Date) -> TimeInterval {
        guard isPreviewPlaying, let playbackStartedAt else {
            return accumulatedElapsed
        }

        return accumulatedElapsed + max(date.timeIntervalSince(playbackStartedAt), 0)
    }

    private func displayedBPMText(
        linkSnapshot: AbletonLinkSnapshot?,
        usbSnapshot: USBMIDISyncSnapshot?
    ) -> String {
        if let displayedBPM = currentDisplayedBPM(
            externalSnapshot: currentExternalTransportSnapshot(
                linkSnapshot: linkSnapshot,
                usbSnapshot: usbSnapshot
            )
        ) {
            return DesktopShellFormatters.bpm(displayedBPM)
        }

        return DesktopShellFormatters.bpm(settings.bpm)
    }

    private func currentDisplayedBPM(
        externalSnapshot: ExternalTransportSnapshot?
    ) -> Double? {
        guard
            settings.syncSource != .internalClock,
            let externalSnapshot,
            externalSnapshot.tempoBPM > 0
        else {
            return nil
        }

        return externalSnapshot.tempoBPM
    }

    private static func normalizedName(
        _ name: String,
        fallback: String
    ) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct DesktopWorkspaceSnapshot {
    let gridFrame: GridRenderFrame
    let levelExpandedFrame: LevelRenderFrame
    let levelSplitFrame: LevelRenderFrame
}

struct DesktopToolbarSnapshot {
    let elapsedText: String
    let bpmText: String
    let syncStatus: SyncStatusDescriptor
}

private struct ExternalTransportSnapshot {
    let isEnabled: Bool
    let isPlaying: Bool
    let tempoBPM: Double
    let elapsedSeconds: TimeInterval
}

struct TransportBeatContext: Equatable {
    let elapsedSeconds: TimeInterval
    let tempoBPM: Double
    let beat: Double
    let effectiveBeat: Double
}

enum TransportBeatResolver {
    static func adjustedExternalElapsedSeconds(
        rawElapsedSeconds: TimeInterval,
        resetOriginSeconds: TimeInterval,
        heldElapsedSeconds: TimeInterval,
        isPlaying: Bool
    ) -> TimeInterval {
        let adjustedElapsedSeconds = max(
            rawElapsedSeconds - resetOriginSeconds,
            0
        )
        return isPlaying ? adjustedElapsedSeconds : heldElapsedSeconds
    }

    static func resolve(
        elapsedSeconds: TimeInterval,
        tempoBPM: Double,
        offset: Offset
    ) -> TransportBeatContext? {
        guard tempoBPM > 0 else {
            return nil
        }

        let beat = max(0, elapsedSeconds * (tempoBPM / 60.0))
        return TransportBeatContext(
            elapsedSeconds: elapsedSeconds,
            tempoBPM: tempoBPM,
            beat: beat,
            effectiveBeat: beat + offset.beats(atTempo: tempoBPM)
        )
    }
}

struct SyncStatusDescriptor {
    enum Tone {
        case neutral
        case success
        case danger

        var color: Color {
            switch self {
            case .neutral:
                return DesktopShellTokens.textTertiary
            case .success:
                return DesktopShellTokens.statusSuccess
            case .danger:
                return DesktopShellTokens.statusDanger
            }
        }
    }

    let text: String
    let tone: Tone
    let showsLinkIcon: Bool
}

enum SidebarInputStatusTone: Equatable {
    case hidden
    case waiting
    case connected
    case disconnected
}

protocol SidebarInputStatusDescriptor {
    var sidebarStatusTone: SidebarInputStatusTone { get }
    var sidebarStatusLabel: String { get }
}

struct LevelLaneConnectionStatus: Equatable {
    enum State: Equatable {
        case disabled
        case waiting
        case connected
        case disconnected
    }

    let lane: LaneID
    let state: State
    let displayLabel: String

    static func disabled(for lane: LaneID) -> LevelLaneConnectionStatus {
        LevelLaneConnectionStatus(
            lane: lane,
            state: .disabled,
            displayLabel: ""
        )
    }

    static func waiting(
        lane: LaneID,
        slot: Int?
    ) -> LevelLaneConnectionStatus {
        LevelLaneConnectionStatus(
            lane: lane,
            state: .waiting,
            displayLabel: slot.map { "Waiting for Max4live Slot \($0)" } ?? "Waiting for Max4live Slot"
        )
    }

    static func connected(
        lane: LaneID,
        slot: Int
    ) -> LevelLaneConnectionStatus {
        LevelLaneConnectionStatus(
            lane: lane,
            state: .connected,
            displayLabel: "Max4live Slot \(slot)"
        )
    }

    static func disconnected(
        lane: LaneID,
        slot: Int?
    ) -> LevelLaneConnectionStatus {
        LevelLaneConnectionStatus(
            lane: lane,
            state: .disconnected,
            displayLabel: slot.map { "Max4live Slot \($0)" } ?? "Max4live Slot"
        )
    }
}

extension LevelLaneConnectionStatus: SidebarInputStatusDescriptor {
    var sidebarStatusTone: SidebarInputStatusTone {
        switch state {
        case .disabled:
            return .hidden
        case .waiting:
            return .waiting
        case .connected:
            return .connected
        case .disconnected:
            return .disconnected
        }
    }

    var sidebarStatusLabel: String {
        displayLabel
    }
}

struct SyncInputConnectionStatus: Equatable, SidebarInputStatusDescriptor {
    let sidebarStatusTone: SidebarInputStatusTone
    let sidebarStatusLabel: String

    static func waiting(_ label: String) -> SyncInputConnectionStatus {
        SyncInputConnectionStatus(
            sidebarStatusTone: .waiting,
            sidebarStatusLabel: label
        )
    }

    static func connected(_ sourceName: String) -> SyncInputConnectionStatus {
        SyncInputConnectionStatus(
            sidebarStatusTone: .connected,
            sidebarStatusLabel: "\(sourceName) connected"
        )
    }

    static func disconnected(_ label: String) -> SyncInputConnectionStatus {
        SyncInputConnectionStatus(
            sidebarStatusTone: .disconnected,
            sidebarStatusLabel: label
        )
    }
}

struct DesktopShellRootView: View {
    @State private var model = DesktopShellModel()

    var body: some View {
        DesktopShellView(model: model)
        .task {
            model.startRuntimeIfNeeded()
        }
        .onDisappear {
            model.stopRuntime()
        }
        .frame(minWidth: 1_280, minHeight: 820)
        .background(DesktopShellTokens.backgroundCanvas)
    }
}

private struct DesktopShellView: View {
    let model: DesktopShellModel
    @State private var dropdownCoordinator = FloatingDropdownCoordinator()

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                DesktopToolbarView(model: model)

                HStack(spacing: 0) {
                    if model.isSidebarVisible {
                        DesktopSidebarWrapper {
                            DesktopSidebarView(model: model)
                        }
                    }

                    DesktopWorkspaceLiveView(model: model)
                }
                // No top padding here: the toolbar already provides the gap below it.
                // Adding it again would double the canvas-colored space.
                .padding(.trailing, DesktopShellTokens.layoutGapLG)
                .padding(.bottom, DesktopShellTokens.layoutGapLG)
            }

            if let presentation = dropdownCoordinator.presentation {
                FloatingDropdownOverlay(
                    presentation: presentation,
                    onDismiss: dropdownCoordinator.dismiss
                )
                .zIndex(10_000)
            }
        }
        .coordinateSpace(name: DesktopShellTokens.shellCoordinateSpace)
        .environment(\.floatingDropdownCoordinator, dropdownCoordinator)
        .background(DesktopShellTokens.backgroundCanvas)
    }
}


extension EnvironmentValues {
    var floatingDropdownCoordinator: FloatingDropdownCoordinator? {
        get { self[FloatingDropdownCoordinatorKey.self] }
        set { self[FloatingDropdownCoordinatorKey.self] = newValue }
    }
}

extension View {
    func captureSize(_ size: Binding<CGSize>) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        size.wrappedValue = geometry.size
                    }
                    .onChange(of: geometry.size) { _, nextSize in
                        size.wrappedValue = nextSize
                    }
            }
        }
    }
}

extension View {
    func captureWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        width.wrappedValue = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, nextWidth in
                        width.wrappedValue = nextWidth
                    }
            }
        }
    }

    func captureFrame(
        in coordinateSpace: CoordinateSpace,
        to frame: Binding<CGRect>
    ) -> some View {
        background {
            GeometryReader { geometry in
                let currentFrame = geometry.frame(in: coordinateSpace)

                Color.clear
                    .onAppear {
                        frame.wrappedValue = currentFrame
                    }
                    .onChange(of: currentFrame) { _, nextFrame in
                        frame.wrappedValue = nextFrame
                    }
            }
        }
    }
}
func buttonSurface<Content: View>(
    kind: ButtonSurfaceKind,
    isActive: Bool = false,
    isHovered: Bool = false,
    isPressed: Bool = false,
    isDisabled: Bool = false,
    @ViewBuilder content: () -> Content
) -> some View {
    let fillColor: Color
    let borderColor: Color
    let cornerRadius: CGFloat

    switch kind {
    case .ghost:
        // Figma `button/ghost`: the default state has no fill and no border, and
        // it never adopts the accent/primary fill. The folded menu state is
        // rendered by the surrounding container; the trigger itself only takes
        // the pressed surface while actively clicking.
        if isPressed {
            fillColor = DesktopShellTokens.backgroundSurface
        } else if isHovered {
            fillColor = DesktopShellTokens.actionSecondaryHover
        } else {
            fillColor = .clear
        }
        borderColor = .clear
        cornerRadius = DesktopShellTokens.radiusSurface
    case .filled:
        fillColor = isActive ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary
        borderColor = .clear
        cornerRadius = DesktopShellTokens.radiusSurface
    case .outlined:
        // Figma `button/tertiary` default: transparent fill + 0.5px subtle
        // border. The folded state is handled by the outer dropdown container.
        fillColor = (isHovered || isPressed) ? DesktopShellTokens.actionSecondaryHover : .clear
        borderColor = DesktopShellTokens.borderSubtle
        cornerRadius = DesktopShellTokens.radiusElevated
    case .secondary:
        if isActive {
            fillColor = DesktopShellTokens.actionHighlight
            borderColor = .clear
        } else if isHovered || isPressed {
            fillColor = DesktopShellTokens.actionSecondaryHover
            borderColor = .clear
        } else {
            fillColor = DesktopShellTokens.backgroundElevated
            borderColor = DesktopShellTokens.borderSubtle
        }
        cornerRadius = DesktopShellTokens.radiusSurface
    case .modalSecondary:
        if isActive {
            fillColor = DesktopShellTokens.actionHighlight
        } else if isHovered || isPressed {
            fillColor = DesktopShellTokens.actionSecondaryHover
        } else {
            fillColor = DesktopShellTokens.backgroundModalsButton
        }
        borderColor = .clear
        cornerRadius = DesktopShellTokens.radiusElevated
    case .subButton:
        fillColor = (isHovered || isPressed) ? DesktopShellTokens.actionSecondaryHover : .clear
        borderColor = .clear
        cornerRadius = DesktopShellTokens.radiusElevated
    }

    return content()
        .padding(.horizontal, DesktopShellTokens.componentGapSM)
        .frame(minHeight: DesktopShellTokens.controlHeight)
        .background(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .fill(fillColor.opacity(isDisabled ? 0.45 : 1))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .stroke(
                borderColor,
                lineWidth: {
                    switch kind {
                    case .outlined, .secondary, .modalSecondary:
                        return DesktopShellTokens.borderWidth
                    case .ghost, .filled, .subButton:
                        return 0
                    }
                }()
            )
        )
}

private extension PresetLibrary {
    mutating func replace(preset: StoredPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }

        presets[index] = preset
    }

    mutating func append(preset: StoredPreset) {
        presets.append(preset)
        presets = SettingsDefaults.normalizeStoredPresets(presets)
    }

    mutating func removePreset(id: String) {
        presets.removeAll { $0.id == id }
        presets = SettingsDefaults.normalizeStoredPresets(presets)
    }

    func storedPreset(for presetID: String) -> StoredPreset? {
        presets.first(where: { $0.id == presetID })
    }

    var defaultPreset: StoredPreset {
        storedPreset(for: StoredPreset.defaultID) ?? .factoryDefault
    }
}

extension SyncSource {
    var buttonLabel: String {
        switch self {
        case .internalClock:
            return "Internal"
        case .usb:
            return "USB"
        case .link:
            return "Link"
        }
    }
}

extension StepNumber {
    var displayLabel: String {
        "\(rawValue)"
    }
}

extension Pulse {
    var displayLabel: String {
        switch self {
        case .oneSixteenth:
            return "1/16"
        case .oneEighth:
            return "1/8"
        case .oneQuarter:
            return "1/4"
        case .oneHalf:
            return "1/2"
        case .one:
            return "1"
        case .two:
            return "2"
        case .four:
            return "4"
        case .eight:
            return "8"
        case .sixteen:
            return "16"
        case .thirtyTwo:
            return "32"
        case .sixtyFour:
            return "64"
        }
    }
}

extension HistoryRange {
    var displayLabel: String {
        switch self {
        case .twoSeconds:
            return "2 sec"
        case .fiveSeconds:
            return "5 sec"
        case .tenSeconds:
            return "10 sec"
        case .thirtySeconds:
            return "30 sec"
        case .oneMinute:
            return "1 min"
        case .twoMinutes:
            return "2 min"
        }
    }
}

extension GridVisualMode {
    var icon: KairosIcon {
        switch self {
        case .block:
            return .modeBlock
        case .border:
            return .modeBorder
        case .line:
            return .modeLine
        case .custom:
            return .modeCustom
        }
    }
}

private extension GridVisualMode {
    var uniformDisplayMode: GridStepDisplayMode? {
        switch self {
        case .block:
            return .block
        case .border:
            return .border
        case .line:
            return .line
        case .custom:
            return nil
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
