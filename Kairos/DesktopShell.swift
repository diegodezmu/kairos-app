import Observation
import SwiftUI
import KairosCore

@MainActor
@Observable
final class DesktopShellModel {
    let settings: SettingsModel

    private let presetStore: PresetStore?
    private let gridPreviewDriver = GridPreviewDriver()
    private let levelPreviewDriver = LevelPreviewDriver()

    private(set) var presetLibrary: PresetLibrary
    private(set) var storageErrorMessage: String?

    var isSidebarVisible = true
    var isPreviewPlaying = false
    var isMetronomeEnabled = false

    private var accumulatedElapsed: TimeInterval = 0
    private var playbackStartedAt: Date?

    init(
        settings: SettingsModel = SettingsModel(),
        presetStore: PresetStore? = try? PresetStore()
    ) {
        self.settings = settings
        self.presetStore = presetStore
        presetLibrary = .factoryDefault
        synchronizeTransportState()

        Task {
            await loadPresets()
        }
    }

    var canControlTransport: Bool {
        settings.syncSource == .internalClock
    }

    var canEditTempo: Bool {
        settings.syncSource == .internalClock
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

            synchronizeTransportState()
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

    func selectPreset(
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
        synchronizeTransportState()
        resetPreview(at: date)
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func togglePlay(at date: Date) {
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
    }

    func resetPreview(at date: Date) {
        accumulatedElapsed = 0
        playbackStartedAt = isPreviewPlaying ? date : nil
        gridPreviewDriver.reset()
        levelPreviewDriver.reset()
    }

    func setSyncSource(
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

    func setOffset(_ milliseconds: Double) {
        settings.offset = Offset(milliseconds: milliseconds)
    }

    func setBPM(_ bpm: Int) {
        settings.bpm = bpm
    }

    func setMetronomePulse(_ pulse: Pulse) {
        settings.metronomePulse = pulse
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
            cycle.visualMode = mode
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
    }

    func setLaneTargetLevel(
        _ targetLevelDB: Double,
        lane: LaneID
    ) {
        settings.updateLevelLane(lane: lane) { configuration in
            configuration.targetLevelDB = targetLevelDB
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

    func snapshot(at date: Date) -> DesktopShellSnapshot {
        let elapsedSeconds = previewElapsedSeconds(at: date)
        let elapsedMilliseconds = UInt64(
            max((elapsedSeconds * 1_000.0).rounded(), 0)
        )
        let gridFrame = gridPreviewDriver.makeFrame(
            settings: settings.gridCycles,
            bpm: settings.bpm,
            offset: settings.offset,
            elapsedSeconds: elapsedSeconds
        )
        let levelSnapshot = levelPreviewDriver.snapshot(
            at: elapsedMilliseconds,
            timestamp: date.timeIntervalSinceReferenceDate,
            laneConfigurations: settings.levelLanes
        )

        return DesktopShellSnapshot(
            gridFrame: gridFrame,
            levelExpandedFrame: levelSnapshot.expandedFrame,
            levelSplitFrame: levelSnapshot.splitFrame,
            laneStatuses: levelSnapshot.statuses,
            elapsedText: DesktopShellFormatters.elapsedTime(elapsedSeconds),
            bpmText: DesktopShellFormatters.bpm(settings.bpm),
            syncStatus: syncStatusDescriptor
        )
    }

    private var syncStatusDescriptor: SyncStatusDescriptor {
        switch settings.syncSource {
        case .internalClock:
            return SyncStatusDescriptor(
                text: "Internal",
                tone: .neutral,
                showsLinkIcon: false
            )
        case .midiClock:
            switch settings.midiClockStatus {
            case .idle:
                return SyncStatusDescriptor(
                    text: "MIDI idle",
                    tone: .neutral,
                    showsLinkIcon: false
                )
            case .receiving:
                return SyncStatusDescriptor(
                    text: "MIDI receiving",
                    tone: .success,
                    showsLinkIcon: false
                )
            case .disconnected:
                return SyncStatusDescriptor(
                    text: "MIDI disconnected",
                    tone: .danger,
                    showsLinkIcon: false
                )
            }
        case .link:
            guard settings.linkStatus.isEnabled else {
                return SyncStatusDescriptor(
                    text: "Link off",
                    tone: .danger,
                    showsLinkIcon: true
                )
            }

            if settings.linkStatus.peerCount == 0 {
                return SyncStatusDescriptor(
                    text: "Link active - no peers",
                    tone: .neutral,
                    showsLinkIcon: true
                )
            }

            let peerLabel = settings.linkStatus.peerCount == 1 ? "peer" : "peers"
            return SyncStatusDescriptor(
                text: "Link active - \(settings.linkStatus.peerCount) \(peerLabel)",
                tone: .success,
                showsLinkIcon: true
            )
        }
    }

    private func synchronizeTransportState() {
        switch settings.syncSource {
        case .internalClock:
            settings.midiClockStatus = .idle
            settings.linkStatus = .off
        case .midiClock:
            settings.midiClockStatus = .idle
            settings.linkStatus = .off
            isPreviewPlaying = false
            playbackStartedAt = nil
            accumulatedElapsed = 0
        case .link:
            settings.midiClockStatus = .idle
            settings.linkStatus = LinkStatus(
                isEnabled: true,
                peerCount: 0,
                tempoBPM: nil
            )
            isPreviewPlaying = false
            playbackStartedAt = nil
            accumulatedElapsed = 0
        }
    }

    private func previewElapsedSeconds(at date: Date) -> TimeInterval {
        guard canControlTransport else {
            return 0
        }

        return elapsedTime(at: date)
    }

    private func elapsedTime(at date: Date) -> TimeInterval {
        guard isPreviewPlaying, let playbackStartedAt else {
            return accumulatedElapsed
        }

        return accumulatedElapsed + max(date.timeIntervalSince(playbackStartedAt), 0)
    }

    private static func normalizedName(
        _ name: String,
        fallback: String
    ) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct DesktopShellSnapshot {
    let gridFrame: GridRenderFrame
    let levelExpandedFrame: LevelRenderFrame
    let levelSplitFrame: LevelRenderFrame
    let laneStatuses: [LaneID: LaneInputStatus]
    let elapsedText: String
    let bpmText: String
    let syncStatus: SyncStatusDescriptor
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

struct DesktopShellRootView: View {
    @State private var model = DesktopShellModel()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            DesktopShellView(
                model: model,
                snapshot: model.snapshot(at: timeline.date),
                now: timeline.date
            )
        }
        .frame(minWidth: 1_280, minHeight: 820)
        .background(DesktopShellTokens.backgroundCanvas)
    }
}

private struct DesktopShellView: View {
    let model: DesktopShellModel
    let snapshot: DesktopShellSnapshot
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            DesktopToolbarView(
                model: model,
                snapshot: snapshot,
                now: now
            )

            HStack(spacing: 0) {
                if model.isSidebarVisible {
                    DesktopSidebarWrapper {
                        DesktopSidebarView(
                            model: model,
                            snapshot: snapshot,
                            now: now
                        )
                    }
                    DesktopSidebarHandle()
                }

                DesktopWorkspaceView(
                    settings: model.settings,
                    snapshot: snapshot
                )
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .background(DesktopShellTokens.backgroundCanvas)
    }
}

private struct DesktopToolbarView: View {
    let model: DesktopShellModel
    let snapshot: DesktopShellSnapshot
    let now: Date

    var body: some View {
        HStack(spacing: DesktopShellTokens.componentGapXL) {
            HStack(spacing: DesktopShellTokens.componentGapXL) {
                Text("KAIROS")
                    .font(DesktopShellTypography.wordmark)
                    .foregroundStyle(DesktopShellTokens.textTertiary)

                PresetSelectorButton(
                    title: model.activePresetToolbarLabel,
                    activeSlot: model.settings.activePresetSlot,
                    onSelect: { slot in
                        model.selectPreset(slot, at: now)
                    },
                    onSave: { slot in
                        Task {
                            await model.saveCurrentPreset(to: slot)
                        }
                    }
                )

                HStack(spacing: DesktopShellTokens.componentGapXS) {
                    ToolbarIconButton(
                        icon: .sidebar,
                        isActive: model.isSidebarVisible,
                        action: model.toggleSidebar
                    )

                    ToolbarIconButton(
                        icon: model.isPreviewPlaying ? .stop : .play,
                        isDisabled: !model.canControlTransport,
                        action: {
                            model.togglePlay(at: now)
                        }
                    )

                    ToolbarIconButton(
                        icon: .reset,
                        action: {
                            model.resetPreview(at: now)
                        }
                    )

                    ToolbarIconButton(
                        icon: .metronome,
                        isActive: model.isMetronomeEnabled,
                        action: {
                            model.isMetronomeEnabled.toggle()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesktopShellTokens.componentGapLG) {
                DataAtomView(text: snapshot.elapsedText)
                DataAtomView(
                    text: snapshot.bpmText,
                    isDisabled: !model.canEditTempo
                )
                SyncStatusView(descriptor: snapshot.syncStatus)
                    .frame(minWidth: 146, alignment: .leading)
            }
        }
        .padding(.horizontal, DesktopShellTokens.componentGapLG)
        .padding(.vertical, DesktopShellTokens.componentGapSM)
        .frame(height: DesktopShellTokens.toolbarHeight)
        .background(DesktopShellTokens.backgroundCanvas)
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

private struct DesktopSidebarHandle: View {
    var body: some View {
        VStack {
            Capsule(style: .continuous)
                .fill(DesktopShellTokens.actionSecondary)
                .frame(width: 8, height: 200)
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .padding(.leading, 4)
        .padding(.trailing, 12)
    }
}

private struct DesktopSidebarView: View {
    let model: DesktopShellModel
    let snapshot: DesktopShellSnapshot
    let now: Date

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
                GlobalSidebarSection(
                    model: model,
                    snapshot: snapshot,
                    now: now
                )

                GridSidebarSection(model: model)

                LevelSidebarSection(
                    model: model,
                    laneStatuses: snapshot.laneStatuses
                )
            }
            .padding(DesktopShellTokens.layoutGapLG)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesktopShellTokens.backgroundSurface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesktopShellTokens.radiusCanvas,
                style: .continuous
            )
        )
    }
}

private struct GlobalSidebarSection: View {
    let model: DesktopShellModel
    let snapshot: DesktopShellSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapXL) {
            Text("Global")
                .font(DesktopShellTypography.titleMD)
                .foregroundStyle(DesktopShellTokens.textSecondary)

            VStack(spacing: DesktopShellTokens.layoutGapSM) {
                SidebarCardSection(title: "Sync") {
                    VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapLG) {
                        HStack(spacing: DesktopShellTokens.layoutGapLG) {
                            ForEach(SyncSource.allCases, id: \.self) { source in
                                SegmentButton(
                                    title: source.buttonLabel,
                                    isSelected: model.settings.syncSource == source,
                                    trailingIcon: source == .midiClock ? .chevronDown : nil,
                                    action: {
                                        model.setSyncSource(source, at: now)
                                    }
                                )
                            }
                        }

                        SyncStatusView(
                            descriptor: snapshot.syncStatus,
                            compact: false
                        )

                        SidebarValueRow(label: "Offset") {
                            DoubleEditorButton(
                                value: model.settings.offset.milliseconds,
                                range: Offset.minimumMilliseconds...Offset.maximumMilliseconds,
                                step: 10,
                                formatter: DesktopShellFormatters.offset,
                                onCommit: model.setOffset
                            )
                        }
                    }
                }

                Divider()
                    .background(DesktopShellTokens.borderDefault)

                SidebarCardSection(title: "Tempo") {
                    VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapLG) {
                        SidebarValueRow(label: "BPM") {
                            IntEditorButton(
                                value: model.settings.bpm,
                                range: 1...999,
                                step: 1,
                                formatter: DesktopShellFormatters.bpmControl,
                                isDisabled: !model.canEditTempo,
                                onCommit: model.setBPM
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
            .padding(DesktopShellTokens.layoutGapLG)
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
                        Divider()
                            .background(DesktopShellTokens.borderDefault)
                    }
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
                Text(cycle.name)
                    .font(DesktopShellTypography.titleSM)
                    .foregroundStyle(DesktopShellTokens.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: DesktopShellTokens.layoutGapSM) {
                    RenameButton(
                        currentName: cycle.name,
                        onCommit: onRename
                    )

                    PowerIconButton(
                        isOn: cycle.isEnabled,
                        action: {
                            onToggle(cycle)
                        }
                    )
                }
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
    }
}

private struct LevelSidebarSection: View {
    let model: DesktopShellModel
    let laneStatuses: [LaneID: LaneInputStatus]

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
                        status: laneStatuses[lane.lane],
                        onRename: { model.renameLane(lane: lane.lane, name: $0) },
                        onToggle: { model.setLaneEnabled(!$0.isEnabled, lane: lane.lane) },
                        onTargetLevel: { model.setLaneTargetLevel($0, lane: lane.lane) },
                        onHistoryRange: { model.setLaneHistoryRange($0, lane: lane.lane) }
                    )

                    if lane.lane != model.settings.levelLanes.last?.lane {
                        Divider()
                            .background(DesktopShellTokens.borderDefault)
                    }
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
    }
}

private struct LevelLaneCard: View {
    let lane: LevelLaneConfiguration
    let status: LaneInputStatus?
    let onRename: (String) -> Void
    let onToggle: (LevelLaneConfiguration) -> Void
    let onTargetLevel: (Double) -> Void
    let onHistoryRange: (HistoryRange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: lane.isEnabled ? DesktopShellTokens.componentGapMD : DesktopShellTokens.layoutGapXL) {
            VStack(alignment: .leading, spacing: lane.isEnabled ? DesktopShellTokens.componentGapMD : 0) {
                HStack(spacing: DesktopShellTokens.layoutGapXL) {
                    Text(lane.name)
                        .font(DesktopShellTypography.titleSM)
                        .foregroundStyle(DesktopShellTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: DesktopShellTokens.layoutGapSM) {
                        RenameButton(
                            currentName: lane.name,
                            onCommit: onRename
                        )

                        PowerIconButton(
                            isOn: lane.isEnabled,
                            action: {
                                onToggle(lane)
                            }
                        )
                    }
                }

                if lane.isEnabled, let status {
                    InputStatusView(status: status)
                }
            }

            if lane.isEnabled {
                VStack(alignment: .leading, spacing: DesktopShellTokens.layoutGapLG) {
                    SidebarValueRow(label: "Target level") {
                        DoubleEditorButton(
                            value: lane.targetLevelDB,
                            range: -60...0,
                            step: 1,
                            formatter: DesktopShellFormatters.targetLevel,
                            onCommit: onTargetLevel
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
    }
}

private struct DesktopWorkspaceView: View {
    let settings: SettingsModel
    let snapshot: DesktopShellSnapshot

    var body: some View {
        GeometryReader { geometry in
            let contentHeight = max(geometry.size.height, 320)
            let levelHeight = min(max(contentHeight * 0.322, 260), 380)
            let gridHeight = max(contentHeight - levelHeight - DesktopShellTokens.layoutGapLG, 280)

            VStack(spacing: DesktopShellTokens.layoutGapLG) {
                if settings.isGridVisible, settings.isLevelVisible {
                    gridSurface
                        .frame(height: gridHeight)

                    levelSplitSurface
                        .frame(height: levelHeight)
                } else if settings.isGridVisible {
                    gridSurface
                        .frame(maxHeight: .infinity)
                } else if settings.isLevelVisible {
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
        RendererSurface(
            hasContent: !snapshot.gridFrame.cycles.isEmpty,
            emptyTitle: "Enable a cycle to preview Grid."
        ) {
            GridRenderer(frame: snapshot.gridFrame)
        }
    }

    private var levelSplitSurface: some View {
        RendererSurface(
            hasContent: !snapshot.levelSplitFrame.lanes.isEmpty,
            emptyTitle: "Enable a window to preview Level."
        ) {
            LevelRenderer(frame: snapshot.levelSplitFrame)
        }
    }

    private var levelExpandedSurface: some View {
        RendererSurface(
            hasContent: !snapshot.levelExpandedFrame.lanes.isEmpty,
            emptyTitle: "Enable a window to preview Level."
        ) {
            LevelRenderer(frame: snapshot.levelExpandedFrame)
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
    var isDisabled = false

    var body: some View {
        Text(text)
            .font(DesktopShellTypography.labelXS)
            .foregroundStyle(DesktopShellTokens.textTertiary)
            .opacity(isDisabled ? 0.55 : 1)
            .padding(.vertical, DesktopShellTokens.componentGapXS)
            .padding(.horizontal, DesktopShellTokens.componentGapXS)
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
                .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        }
        .padding(.vertical, DesktopShellTokens.componentGapXS)
        .padding(.horizontal, compact ? DesktopShellTokens.componentGapXS : 0)
    }
}

private struct InputStatusView: View {
    let status: LaneInputStatus

    var body: some View {
        guard status.state != .disabled else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: DesktopShellTokens.componentGapSM) {
                Circle()
                    .fill(statusColor)
                    .frame(width: DesktopShellTokens.statusDotSize, height: DesktopShellTokens.statusDotSize)

                Text(status.displayLabel)
                    .font(DesktopShellTypography.labelXS)
                    .foregroundStyle(DesktopShellTokens.textTertiary)
                    .lineLimit(1)
            }
        )
    }

    private var statusColor: Color {
        switch status.state {
        case .disabled:
            return .clear
        case .noSignal:
            return DesktopShellTokens.actionPrimary
        case .receiving:
            return DesktopShellTokens.statusSuccess
        case .clipping:
            return DesktopShellTokens.statusDanger
        }
    }
}

private struct ToolbarIconButton: View {
    let icon: KairosIcon
    var isActive = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            buttonSurface(
                kind: .ghost,
                isActive: isActive,
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

    var body: some View {
        Button(action: action) {
            buttonSurface(kind: .filled, isActive: isSelected) {
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
        .buttonStyle(.plain)
    }
}

private struct RenameButton: View {
    let currentName: String
    let onCommit: (String) -> Void

    @State private var isPresented = false
    @State private var draftName = ""

    var body: some View {
        Button {
            draftName = currentName
            isPresented = true
        } label: {
            buttonSurface(kind: .filled) {
                KairosIconView(
                    icon: .rename,
                    color: DesktopShellTokens.actionPrimary
                )
                .frame(
                    width: DesktopShellTokens.iconSize,
                    height: DesktopShellTokens.iconSize
                )
            }
        }
        .buttonStyle(.plain)
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
        .menuStyle(.borderlessButton)
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
        .menuStyle(.borderlessButton)
    }
}

private struct IntEditorButton: View {
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let formatter: (Int) -> String
    var isDisabled = false
    let onCommit: (Int) -> Void

    @State private var isPresented = false
    @State private var draftValue = 0

    var body: some View {
        Button {
            guard !isDisabled else {
                return
            }

            draftValue = value
            isPresented = true
        } label: {
            MenuValueLabel(
                title: formatter(value),
                icon: .doubleArrow,
                style: .outlined,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $draftValue, in: range, step: step) {
                    Text(formatter(draftValue))
                        .font(DesktopShellTypography.labelMD)
                }

                TextField(
                    "Value",
                    value: $draftValue,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                    }
                    Button("Apply") {
                        onCommit(draftValue)
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }
}

private struct DoubleEditorButton: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var isPresented = false
    @State private var draftValue = 0.0

    var body: some View {
        Button {
            draftValue = value
            isPresented = true
        } label: {
            MenuValueLabel(
                title: formatter(value),
                icon: .doubleArrow,
                style: .outlined
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $draftValue, in: range, step: step) {
                    Text(formatter(draftValue))
                        .font(DesktopShellTypography.labelMD)
                }

                TextField(
                    "Value",
                    value: $draftValue,
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                    }
                    Button("Apply") {
                        onCommit(min(max(draftValue, range.lowerBound), range.upperBound))
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
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
            .frame(minWidth: width, alignment: .leading)
        }
    }
}

private enum ButtonSurfaceKind {
    case ghost
    case filled
    case outlined
}

private func buttonSurface<Content: View>(
    kind: ButtonSurfaceKind,
    isActive: Bool = false,
    isDisabled: Bool = false,
    @ViewBuilder content: () -> Content
) -> some View {
    let fillColor: Color
    let borderColor: Color

    switch kind {
    case .ghost:
        fillColor = isActive ? DesktopShellTokens.actionAccent : Color.clear
        borderColor = .clear
    case .filled:
        fillColor = isActive ? DesktopShellTokens.actionAccent : DesktopShellTokens.actionSecondary
        borderColor = .clear
    case .outlined:
        fillColor = DesktopShellTokens.backgroundElevated
        borderColor = DesktopShellTokens.borderSubtle
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
            .stroke(borderColor, lineWidth: kind == .outlined ? DesktopShellTokens.borderWidth : 0)
        )
}

private enum KairosIcon {
    case sidebar
    case play
    case stop
    case reset
    case metronome
    case power
    case rename
    case link
    case chevronDown
    case doubleArrow
    case modeBlock
    case modeBorder
    case modeLine
}

private struct KairosIconView: View {
    let icon: KairosIcon
    let color: Color

    var body: some View {
        switch icon {
        case .sidebar:
            SidebarGlyph(color: color)
        case .play:
            PlayGlyph(color: color)
        case .stop:
            StopGlyph(color: color)
        case .reset:
            ResetGlyph(color: color)
        case .metronome:
            MetronomeGlyph(color: color)
        case .power:
            PowerGlyph(color: color)
        case .rename:
            RenameGlyph(color: color)
        case .link:
            LinkGlyph(color: color)
        case .chevronDown:
            ChevronDownGlyph(color: color)
        case .doubleArrow:
            DoubleArrowGlyph(color: color)
        case .modeBlock:
            ModeBlockGlyph(color: color)
        case .modeBorder:
            ModeBorderGlyph(color: color)
        case .modeLine:
            ModeLineGlyph(color: color)
        }
    }
}

private struct SidebarGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let rect = geometry.frame(in: .local).insetBy(dx: 3, dy: 4)

            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(color, lineWidth: 1.5)

                Rectangle()
                    .fill(color)
                    .frame(width: 1.5)
                    .padding(.vertical, 4)
                    .offset(x: -rect.width * 0.18)
            }
        }
    }
}

private struct PlayGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.34, y: height * 0.22))
                path.addLine(to: CGPoint(x: width * 0.34, y: height * 0.78))
                path.addLine(to: CGPoint(x: width * 0.74, y: height * 0.50))
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

private struct StopGlyph: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .padding(5)
    }
}

private struct ResetGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let center = CGPoint(x: width * 0.52, y: height * 0.54)
            let radius = min(width, height) * 0.28

            Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(28),
                    endAngle: .degrees(320),
                    clockwise: true
                )
                path.move(to: CGPoint(x: width * 0.36, y: height * 0.14))
                path.addLine(to: CGPoint(x: width * 0.56, y: height * 0.18))
                path.addLine(to: CGPoint(x: width * 0.46, y: height * 0.32))
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: 1.6,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}

private struct MetronomeGlyph: View {
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PowerGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let center = CGPoint(x: width * 0.50, y: height * 0.56)
            let radius = min(width, height) * 0.30

            ZStack {
                Path { path in
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(48),
                        endAngle: .degrees(312),
                        clockwise: true
                    )
                }
                .stroke(color, lineWidth: 1.6)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.50, y: height * 0.14))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.48))
                }
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }
        }
    }
}

private struct RenameGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.18, y: height * 0.34))
                path.addLine(to: CGPoint(x: width * 0.54, y: height * 0.12))
                path.addLine(to: CGPoint(x: width * 0.82, y: height * 0.38))
                path.addLine(to: CGPoint(x: width * 0.48, y: height * 0.76))
                path.addLine(to: CGPoint(x: width * 0.18, y: height * 0.76))
                path.closeSubpath()
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineJoin: .round
                )
            )
            .overlay {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: width * 0.12, height: width * 0.12)
                    .offset(x: width * 0.16, y: -height * 0.04)
            }
        }
    }
}

private struct LinkGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.20, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: width * 0.40, height: height * 0.46)
                    .offset(x: -width * 0.16, y: 0)

                RoundedRectangle(cornerRadius: width * 0.20, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: width * 0.40, height: height * 0.46)
                    .offset(x: width * 0.16, y: 0)
            }
        }
    }
}

private struct ChevronDownGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.28, y: height * 0.40))
                path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.62))
                path.addLine(to: CGPoint(x: width * 0.72, y: height * 0.40))
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: 1.6,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}

private struct DoubleArrowGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.30, y: height * 0.36))
                path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.18))
                path.addLine(to: CGPoint(x: width * 0.70, y: height * 0.36))

                path.move(to: CGPoint(x: width * 0.30, y: height * 0.64))
                path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.82))
                path.addLine(to: CGPoint(x: width * 0.70, y: height * 0.64))
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}

private struct ModeBlockGlyph: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(color)
            .padding(5)
    }
}

private struct ModeBorderGlyph: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .stroke(color, lineWidth: 1.5)
            .padding(5)
    }
}

private struct ModeLineGlyph: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: 1.5,
                    dash: [1.5, 1.5]
                )
            )
            .padding(5)
    }
}

private enum DesktopShellTypography {
    static let wordmark = Font.system(size: 13, weight: .bold)
    static let titleMD = Font.system(size: 18, weight: .semibold)
    static let titleSM = Font.system(size: 16, weight: .semibold)
    static let bodyLG = Font.system(size: 15, weight: .regular)
    static let labelMD = Font.system(size: 14, weight: .medium)
    static let labelXS = Font.system(size: 12, weight: .semibold)
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
    static let actionAccent = Color(hex: 0x4378B8)
    static let textSecondary = Color(hex: 0xAEB8C4)
    static let textTertiary = Color(hex: 0x8792A0)
    static let borderSubtle = Color(hex: 0x24262B)
    static let borderDefault = Color(hex: 0x2F3238)
    static let statusSuccess = Color(hex: 0x43B973)
    static let statusDanger = Color(hex: 0xCA5256)

    static let toolbarHeight: CGFloat = 56
    static let sidebarWidth: CGFloat = 375
    static let sidebarOuterWidth: CGFloat = 391
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

    static let layoutGapSM: CGFloat = 8
    static let layoutGapLG: CGFloat = 16
    static let layoutGapXL: CGFloat = 24
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

    static func bpmControl(_ bpm: Int) -> String {
        String(format: "%.2f", Double(bpm))
    }

    static func offset(_ milliseconds: Double) -> String {
        String(format: "%.2f ms", milliseconds)
    }

    static func targetLevel(_ db: Double) -> String {
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
        case .midiClock:
            return "MIDI"
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
