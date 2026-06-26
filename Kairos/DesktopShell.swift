import SwiftUI
import KairosCore

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

struct ExternalTransportSnapshot {
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

extension PresetLibrary {
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
