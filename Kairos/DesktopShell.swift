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

    var activePresetToolbarLabel: String {
        settings.activePresetSlot.toolbarLabel
    }

    func loadPresets() async {
        guard let presetStore else {
            storageErrorMessage = "Preset storage unavailable."
            return
        }

        do {
            let library = try await presetStore.loadPresets()
            presetLibrary = library

            if let storedPreset = library.storedPreset(for: settings.activePresetSlot) {
                settings.apply(
                    storedPreset.settings,
                    activating: storedPreset.slot
                )
            }

            synchronizeUSBSourceSelection()
            synchronizeTransportState()
            refreshLevelSidebarState(at: currentDate())
            refreshMetronomeScheduling(at: currentDate(), reset: true)
        } catch {
            presetLibrary = .factoryDefault
            storageErrorMessage = "Presets could not be loaded."
        }
    }

    func saveCurrentPreset(to slot: PresetSlot? = nil) async {
        let targetSlot = slot ?? settings.activePresetSlot
        settings.activePresetSlot = targetSlot

        var updatedLibrary = presetLibrary
        updatedLibrary.replace(
            preset: settings.makeStoredPreset(for: targetSlot)
        )

        do {
            if let presetStore {
                try await presetStore.savePresets(updatedLibrary)
            }
            presetLibrary = updatedLibrary
            storageErrorMessage = nil
        } catch {
            storageErrorMessage = "Current preset could not be saved."
        }
    }

    func selectPreset(_ slot: PresetSlot) {
        selectPreset(slot, at: currentDate())
    }

    private func selectPreset(
        _ slot: PresetSlot,
        at date: Date
    ) {
        guard let storedPreset = presetLibrary.storedPreset(for: slot) else {
            return
        }

        settings.apply(
            storedPreset.settings,
            activating: slot
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

    var body: some View {
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
                        title: model.activePresetToolbarLabel,
                        activeSlot: model.settings.activePresetSlot,
                        onSelect: { slot in
                            model.selectPreset(slot)
                        },
                        onSave: { slot in
                            Task {
                                await model.saveCurrentPreset(to: slot)
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
                            ) {
                                ForEach(DesktopShellFormatters.metronomePulseOptions, id: \.self) { option in
                                    Button(option.title) {
                                        model.setMetronomePulse(option.value)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesktopShellTokens.layoutGapLG)
            .background(DesktopShellTokens.backgroundElevated)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
            )

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
            .background(DesktopShellTokens.backgroundElevated)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
            )
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
                        ) {
                            ForEach(StepNumber.allCases, id: \.self) { stepNumber in
                                Button(stepNumber.displayLabel) {
                                    onStepNumber(stepNumber)
                                }
                            }
                        }
                    }

                    SidebarValueRow(label: "Pulse") {
                        MenuValueButton(
                            title: cycle.pulse.displayLabel,
                            icon: .chevronDown
                        ) {
                            ForEach(Pulse.allCases, id: \.self) { pulse in
                                Button(pulse.displayLabel) {
                                    onPulse(pulse)
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
            .background(DesktopShellTokens.backgroundElevated)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: DesktopShellTokens.radiusCanvas,
                    style: .continuous
                )
            )
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
        .background(DesktopShellTokens.backgroundElevated)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusCanvas,
                style: .continuous
            )
        )
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
                            icon: .chevronDown
                        ) {
                            Button("Unassigned") {
                                onSourceSelection(nil, nil)
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
                        ) {
                            ForEach(HistoryRange.allCases, id: \.self) { historyRange in
                                Button(historyRange.displayLabel) {
                                    onHistoryRange(historyRange)
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

private struct DesktopWorkspaceLiveView: View {
    let model: DesktopShellModel

    /// Fraction of the available height assigned to the Grid panel when Grid and
    /// Level are stacked. Persisted across launches; clamped by the Figma panel
    /// min-height tokens (`component/panel/grid-min-height` = 560,
    /// `component/panel/level-min-height` = 280).
    @AppStorage("kairos.workspace.gridFraction") private var gridFraction: Double = 0.66
    @State private var dragStartGridHeight: CGFloat?

    var body: some View {
        // The split layout and the resize divider live OUTSIDE the per-renderer
        // TimelineViews so the drag gesture is not cancelled by the 30 fps redraw
        // that drives the meters. Each surface owns its own TimelineView for the
        // live content.
        GeometryReader { geometry in
            let available = max(geometry.size.height, 1)

            VStack(spacing: 0) {
                if model.settings.isGridVisible, model.settings.isLevelVisible {
                    let gap = DesktopShellTokens.layoutGapLG
                    let content = max(available - gap, 1)
                    let gridHeight = resolvedGridHeight(forContent: content)
                    let levelHeight = max(content - gridHeight, 1)

                    gridSurface
                        .frame(height: gridHeight)

                    WorkspaceResizeDivider(
                        height: gap,
                        onChanged: { translation in
                            if dragStartGridHeight == nil {
                                dragStartGridHeight = gridHeight
                            }
                            let proposed = (dragStartGridHeight ?? gridHeight) + translation
                            gridFraction = Double(clampGridHeight(proposed, content: content) / content)
                        },
                        onEnded: {
                            dragStartGridHeight = nil
                        }
                    )

                    levelSplitSurface
                        .frame(height: levelHeight)
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

    /// Grid height honoring the persisted fraction, clamped to the Figma min
    /// heights. If the viewport is too short to satisfy both minimums, fall back
    /// to a proportional split so the layout never breaks.
    private func resolvedGridHeight(forContent content: CGFloat) -> CGFloat {
        clampGridHeight(content * CGFloat(gridFraction), content: content)
    }

    private func clampGridHeight(_ proposed: CGFloat, content: CGFloat) -> CGFloat {
        let gridMin = DesktopShellTokens.gridPanelMinHeight
        let levelMin = DesktopShellTokens.levelPanelMinHeight
        let upperBound = content - levelMin

        // When the viewport is tall enough, honor the exact Figma panel min
        // heights. On viewports too short to fit both (e.g. a laptop display),
        // keep the resize interactive within a safe band so neither panel
        // collapses, instead of locking the split.
        guard gridMin <= upperBound else {
            return min(max(proposed, content * 0.25), content * 0.75)
        }

        return min(max(proposed, gridMin), upperBound)
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

private struct WorkspaceResizeDivider: View {
    let height: CGFloat
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    @State private var isHovering = false

    var body: some View {
        // The Figma reference shows only the 16px gap between Grid and Level
        // (no visible rule). The visible band stays at `height`, but the hit area
        // and resize cursor extend a few points into each panel via an overlay so
        // the separator is easy to find and grab.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                ZStack {
                    Color.clear
                    Capsule(style: .continuous)
                        .fill(DesktopShellTokens.borderDefault)
                        .frame(width: 36, height: 4)
                        .opacity(isHovering ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: height + 18)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            onChanged(value.translation.height)
                        }
                        .onEnded { _ in
                            onEnded()
                        }
                )
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

private struct ToolbarIconButton: View {
    let icon: KairosIcon
    // Retained for call-site clarity (which control is "on"); ghost styling never
    // uses it for a fill — the on-state is conveyed by the icon, not a blue background.
    var isActive = false
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            buttonSurface(
                kind: .ghost,
                isHovered: isHovered,
                isDisabled: isDisabled
            ) {
                KairosIconView(
                    icon: icon,
                    color: isDisabled
                        ? DesktopShellTokens.textTertiary.opacity(0.5)
                        : DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct PowerIconButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            buttonSurface(kind: .filled, isActive: isOn) {
                KairosIconView(
                    icon: .power,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ModeIconButton: View {
    let icon: KairosIcon
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            buttonSurface(
                kind: .secondary,
                isActive: isSelected,
                isHovered: isHovered
            ) {
                KairosIconView(
                    icon: icon,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct TertiaryIconButton: View {
    let icon: KairosIcon
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            buttonSurface(kind: .outlined, isHovered: isHovered) {
                KairosIconView(
                    icon: icon,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct ToggleButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary)

                Circle()
                    .fill(DesktopShellTokens.actionPrimary)
                    .frame(width: DesktopShellTokens.toggleThumbSize, height: DesktopShellTokens.toggleThumbSize)
                    .padding(DesktopShellTokens.componentGapXS)
            }
            .frame(
                width: DesktopShellTokens.toggleWidth,
                height: DesktopShellTokens.toggleHeight
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    var trailingIcon: KairosIcon?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SegmentButtonLabel(
                title: title,
                isSelected: isSelected,
                trailingIcon: trailingIcon
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SegmentMenuButton<Content: View>: View {
    let title: String
    let isSelected: Bool
    var trailingIcon: KairosIcon?
    let content: Content

    init(
        title: String,
        isSelected: Bool,
        trailingIcon: KairosIcon? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isSelected = isSelected
        self.trailingIcon = trailingIcon
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            SegmentButtonLabel(
                title: title,
                isSelected: isSelected,
                trailingIcon: trailingIcon
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }
}

private struct USBSyncSegmentButton<Content: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    init(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXS) {
            Button(action: action) {
                Text(title)
                    .font(DesktopShellTypography.labelMD)
                    .foregroundStyle(DesktopShellTokens.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesktopShellTokens.controlHeight)
            }
            .buttonStyle(.plain)

            Menu {
                content
            } label: {
                KairosIconView(
                    icon: .chevronDown,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
                .frame(minHeight: DesktopShellTokens.controlHeight)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, DesktopShellTokens.componentGapSM)
        .frame(maxWidth: .infinity, minHeight: DesktopShellTokens.controlHeight)
        .background(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusSurface,
                style: .continuous
            )
            .fill(isSelected ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary)
        )
    }
}

private struct SegmentButtonLabel: View {
    let title: String
    let isSelected: Bool
    var trailingIcon: KairosIcon?

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXS) {
            Text(title)
                .font(DesktopShellTypography.labelMD)
                .foregroundStyle(DesktopShellTokens.actionPrimary)

            if let trailingIcon {
                KairosIconView(
                    icon: trailingIcon,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: DesktopShellTokens.controlHeight)
        .padding(.horizontal, DesktopShellTokens.componentGapSM)
        .background(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusSurface,
                style: .continuous
            )
            .fill(isSelected ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary)
        )
    }
}

private struct RenameableTitle: View {
    let title: String
    let onCommit: (String) -> Void

    @State private var isPresented = false
    @State private var draftName = ""

    var body: some View {
        Text(title)
            .font(DesktopShellTypography.titleSM)
            .foregroundStyle(DesktopShellTokens.textSecondary)
            .contextMenu {
                Button("Rename") {
                    draftName = title
                    isPresented = true
                }
            }
            .popover(isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rename")
                        .font(DesktopShellTypography.titleSM)

                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            isPresented = false
                        }
                        Button("Apply") {
                            onCommit(draftName)
                            isPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
            }
    }
}

private struct PresetSelectorButton: View {
    let title: String
    let activeSlot: PresetSlot
    let onSelect: (PresetSlot) -> Void
    let onSave: (PresetSlot) -> Void

    var body: some View {
        Menu {
            Section("Switch preset") {
                ForEach(PresetSlot.allCases, id: \.self) { slot in
                    Button {
                        onSelect(slot)
                    } label: {
                        if slot == activeSlot {
                            Label(slot.displayName, systemImage: "checkmark")
                        } else {
                            Text(slot.displayName)
                        }
                    }
                }
            }

            Section("Save current") {
                ForEach(PresetSlot.allCases, id: \.self) { slot in
                    Button("Save to \(slot.displayName)") {
                        onSave(slot)
                    }
                }
            }
        } label: {
            MenuValueLabel(
                title: title,
                icon: .chevronDown,
                width: 146,
                style: .ghost
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct MenuValueButton<Content: View>: View {
    let title: String
    let icon: KairosIcon
    var width: CGFloat?
    let content: Content

    init(
        title: String,
        icon: KairosIcon,
        width: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.width = width
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            MenuValueLabel(
                title: title,
                icon: icon,
                width: width,
                style: .outlined
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct DraggableValueField: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String
    let editText: (Double) -> String
    let parse: (String) -> Double?
    var showStepIcon = true
    var fillWidth = false
    var isDisabled = false
    let onCommit: (Double) -> Void

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var dragStartValue: Double?
    @FocusState private var isFocused: Bool

    private static let pointsPerStep: CGFloat = 4

    var body: some View {
        buttonSurface(kind: .outlined, isDisabled: isDisabled) {
            HStack(spacing: DesktopShellTokens.componentGapXS) {
                if isEditing {
                    TextField("", text: $draftText)
                        .textFieldStyle(.plain)
                        .font(DesktopShellTypography.labelMD)
                        .foregroundStyle(DesktopShellTokens.actionPrimary)
                        .multilineTextAlignment(fillWidth ? .center : .leading)
                        .focused($isFocused)
                        .onSubmit { commitDraft() }
                        .frame(maxWidth: fillWidth ? .infinity : nil)
                } else {
                    Text(display(value))
                        .font(DesktopShellTypography.labelMD)
                        .foregroundStyle(DesktopShellTokens.actionPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: fillWidth ? .infinity : nil, alignment: fillWidth ? .center : .leading)

                    if showStepIcon {
                        KairosIconView(icon: .doubleArrow, color: DesktopShellTokens.actionPrimary)
                            .frame(width: DesktopShellTokens.iconSize, height: DesktopShellTokens.iconSize)
                    }
                }
            }
            .frame(maxWidth: fillWidth ? .infinity : nil, alignment: fillWidth ? .center : .leading)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !isDisabled else { return }
                draftText = editText(value)
                isEditing = true
                isFocused = true
            }
        )
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { gesture in
                    guard !isEditing, !isDisabled else { return }
                    if dragStartValue == nil { dragStartValue = value }
                    let steps = (-gesture.translation.height / Self.pointsPerStep).rounded()
                    onCommit(clamped((dragStartValue ?? value) + Double(steps) * step))
                }
                .onEnded { _ in dragStartValue = nil }
        )
        .onChange(of: isFocused) { _, hasFocus in
            if isEditing, !hasFocus { commitDraft() }
        }
    }

    private func commitDraft() {
        defer {
            isEditing = false
            isFocused = false
        }
        let normalized = draftText.replacingOccurrences(of: ",", with: ".")
        if let parsed = parse(normalized) {
            onCommit(clamped(parsed))
        }
    }

    private func clamped(_ next: Double) -> Double {
        min(max(next, range.lowerBound), range.upperBound)
    }
}

private struct HoldRepeatButton: View {
    let icon: KairosIcon
    let onStep: () -> Void

    @State private var isHovering = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        buttonSurface(kind: .outlined, isHovered: isHovering) {
            KairosIconView(icon: icon, color: DesktopShellTokens.actionPrimary)
                .frame(width: DesktopShellTokens.iconSize, height: DesktopShellTokens.iconSize)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if holdTask == nil { beginHold() }
                }
                .onEnded { _ in endHold() }
        )
    }

    // Single tap fires once; press-and-hold repeats unit-by-unit with a
    // progressive acceleration while held.
    private func beginHold() {
        onStep()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            var interval: UInt64 = 110_000_000
            while !Task.isCancelled {
                onStep()
                try? await Task.sleep(nanoseconds: interval)
                interval = max(18_000_000, UInt64(Double(interval) * 0.82))
            }
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
    }
}

private struct LatencyControl: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    let editFormatter: (Double) -> String
    let parse: (String) -> Double?
    let onCommit: (Double) -> Void
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        // Figma sidebar: a line of buttons aligned to the right of the row —
        // [−] [value] [+] — matching the other sidebar value controls.
        HStack(spacing: DesktopShellTokens.layoutGapSM) {
            HoldRepeatButton(icon: .minus, onStep: onDecrement)

            DraggableValueField(
                value: value,
                range: range,
                step: step,
                display: formatter,
                editText: editFormatter,
                parse: parse,
                showStepIcon: false,
                onCommit: onCommit
            )

            HoldRepeatButton(icon: .plus, onStep: onIncrement)
        }
    }
}

private struct MenuValueLabel: View {
    enum Style {
        case ghost
        case outlined
    }

    let title: String
    let icon: KairosIcon
    var width: CGFloat?
    let style: Style
    var isDisabled = false

    var body: some View {
        buttonSurface(
            kind: style == .ghost ? .ghost : .outlined,
            isDisabled: isDisabled
        ) {
            HStack(spacing: DesktopShellTokens.componentGapXS) {
                Text(title)
                    .font(DesktopShellTypography.labelMD)
                    .foregroundStyle(DesktopShellTokens.actionPrimary)

                KairosIconView(
                    icon: icon,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
            // Fixed width when specified (e.g. preset selector = 146 per Figma) so
            // the trigger never stretches to fill the toolbar; otherwise hug content.
            .frame(width: width, alignment: .leading)
        }
    }
}

private enum ButtonSurfaceKind {
    case ghost
    case filled
    case outlined
    case secondary
}

private func buttonSurface<Content: View>(
    kind: ButtonSurfaceKind,
    isActive: Bool = false,
    isHovered: Bool = false,
    isDisabled: Bool = false,
    @ViewBuilder content: () -> Content
) -> some View {
    let fillColor: Color
    let borderColor: Color

    switch kind {
    case .ghost:
        // Figma `button/ghost`: the default state has no fill and no border, and
        // it never adopts the accent/primary fill. The only documented states are
        // `default` and `folded` (the open menu), so an active toolbar control is
        // expressed through its icon, not a blue background. Hover gets a subtle
        // surface tint for feedback only.
        fillColor = isHovered ? DesktopShellTokens.actionSecondaryHover : Color.clear
        borderColor = .clear
    case .filled:
        fillColor = isActive ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary
        borderColor = .clear
    case .outlined:
        // Figma `button/tertiary` default: transparent fill + 0.5px subtle border.
        // (The elevated fill belongs to `button/secondary`, not tertiary.)
        fillColor = isHovered ? DesktopShellTokens.actionSecondaryHover : Color.clear
        borderColor = DesktopShellTokens.borderSubtle
    case .secondary:
        if isActive {
            fillColor = DesktopShellTokens.actionHighlight
            borderColor = .clear
        } else if isHovered {
            fillColor = DesktopShellTokens.actionSecondaryHover
            borderColor = .clear
        } else {
            fillColor = DesktopShellTokens.backgroundElevated
            borderColor = DesktopShellTokens.borderSubtle
        }
    }

    return content()
        .padding(.horizontal, DesktopShellTokens.componentGapSM)
        .frame(minHeight: DesktopShellTokens.controlHeight)
        .background(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusSurface,
                style: .continuous
            )
            .fill(fillColor.opacity(isDisabled ? 0.45 : 1))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusSurface,
                style: .continuous
            )
            .stroke(
                borderColor,
                lineWidth: (kind == .outlined || kind == .secondary) ? DesktopShellTokens.borderWidth : 0
            )
        )
}

private enum KairosIcon {
    case sidebar
    case sidebarFolded
    case play
    case stop
    case reset
    case metronomeDefault
    case metronomePing
    case metronomePong
    case power
    case link
    case chevronDown
    case doubleArrow
    case plus
    case minus
    case modeBlock
    case modeBorder
    case modeLine
    case modeCustom

    /// Asset-catalog image name. Vectors are exported verbatim from the Figma
    /// `Components` page (icon/* symbols) and stored as template SVGs.
    var assetName: String {
        switch self {
        case .sidebar: return "sidebar-unfolded"
        case .sidebarFolded: return "sidebar-folded"
        case .play: return "reproduce-play"
        case .stop: return "reproduce-stop"
        case .reset: return "reset"
        case .metronomeDefault: return "metronome-default"
        case .metronomePing: return "metronome-ping"
        case .metronomePong: return "metronome-pong"
        case .power: return "power"
        case .link: return "link"
        case .chevronDown: return "selector-fold"
        case .doubleArrow: return "double-arrow"
        case .plus: return "add"
        case .minus: return "remove"
        case .modeBlock: return "mode-solid"
        case .modeBorder: return "mode-border"
        case .modeLine: return "mode-line"
        case .modeCustom: return "mode-custom"
        }
    }
}

private struct KairosIconView: View {
    let icon: KairosIcon
    let color: Color

    var body: some View {
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
    }
}

private enum DesktopShellTypography {
    // Figma type family is Inter (`type/family/base`). Use the installed Inter
    // family with explicit weights so the UI matches the design 1:1.
    private static func inter(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        Font.custom("Inter", size: size).weight(weight)
    }

    static let wordmark = inter(13, .bold)
    static let titleMD = inter(18, .semibold)
    static let titleSM = inter(16, .semibold)
    static let bodyLG = inter(15, .regular)
    static let labelMD = inter(14, .medium)
    static let labelXS = inter(12, .semibold)
}

private enum DesktopShellTokens {
    // Figma MCP sources:
    // - shell nodes 83:8522, 88:27257, 91:38783
    // - toolbar 108:8183
    // - sidebar 99:6701
    // - button frames 72:2057, 74:2143, 121:6213, 78:1852
    // - toggle 75:2050
    // - status atoms 108:8044, 108:8650, 231:11155
    static let backgroundCanvas = Color(hex: 0x0A0A0B)
    static let backgroundSurface = Color(hex: 0x101012)
    static let backgroundElevated = Color(hex: 0x16171A)
    static let actionPrimary = Color(hex: 0xF5F7FA)
    static let actionSecondary = Color(hex: 0x24262B)
    static let actionSecondaryHover = Color(hex: 0x2F3238)
    static let actionAccent = Color(hex: 0x4378B8)
    static let actionHighlight = Color(hex: 0x4378B8, opacity: 0.5)
    static let textSecondary = Color(hex: 0xAEB8C4)
    static let textTertiary = Color(hex: 0x8792A0)
    static let borderSubtle = Color(hex: 0x24262B)
    static let borderDefault = Color(hex: 0x2F3238)
    static let statusSuccess = Color(hex: 0x43B973)
    static let statusDanger = Color(hex: 0xCA5256)

    static let toolbarHeight: CGFloat = 56
    static let toolbarTimeWidth: CGFloat = 74
    static let toolbarBPMWidth: CGFloat = 78
    static let toolbarSyncWidth: CGFloat = 146
    static let toolbarInfoWidth: CGFloat = toolbarTimeWidth + toolbarBPMWidth + toolbarSyncWidth + (componentGapLG * 2)
    static let sidebarWidth: CGFloat = 375
    static let sidebarOuterWidth: CGFloat = 391
    // Figma `component/panel/*-min-height` tokens — bounds for the vertical
    // Grid/Level resize split.
    static let gridPanelMinHeight: CGFloat = 560
    static let levelPanelMinHeight: CGFloat = 280
    // Figma `scroll-bar` thumb: 8 × 120, radius full, color/action/secondary.
    static let scrollThumbWidth: CGFloat = 8
    static let scrollThumbLength: CGFloat = 120
    static let controlHeight: CGFloat = 32
    static let iconSize: CGFloat = 24
    static let statusDotSize: CGFloat = 8
    static let toggleWidth: CGFloat = 48
    static let toggleHeight: CGFloat = 28
    static let toggleThumbSize: CGFloat = 20

    static let radiusSurface: CGFloat = 8
    static let radiusCanvas: CGFloat = 12
    static let borderWidth: CGFloat = 0.5

    static let componentGapXS: CGFloat = 4
    static let componentGapSM: CGFloat = 8
    static let componentGapMD: CGFloat = 12
    static let componentGapLG: CGFloat = 16
    static let componentGapXL: CGFloat = 24

    static let inputStatusGap: CGFloat = 12

    static let layoutGapSM: CGFloat = 8
    static let layoutGapLG: CGFloat = 16
    static let layoutGapXL: CGFloat = 24

    static let latencyFieldWidth: CGFloat = 92
    static let latencyDragSensitivity: Double = 0.02
    static let latencyStep: Double = 0.01
}

private enum DesktopShellFormatters {
    struct PulseOption: Hashable {
        let title: String
        let value: Pulse
    }

    static let metronomePulseOptions: [PulseOption] = [
        PulseOption(title: Pulse.oneSixteenth.displayLabel, value: .oneSixteenth),
        PulseOption(title: Pulse.oneEighth.displayLabel, value: .oneEighth),
        PulseOption(title: Pulse.oneQuarter.displayLabel, value: .oneQuarter),
        PulseOption(title: Pulse.oneHalf.displayLabel, value: .oneHalf),
        PulseOption(title: Pulse.one.displayLabel, value: .one),
    ]

    static func elapsedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }

        return "\(remainingSeconds)s"
    }

    static func bpm(_ bpm: Int) -> String {
        "\(String(format: "%.2f", Double(bpm))) bpm"
    }

    static func bpm(_ bpm: Double) -> String {
        "\(String(format: "%.2f", bpm)) bpm"
    }

    static func bpmControl(_ bpm: Int) -> String {
        String(format: "%.2f", Double(bpm))
    }

    static func latency(_ milliseconds: Double) -> String {
        String(format: "%.2f ms", milliseconds)
    }

    static func latencyInput(_ milliseconds: Double) -> String {
        String(format: "%.2f", milliseconds)
    }

    static func targetLevel(_ db: Double) -> String {
        "\(Int(db.rounded())) db"
    }

    static func margin(_ db: Double) -> String {
        "\(Int(db.rounded())) db"
    }
}

private extension PresetLibrary {
    mutating func replace(preset: StoredPreset) {
        guard let index = presets.firstIndex(where: { $0.slot == preset.slot }) else {
            return
        }

        presets[index] = preset
    }

    func storedPreset(for slot: PresetSlot) -> StoredPreset? {
        presets.first(where: { $0.slot == slot })
    }
}

private extension PresetSlot {
    var toolbarLabel: String {
        switch self {
        case .defaultPreset:
            return "default preset"
        case .custom1:
            return "preset 1"
        case .custom2:
            return "preset 2"
        case .custom3:
            return "preset 3"
        case .custom4:
            return "preset 4"
        }
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

private extension Pulse {
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

private extension Color {
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
