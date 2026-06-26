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

    fileprivate func metronomeToolbarIcon(at date: Date) -> KairosIcon {
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

private struct DesktopToolbarView: View {
    let model: DesktopShellModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let snapshot = model.toolbarSnapshot(at: timeline.date)

            HStack(spacing: DesktopShellTokens.componentGapXL) {
                HStack(spacing: DesktopShellTokens.componentGapXL) {
                    Text("KAIROS")
                        .font(DesktopShellTypography.wordmark)
                        .foregroundStyle(DesktopShellTokens.textTertiary)

                    PresetSelectorButton(
                        activePreset: model.activePreset,
                        presets: model.availablePresets,
                        onSelect: { presetID in
                            model.selectPreset(presetID)
                        },
                        onSave: {
                            Task {
                                await model.saveCurrentPreset()
                            }
                        },
                        onAdd: {
                            Task {
                                await model.addPreset()
                            }
                        },
                        onRename: { presetID, name in
                            Task {
                                await model.renamePreset(presetID, to: name)
                            }
                        },
                        onRemove: { presetID in
                            Task {
                                await model.removePreset(presetID)
                            }
                        }
                    )

                    HStack(spacing: DesktopShellTokens.componentGapXS) {
                        ToolbarIconButton(
                            icon: model.isSidebarVisible ? .sidebar : .sidebarFolded,
                            isActive: model.isSidebarVisible,
                            action: model.toggleSidebar
                        )

                        ToolbarIconButton(
                            icon: model.isPreviewPlaying ? .stop : .play,
                            isDisabled: !model.canControlTransport,
                            action: model.togglePlay
                        )

                        ToolbarIconButton(
                            icon: .reset,
                            action: model.resetPreview
                        )

                        ToolbarIconButton(
                            icon: model.metronomeToolbarIcon(at: timeline.date),
                            isActive: model.settings.isMetronomeEnabled,
                            action: model.toggleMetronome
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DesktopToolbarLiveDataView(
                    snapshot: snapshot,
                    canEditTempo: model.canEditTempo
                )
                .fixedSize()
            }
            .padding(.horizontal, DesktopShellTokens.componentGapLG)
            .padding(.vertical, DesktopShellTokens.componentGapSM)
            .frame(height: DesktopShellTokens.toolbarHeight)
            .background(DesktopShellTokens.backgroundCanvas)
        }
    }
}

private struct DesktopToolbarLiveDataView: View {
    let snapshot: DesktopToolbarSnapshot
    let canEditTempo: Bool

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapLG) {
            DataAtomView(
                text: snapshot.elapsedText,
                width: DesktopShellTokens.toolbarTimeWidth
            )
            DataAtomView(
                text: snapshot.bpmText,
                width: DesktopShellTokens.toolbarBPMWidth,
                isDisabled: !canEditTempo
            )
            // Sync status hugs its content and the whole cluster is pinned to the
            // trailing edge, so the data is flush with the layout's right margin
            // (no empty gap after the sync text), per the Figma toolbar.
            SyncStatusView(descriptor: snapshot.syncStatus)
                .layoutPriority(1)
        }
    }
}

private struct DesktopSidebarWrapper<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
                .frame(width: DesktopShellTokens.sidebarWidth)
            Color.clear
                .frame(width: DesktopShellTokens.sidebarOuterWidth - DesktopShellTokens.sidebarWidth)
        }
        .frame(width: DesktopShellTokens.sidebarOuterWidth, alignment: .leading)
    }
}

private struct SidebarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DesktopSidebarView: View {
    let model: DesktopShellModel

    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrolling = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { outer in
            let viewport = outer.size.height

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
                    GlobalSidebarSection(model: model)

                    GridSidebarSection(model: model)

                    LevelSidebarSection(
                        model: model,
                        telemetry: model.levelTelemetrySnapshot,
                        laneStatuses: model.laneStatuses
                    )
                }
                .padding(DesktopShellTokens.layoutGapLG)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { inner in
                        Color.clear
                            .onAppear { contentHeight = inner.size.height }
                            .onChange(of: inner.size.height) { _, height in
                                contentHeight = height
                            }
                            .preference(
                                key: SidebarScrollOffsetKey.self,
                                value: -inner.frame(in: .named("sidebarScroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "sidebarScroll")
            .onPreferenceChange(SidebarScrollOffsetKey.self) { offset in
                scrollOffset = offset
                flashScrollIndicator()
            }
            .overlay(alignment: .topTrailing) {
                scrollIndicator(viewport: viewport)
            }
        }
        .background(DesktopShellTokens.backgroundSurface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusCanvas,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func scrollIndicator(viewport: CGFloat) -> some View {
        let maxScroll = max(contentHeight - viewport, 0)
        if maxScroll > 1 {
            let thumbHeight = DesktopShellTokens.scrollThumbLength
            let travel = max(viewport - thumbHeight, 0)
            let progress = min(max(scrollOffset / maxScroll, 0), 1)

            Capsule(style: .continuous)
                .fill(DesktopShellTokens.actionSecondary)
                .frame(width: DesktopShellTokens.scrollThumbWidth, height: thumbHeight)
                .offset(y: progress * travel)
                .padding(.trailing, DesktopShellTokens.componentGapXS)
                .opacity(isScrolling ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: isScrolling)
                .allowsHitTesting(false)
        }
    }

    // Show the scroll indicator while the user is scrolling and fade it out once
    // scrolling settles, mirroring the native overlay-scrollbar behavior.
    private func flashScrollIndicator() {
        isScrolling = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !Task.isCancelled {
                isScrolling = false
            }
        }
    }
}

private struct GlobalSidebarSection: View {
    let model: DesktopShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            Text("Global")
                .font(DesktopShellTypography.titleMD)
                .foregroundStyle(DesktopShellTokens.textSecondary)

            VStack(spacing: DesktopShellTokens.layoutGapSM) {
                SidebarCardSection(title: "Sync") {
                    VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
                        VStack(alignment: .leading, spacing: DesktopShellTokens.componentGapXL) {
                            HStack(spacing: DesktopShellTokens.layoutGapLG) {
                                SegmentButton(
                                    title: SyncSource.internalClock.buttonLabel,
                                    isSelected: model.settings.syncSource == .internalClock,
                                    action: {
                                        model.setSyncSource(.internalClock)
                                    }
                                )

                                USBSyncSegmentButton(
                                    title: SyncSource.usb.buttonLabel,
                                    isSelected: model.settings.syncSource == .usb,
                                    action: {
                                        model.activateUSBMIDISync()
                                    }
                                ) {
                                    if model.usbMIDISources.isEmpty {
                                        Button("No USB MIDI devices connected") {}
                                            .disabled(true)
                                    } else {
                                        ForEach(model.usbMIDISources) { source in
                                            Button {
                                                model.selectUSBMIDISource(source)
                                            } label: {
                                                if model.settings.usbMIDISource.uniqueID == source.uniqueID {
                                                    Label(source.displayName, systemImage: "checkmark")
                                                } else {
                                                    Text(source.displayName)
                                                }
                                            }
                                        }
                                    }
                                }

                                SegmentButton(
                                    title: SyncSource.link.buttonLabel,
                                    isSelected: model.settings.syncSource == .link,
                                    action: {
                                        model.setSyncSource(.link)
                                    }
                                )
                            }

                            if let status = model.usbSyncInputStatus {
                                InputStatusView(status: status)
                            }
                        }

                        SidebarValueRow(label: "Latency") {
                            LatencyControl(
                                value: model.settings.offset.milliseconds,
                                range: Offset.minimumMilliseconds...Offset.maximumMilliseconds,
                                step: 0.1,
                                formatter: DesktopShellFormatters.latency,
                                editFormatter: DesktopShellFormatters.latencyInput,
                                parse: { Double($0) },
                                onCommit: model.setLatency,
                                onDecrement: { model.setLatency(max(model.settings.offset.milliseconds - 0.1, Offset.minimumMilliseconds)) },
                                onIncrement: { model.setLatency(min(model.settings.offset.milliseconds + 0.1, Offset.maximumMilliseconds)) }
                            )
                        }
                    }
                }

                SidebarDivider()

                SidebarCardSection(title: "Tempo") {
                    VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapLG) {
                        SidebarValueRow(label: "BPM") {
                            DraggableValueField(
                                value: Double(model.settings.bpm),
                                range: 1...999,
                                step: 1,
                                display: { DesktopShellFormatters.bpmControl(Int($0)) },
                                editText: { String(Int($0)) },
                                parse: { Double($0) },
                                isDisabled: !model.canEditTempo,
                                onCommit: { model.setBPM(Int($0.rounded())) }
                            )
                        }

                        SidebarValueRow(label: "Metronome pulse") {
                            MenuValueButton(
                                title: model.settings.metronomePulse.displayLabel,
                                icon: .chevronDown
                            ) { dismiss in
                                ForEach(DesktopShellFormatters.metronomePulseOptions, id: \.self) { option in
                                    Button(option.title) {
                                        model.setMetronomePulse(option.value)
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesktopShellTokens.layoutGapLG)
            .background {
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
                .fill(DesktopShellTokens.backgroundElevated)
            }

            if let storageErrorMessage = model.storageErrorMessage {
                Text(storageErrorMessage)
                    .font(DesktopShellTypography.labelXS)
                    .foregroundStyle(DesktopShellTokens.statusDanger)
            }
        }
    }
}

private struct LiveSyncStatusView: View {
    let model: DesktopShellModel
    var compact = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            SyncStatusView(
                descriptor: model.toolbarSnapshot(at: timeline.date).syncStatus,
                compact: compact
            )
        }
    }
}

private struct GridSidebarSection: View {
    let model: DesktopShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            HStack(spacing: DesktopShellTokens.layoutGapXL) {
                Text("Grid")
                    .font(DesktopShellTypography.titleMD)
                    .foregroundStyle(DesktopShellTokens.textSecondary)

                ToggleButton(
                    isOn: model.settings.isGridVisible,
                    action: {
                        model.setGridPanelVisibility(!model.settings.isGridVisible)
                    }
                )
            }

            VStack(spacing: DesktopShellTokens.layoutGapSM) {
                ForEach(model.settings.gridCycles, id: \.slot) { cycle in
                    GridCycleCard(
                        cycle: cycle,
                        onRename: { model.renameCycle(slot: cycle.slot, name: $0) },
                        onToggle: { model.setCycleEnabled(!$0.isEnabled, slot: cycle.slot) },
                        onStepNumber: { model.setCycleStepNumber($0, slot: cycle.slot) },
                        onPulse: { model.setCyclePulse($0, slot: cycle.slot) },
                        onMode: { model.setCycleVisualMode($0, slot: cycle.slot) }
                    )

                    if cycle.slot != model.settings.gridCycles.last?.slot {
                        SidebarDivider()
                    }
                }
            }
            // Card supplies the horizontal inset; each cycle owns its vertical
            // padding (Figma `cycle` p-16 + container gap-8 → 24px to each divider).
            .padding(.horizontal, DesktopShellTokens.layoutGapLG)
            .background {
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
                .fill(DesktopShellTokens.backgroundElevated)
            }
        }
    }
}

private struct GridCycleCard: View {
    let cycle: GridCycleSettings
    let onRename: (String) -> Void
    let onToggle: (GridCycleSettings) -> Void
    let onStepNumber: (StepNumber) -> Void
    let onPulse: (Pulse) -> Void
    let onMode: (GridVisualMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            HStack(spacing: DesktopShellTokens.layoutGapXL) {
                RenameableTitle(
                    title: cycle.name,
                    onCommit: onRename
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                PowerIconButton(
                    isOn: cycle.isEnabled,
                    action: {
                        onToggle(cycle)
                    }
                )
            }

            if cycle.isEnabled {
                VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapLG) {
                    SidebarValueRow(label: "Steps") {
                        MenuValueButton(
                            title: cycle.stepNumber.displayLabel,
                            icon: .chevronDown
                        ) { dismiss in
                            ForEach(StepNumber.allCases, id: \.self) { stepNumber in
                                Button(stepNumber.displayLabel) {
                                    onStepNumber(stepNumber)
                                    dismiss()
                                }
                            }
                        }
                    }

                    SidebarValueRow(label: "Pulse") {
                        MenuValueButton(
                            title: cycle.pulse.displayLabel,
                            icon: .chevronDown
                        ) { dismiss in
                            ForEach(Pulse.allCases, id: \.self) { pulse in
                                Button(pulse.displayLabel) {
                                    onPulse(pulse)
                                    dismiss()
                                }
                            }
                        }
                    }

                    SidebarValueRow(label: "Mode") {
                        HStack(spacing: DesktopShellTokens.layoutGapSM) {
                            ForEach(GridVisualMode.allCases, id: \.self) { mode in
                                ModeIconButton(
                                    icon: mode.icon,
                                    isSelected: cycle.visualMode == mode,
                                    action: {
                                        onMode(mode)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, DesktopShellTokens.layoutGapLG)
    }
}

private struct LevelSidebarSection: View {
    let model: DesktopShellModel
    let telemetry: LevelTelemetrySnapshot
    let laneStatuses: [LaneID: LevelLaneConnectionStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            HStack(spacing: DesktopShellTokens.layoutGapXL) {
                Text("Level")
                    .font(DesktopShellTypography.titleMD)
                    .foregroundStyle(DesktopShellTokens.textSecondary)

                ToggleButton(
                    isOn: model.settings.isLevelVisible,
                    action: {
                        model.setLevelPanelVisibility(!model.settings.isLevelVisible)
                    }
                )
            }
            VStack(spacing: DesktopShellTokens.layoutGapSM) {
                ForEach(model.settings.levelLanes, id: \.lane) { lane in
                    LevelLaneCard(
                        lane: lane,
                        telemetry: telemetry,
                        status: laneStatuses[lane.lane],
                        onRename: { model.renameLane(lane: lane.lane, name: $0) },
                        onToggle: { model.setLaneEnabled(!$0.isEnabled, lane: lane.lane) },
                        onSourceSelection: {
                            model.setLanePreferredSource(
                                $0,
                                sourceName: $1,
                                lane: lane.lane
                            )
                        },
                        onTargetLevel: { model.setLaneTargetLevel($0, lane: lane.lane) },
                        onTargetMargin: { model.setLaneTargetMargin($0, lane: lane.lane) },
                        onHistoryRange: { model.setLaneHistoryRange($0, lane: lane.lane) }
                    )

                    if lane.lane != model.settings.levelLanes.last?.lane {
                        SidebarDivider()
                    }
                }
            }
            .padding(.horizontal, DesktopShellTokens.layoutGapLG)
            .background {
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
                .fill(DesktopShellTokens.backgroundElevated)
            }
        }
    }
}

private struct LevelTelemetryStatusView: View {
    let telemetry: LevelTelemetrySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.componentGapSM) {
            HStack(spacing: DesktopShellTokens.componentGapSM) {
                Circle()
                    .fill(statusColor)
                    .frame(width: DesktopShellTokens.statusDotSize, height: DesktopShellTokens.statusDotSize)

                Text(telemetry.statusText)
                    .font(DesktopShellTypography.labelXS)
                    .foregroundStyle(DesktopShellTokens.textTertiary)
                    .lineLimit(2)
            }

            if !telemetry.sources.isEmpty {
                Text(
                    telemetry.sources
                        .map(\.menuTitle)
                        .joined(separator: "  ·  ")
                )
                .font(DesktopShellTypography.labelXS)
                .foregroundStyle(DesktopShellTokens.textTertiary)
                .lineLimit(2)
            }

            if !telemetry.conflictSourceSlots.isEmpty {
                Text(
                    "Resolve duplicate source numbers on S\(telemetry.conflictSourceSlots.map(String.init).joined(separator: ", S"))."
                )
                .font(DesktopShellTypography.labelXS)
                .foregroundStyle(DesktopShellTokens.statusDanger)
                .lineLimit(2)
            }
        }
        .padding(DesktopShellTokens.layoutGapLG)
        .background {
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusCanvas,
                style: .continuous
            )
            .fill(DesktopShellTokens.backgroundElevated)
        }
    }

    private var statusColor: Color {
        if telemetry.errorMessage != nil {
            return DesktopShellTokens.statusDanger
        }

        return telemetry.activeSourceCount > 0
            ? DesktopShellTokens.statusSuccess
            : DesktopShellTokens.actionPrimary
    }
}

private struct LevelLaneCard: View {
    let lane: LevelLaneConfiguration
    let telemetry: LevelTelemetrySnapshot
    let status: LevelLaneConnectionStatus?
    let onRename: (String) -> Void
    let onToggle: (LevelLaneConfiguration) -> Void
    let onSourceSelection: (Int?, String?) -> Void
    let onTargetLevel: (Double) -> Void
    let onTargetMargin: (Double) -> Void
    let onHistoryRange: (HistoryRange) -> Void

    var body: some View {
        // Figma window: header block (title row + input-status, 12px) → body (24px),
        // card padding 16 vertical (horizontal supplied by the section card).
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            VStack(alignment: .leading, spacing: DesktopShellTokens.inputStatusGap) {
                HStack(spacing: DesktopShellTokens.layoutGapXL) {
                    RenameableTitle(
                        title: lane.name,
                        onCommit: onRename
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PowerIconButton(
                        isOn: lane.isEnabled,
                        action: {
                            onToggle(lane)
                        }
                    )
                }

                if lane.isEnabled, let status {
                    InputStatusView(status: status)
                }
            }

            if lane.isEnabled {
                VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapLG) {
                    SidebarValueRow(label: "Source") {
                        MenuValueButton(
                            title: selectedSourceTitle,
                            icon: .chevronDown,
                            maxTitleWidth: 200
                        ) { dismiss in
                            Button("Unassigned") {
                                onSourceSelection(nil, nil)
                                dismiss()
                            }

                            if telemetry.sources.isEmpty {
                                Button("Waiting for sources") {}
                                    .disabled(true)
                            }

                            ForEach(telemetry.sources) { source in
                                Button(source.menuTitle) {
                                    onSourceSelection(
                                        source.sourceSlot,
                                        source.sourceName
                                    )
                                    dismiss()
                                }
                            }
                        }
                    }

                    SidebarValueRow(label: "Target level") {
                        DraggableValueField(
                            value: lane.targetLevelDB,
                            range: -60...0,
                            step: 1,
                            display: DesktopShellFormatters.targetLevel,
                            editText: { String(Int($0.rounded())) },
                            parse: { Double($0) },
                            onCommit: onTargetLevel
                        )
                    }

                    SidebarValueRow(label: "Margin") {
                        DraggableValueField(
                            value: lane.targetMarginDB,
                            range: 1...24,
                            step: 1,
                            display: DesktopShellFormatters.margin,
                            editText: { String(Int($0.rounded())) },
                            parse: { Double($0) },
                            onCommit: onTargetMargin
                        )
                    }

                    SidebarValueRow(label: "History range") {
                        MenuValueButton(
                            title: lane.historyRange.displayLabel,
                            icon: .chevronDown
                        ) { dismiss in
                            ForEach(HistoryRange.allCases, id: \.self) { historyRange in
                                Button(historyRange.displayLabel) {
                                    onHistoryRange(historyRange)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, DesktopShellTokens.layoutGapLG)
    }

    private var selectedSourceTitle: String {
        if let selectedSource = telemetry.source(for: lane.preferredSourceSlot) {
            return selectedSource.menuTitle
        }

        return lane.preferredSourceLabel
    }
}

struct DesktopWorkspaceSplitMetrics: Equatable {
    let availableHeight: CGFloat
    let gap: CGFloat
    let contentHeight: CGFloat
    let gridHeight: CGFloat
    let levelHeight: CGFloat
    let dividerCenterY: CGFloat

    init(
        availableHeight: CGFloat,
        gridFraction: Double,
        liveGridHeight: CGFloat?,
        gap: CGFloat,
        gridMinHeight: CGFloat,
        levelMinHeight: CGFloat
    ) {
        let resolvedAvailableHeight = max(availableHeight, 1)
        let resolvedGap = max(gap, 0)
        let resolvedContentHeight = max(resolvedAvailableHeight - resolvedGap, 1)
        let proposedGridHeight = liveGridHeight
            ?? resolvedContentHeight * CGFloat(gridFraction)
        let resolvedGridHeight = Self.clampGridHeight(
            proposedGridHeight,
            contentHeight: resolvedContentHeight,
            gridMinHeight: gridMinHeight,
            levelMinHeight: levelMinHeight
        )

        self.availableHeight = resolvedAvailableHeight
        self.gap = resolvedGap
        self.contentHeight = resolvedContentHeight
        self.gridHeight = resolvedGridHeight
        self.levelHeight = max(resolvedContentHeight - resolvedGridHeight, 1)
        self.dividerCenterY = resolvedGridHeight + (resolvedGap / 2)
    }

    static func clampGridHeight(
        _ proposed: CGFloat,
        contentHeight: CGFloat,
        gridMinHeight: CGFloat,
        levelMinHeight: CGFloat
    ) -> CGFloat {
        let resolvedContentHeight = max(contentHeight, 1)
        let lowerBound = max(gridMinHeight, 0)
        let upperBound = resolvedContentHeight - max(levelMinHeight, 0)

        guard lowerBound <= upperBound else {
            return min(
                max(proposed, resolvedContentHeight * 0.25),
                resolvedContentHeight * 0.75
            )
        }

        return min(max(proposed, lowerBound), upperBound)
    }

    static func normalizedGridFraction(
        gridHeight: CGFloat,
        contentHeight: CGFloat,
        gridMinHeight: CGFloat,
        levelMinHeight: CGFloat
    ) -> Double {
        let resolvedContentHeight = max(contentHeight, 1)
        let resolvedGridHeight = clampGridHeight(
            gridHeight,
            contentHeight: resolvedContentHeight,
            gridMinHeight: gridMinHeight,
            levelMinHeight: levelMinHeight
        )
        return Double(resolvedGridHeight / resolvedContentHeight)
    }
}

private struct DesktopWorkspaceLiveView: View {
    let model: DesktopShellModel

    /// Fraction of the available height assigned to the Grid panel when Grid and
    /// Level are stacked. Persisted across launches; clamped by the Figma panel
    /// min-height tokens (`component/panel/grid-min-height` = 128,
    /// `component/panel/level-min-height` = 200).
    @AppStorage("kairos.workspace.gridFraction") private var gridFraction: Double = 0.66
    /// Grid height captured the moment a resize drag begins. The drag is measured
    /// against this fixed baseline (plus the cursor delta) so the split tracks the
    /// pointer 1:1 instead of compounding as the divider repositions.
    @State private var dragStartGridHeight: CGFloat?
    /// Live Grid height while a drag is in flight. Driving the drag through a
    /// transient @State — instead of writing @AppStorage on every frame — keeps the
    /// motion smooth and persists the fraction only once, on release.
    @State private var liveGridHeight: CGFloat?

    var body: some View {
        // The split layout and the resize divider live OUTSIDE the per-renderer
        // TimelineViews so the drag gesture is not cancelled by the 30 fps redraw
        // that drives the meters. Each surface owns its own TimelineView for the
        // live content.
        GeometryReader { geometry in
            let gap = DesktopShellTokens.layoutGapLG
            let gridMinHeight = DesktopShellTokens.gridPanelMinHeight
            let levelMinHeight = DesktopShellTokens.levelPanelMinHeight
            let splitMetrics = DesktopWorkspaceSplitMetrics(
                availableHeight: geometry.size.height,
                gridFraction: gridFraction,
                liveGridHeight: liveGridHeight,
                gap: gap,
                gridMinHeight: gridMinHeight,
                levelMinHeight: levelMinHeight
            )

            Group {
                if model.settings.isGridVisible, model.settings.isLevelVisible {
                    ZStack(alignment: .topLeading) {
                        gridSurface
                            .frame(
                                width: geometry.size.width,
                                height: splitMetrics.gridHeight,
                                alignment: .topLeading
                            )

                        levelSplitSurface
                            .frame(
                                width: geometry.size.width,
                                height: splitMetrics.levelHeight,
                                alignment: .topLeading
                            )
                            .offset(y: splitMetrics.gridHeight + splitMetrics.gap)

                        WorkspaceResizeDivider(
                            width: geometry.size.width,
                            centerY: splitMetrics.dividerCenterY,
                            onChanged: { delta in
                                let base = dragStartGridHeight ?? splitMetrics.gridHeight
                                liveGridHeight = DesktopWorkspaceSplitMetrics.clampGridHeight(
                                    base + delta,
                                    contentHeight: splitMetrics.contentHeight,
                                    gridMinHeight: gridMinHeight,
                                    levelMinHeight: levelMinHeight
                                )
                            },
                            onBegan: {
                                // Capture the baseline the instant the drag
                                // starts, so the first delta is measured from
                                // exactly here.
                                dragStartGridHeight = splitMetrics.gridHeight
                                liveGridHeight = splitMetrics.gridHeight
                            },
                            onEnded: {
                                if let live = liveGridHeight {
                                    gridFraction = DesktopWorkspaceSplitMetrics
                                        .normalizedGridFraction(
                                            gridHeight: live,
                                            contentHeight: splitMetrics.contentHeight,
                                            gridMinHeight: gridMinHeight,
                                            levelMinHeight: levelMinHeight
                                        )
                                }
                                liveGridHeight = nil
                                dragStartGridHeight = nil
                            }
                        )
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .topLeading
                        )
                        .zIndex(1)
                    }
                } else if model.settings.isGridVisible {
                    gridSurface
                        .frame(maxHeight: .infinity)
                } else if model.settings.isLevelVisible {
                    levelExpandedSurface
                        .frame(maxHeight: .infinity)
                } else {
                    emptyState
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridSurface: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            let snapshot = model.workspaceSnapshot(at: timeline.date)
            RendererSurface(
                hasContent: !snapshot.gridFrame.cycles.isEmpty,
                emptyTitle: "Enable a cycle to preview Grid."
            ) {
                GridRenderer(
                    frame: snapshot.gridFrame,
                    onStepTap: { slot, stepIndex in
                        model.cycleCustomStepMode(slot: slot, stepIndex: stepIndex)
                    }
                )
            }
        }
    }

    private var levelSplitSurface: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let snapshot = model.workspaceSnapshot(at: timeline.date)
            RendererSurface(
                hasContent: !snapshot.levelSplitFrame.lanes.isEmpty,
                emptyTitle: "Enable a window to preview Level."
            ) {
                LevelRenderer(frame: snapshot.levelSplitFrame)
            }
        }
    }

    private var levelExpandedSurface: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let snapshot = model.workspaceSnapshot(at: timeline.date)
            RendererSurface(
                hasContent: !snapshot.levelExpandedFrame.lanes.isEmpty,
                emptyTitle: "Enable a window to preview Level."
            ) {
                LevelRenderer(frame: snapshot.levelExpandedFrame)
            }
        }
    }

    private var emptyState: some View {
        RoundedRectangle(
            cornerRadius: DesktopShellTokens.radiusCanvas,
            style: .continuous
        )
        .fill(DesktopShellTokens.backgroundSurface)
        .overlay {
            Text("Enable Grid or Level from the sidebar.")
                .font(DesktopShellTypography.bodyLG)
                .foregroundStyle(DesktopShellTokens.textTertiary)
        }
    }
}

/// Splitter between the Grid and Level surfaces.
///
/// The interactive layer is an AppKit `NSView` (`ResizeHandleRepresentable`)
/// rather than a SwiftUI gesture, because a professional splitter needs two
/// guarantees SwiftUI gestures do not give reliably:
///   1. A resize cursor that always appears and never sticks — driven by an
///      `NSTrackingArea` `cursorUpdate`, the same mechanism AppKit uses for its
///      own divider cursors.
///   2. A drag that cannot be lost on fast pointer moves — native `mouseDown` →
///      `mouseDragged` → `mouseUp` get automatic mouse capture, so every event
///      is delivered to the handle until the button is released.
///
/// The handle is transparent; the visible grabber is drawn in SwiftUI beneath it
/// and brightens on hover/drag. The drag delta is measured against the pointer
/// position captured at `mouseDown` (in window coordinates), so it tracks the
/// cursor 1:1 and never feeds back as the divider repositions during the resize.
private struct WorkspaceResizeDivider: View {
    let width: CGFloat
    let centerY: CGFloat
    /// Reports the baseline-relative drag distance in points (positive = drag
    /// down, i.e. grow Grid), measured from the `mouseDown` location.
    let onChanged: (CGFloat) -> Void
    /// Fires once at `mouseDown`, before any movement, so the parent can capture
    /// the Grid height baseline with zero delta (no jump at drag start).
    let onBegan: () -> Void
    let onEnded: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Subtle grabber: invisible at rest, brightening while the pointer
            // is over the strip or a resize is in flight.
            Capsule(style: .continuous)
                .fill(DesktopShellTokens.textTertiary)
                .frame(width: 36, height: 4)
                .opacity(isHovering || isDragging ? 0.9 : 0)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: isDragging)
                .position(x: width / 2, y: centerY)
                .allowsHitTesting(false)

            ResizeHandleRepresentable(
                onHoverChange: { isHovering = $0 },
                onBegan: {
                    isDragging = true
                    onBegan()
                },
                onChanged: onChanged,
                onEnded: {
                    isDragging = false
                    onEnded()
                }
            )
            .frame(
                width: width,
                height: DesktopShellTokens.resizeDividerHitHeight
            )
            .position(x: width / 2, y: centerY)
        }
    }
}

/// AppKit-backed splitter handle. Owns the resize cursor and the drag loop; see
/// `WorkspaceResizeDivider` for why this is native rather than a SwiftUI gesture.
private struct ResizeHandleRepresentable: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.apply(onHoverChange: onHoverChange, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.apply(onHoverChange: onHoverChange, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    final class HandleView: NSView {
        private var onHoverChange: ((Bool) -> Void)?
        private var onBegan: (() -> Void)?
        private var onChanged: ((CGFloat) -> Void)?
        private var onEnded: (() -> Void)?
        private var isDragging = false

        /// Pointer Y (window coordinates) captured at `mouseDown`. Window space
        /// has its origin at the bottom-left with Y increasing upward, so a
        /// downward drag lowers Y — hence the `start - current` delta below maps a
        /// downward drag to a positive value (grow Grid).
        private var dragStartY: CGFloat = 0

        func apply(
            onHoverChange: @escaping (Bool) -> Void,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onHoverChange = onHoverChange
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        // Let the splitter respond on the first click even when the window is not
        // yet key, matching native desktop-app behaviour.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        // Rebuild the tracking area whenever the handle's geometry changes (the
        // divider moves continuously while resizing), so the cursor region always
        // matches the live bounds. `.inVisibleRect` keeps it pinned to `bounds`.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.cursorUpdate, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            guard !isDragging else {
                return
            }
            onHoverChange?(false)
        }

        override func mouseDown(with event: NSEvent) {
            isDragging = true
            dragStartY = event.locationInWindow.y
            NSCursor.resizeUpDown.set()
            onHoverChange?(true)
            onBegan?()
        }

        override func mouseDragged(with event: NSEvent) {
            // Keep asserting the cursor for the duration of the drag, including
            // when the pointer runs past a clamp limit and off the handle.
            NSCursor.resizeUpDown.set()
            onChanged?(dragStartY - event.locationInWindow.y)
        }

        override func mouseUp(with event: NSEvent) {
            isDragging = false
            onEnded?()
            let location = convert(event.locationInWindow, from: nil)
            onHoverChange?(bounds.contains(location))
        }
    }
}

private struct RendererSurface<Content: View>: View {
    let hasContent: Bool
    let emptyTitle: String
    let content: Content

    init(
        hasContent: Bool,
        emptyTitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.hasContent = hasContent
        self.emptyTitle = emptyTitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            if hasContent {
                content
            } else {
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
                .fill(DesktopShellTokens.backgroundSurface)

                Text(emptyTitle)
                    .font(DesktopShellTypography.bodyLG)
                    .foregroundStyle(DesktopShellTokens.textTertiary)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusCanvas,
                style: .continuous
            )
        )
    }
}

private struct SidebarCardSection<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            Text(title)
                .font(DesktopShellTypography.titleSM)
                .foregroundStyle(DesktopShellTokens.textSecondary)

            content
        }
        // Match the Grid/Level cards: each subsection owns 16px vertical padding so
        // the gap to the divider (subsection 16 + container 8) is the same 24px.
        .padding(.vertical, DesktopShellTokens.layoutGapLG)
    }
}

private struct SidebarDivider: View {
    var body: some View {
        // Figma sidebar divider: `color/border/default` (#2F3238) at 0.5px.
        // A plain `Divider()` renders the system separator color, so draw the
        // hairline explicitly to match the design token exactly.
        Rectangle()
            .fill(DesktopShellTokens.borderDefault)
            .frame(height: DesktopShellTokens.borderWidth)
            .frame(maxWidth: .infinity)
    }
}

private struct SidebarValueRow<Control: View>: View {
    let label: String
    let control: Control

    init(
        label: String,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: DesktopShellTokens.layoutGapSM) {
            Text(label)
                .font(DesktopShellTypography.bodyLG)
                .foregroundStyle(DesktopShellTokens.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            control
        }
    }
}

private struct DataAtomView: View {
    let text: String
    var width: CGFloat
    var isDisabled = false

    var body: some View {
        Text(text)
            .font(DesktopShellTypography.labelXS)
            .monospacedDigit()
            .foregroundStyle(DesktopShellTokens.textTertiary)
            .opacity(isDisabled ? 0.55 : 1)
            // Figma `data` atoms are single-line (`whitespace-nowrap`). The fixed
            // width keeps the right info cluster from drifting as digits change;
            // lineLimit + minimumScaleFactor guarantee one line without wrapping.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, DesktopShellTokens.componentGapXS)
            .padding(.horizontal, DesktopShellTokens.componentGapXS)
            .frame(width: width, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SyncStatusView: View {
    let descriptor: SyncStatusDescriptor
    var compact = true

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXS) {
            if descriptor.showsLinkIcon {
                KairosIconView(
                    icon: .link,
                    color: descriptor.tone.color
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }

            Text(descriptor.text)
                .font(DesktopShellTypography.labelXS)
                .foregroundStyle(DesktopShellTokens.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        }
        .padding(.vertical, DesktopShellTokens.componentGapXS)
        .padding(.horizontal, compact ? DesktopShellTokens.componentGapXS : 0)
    }
}

private struct InputStatusView<Status: SidebarInputStatusDescriptor>: View {
    let status: Status

    var body: some View {
        guard status.sidebarStatusTone != .hidden else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: DesktopShellTokens.componentGapSM) {
                Circle()
                    .fill(statusColor)
                    .frame(width: DesktopShellTokens.statusDotSize, height: DesktopShellTokens.statusDotSize)

                Text(status.sidebarStatusLabel)
                    .font(DesktopShellTypography.labelXS)
                    .foregroundStyle(DesktopShellTokens.textTertiary)
                    .lineLimit(1)
            }
        )
    }

    private var statusColor: Color {
        switch status.sidebarStatusTone {
        case .hidden:
            return .clear
        case .waiting:
            return DesktopShellTokens.actionPrimary
        case .connected:
            return DesktopShellTokens.statusSuccess
        case .disconnected:
            return DesktopShellTokens.statusDanger
        }
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

private extension SyncSource {
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

private extension StepNumber {
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

private extension HistoryRange {
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

private extension GridVisualMode {
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
