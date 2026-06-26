import SwiftUI
import KairosCore

struct DesktopSidebarWrapper<Content: View>: View {
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

struct SidebarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DesktopSidebarView: View {
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

struct GlobalSidebarSection: View {
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

struct LiveSyncStatusView: View {
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

struct GridSidebarSection: View {
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

struct GridCycleCard: View {
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

struct LevelSidebarSection: View {
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

struct LevelTelemetryStatusView: View {
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

struct LevelLaneCard: View {
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
