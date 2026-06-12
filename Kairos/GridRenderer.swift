import SwiftUI
import KairosCore

struct GridRenderFrame: Sendable, Equatable {
    enum Mode: String, CaseIterable, Sendable {
        case block
        case border
        case lineMD = "line-md"
        case lineSM = "line-sm"

        var displayName: String {
            switch self {
            case .block:
                return "Block"
            case .border:
                return "Border"
            case .lineMD:
                return "Line MD"
            case .lineSM:
                return "Line SM"
            }
        }
    }

    struct Cycle: Identifiable, Sendable, Equatable {
        let slot: CycleSlot
        let mode: Mode
        let stepCount: Int
        let activeStepIndex: Int?
        let anticipationRange: Range<Int>?
        let resetMark: GridResetMark

        var id: Int {
            slot.rawValue
        }
    }

    let cycles: [Cycle]

    var accessibilityLabel: String {
        guard
            let firstMode = cycles.first?.mode,
            cycles.allSatisfy({ $0.mode == firstMode })
        else {
            return "Kairos grid"
        }

        return "\(firstMode.displayName) grid"
    }

    init(cycles: [Cycle]) {
        self.cycles = cycles.sorted { $0.slot.rawValue < $1.slot.rawValue }
    }

    init(
        mode: Mode,
        currentStates: [CycleState],
        resetStates: [CycleResetState] = []
    ) {
        let resetMarks = GridResetMarkMapper.map(resetStates)
        self.init(cycles: currentStates
            .map { state in
                Cycle(
                    slot: state.config.slot,
                    mode: mode,
                    stepCount: state.config.stepNumber.rawValue,
                    activeStepIndex: state.currentStep,
                    anticipationRange: state.anticipationRange,
                    resetMark: resetMarks[state.config.slot] ?? .none
                )
            })
    }
}

private enum GridResetMarkMapper {
    static func map(_ resetStates: [CycleResetState]) -> [CycleSlot: GridResetMark] {
        Dictionary(
            uniqueKeysWithValues: resetStates.map { state in
                (state.slot, presentationMark(for: state.mark))
            }
        )
    }

    private static func presentationMark(for mark: KairosCore.GridResetMark) -> GridResetMark {
        switch mark {
        case .none:
            return .none
        case .combined:
            return .combined
        case .general:
            return .general
        }
    }
}

struct GridRenderer: View {
    let frame: GridRenderFrame

    var body: some View {
        Canvas(
            opaque: true,
            colorMode: .linear,
            rendersAsynchronously: false
        ) { context, size in
            GridCanvasRenderer.draw(
                frame: frame,
                in: &context,
                size: size
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: GridDesignTokens.radiusCanvas,
                style: .continuous
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(frame.accessibilityLabel))
    }

    static func idealHeight(for cycleCount: Int) -> CGFloat {
        let clampedCount = min(max(cycleCount, 1), 4)
        let rows = CGFloat(clampedCount)
        let totalGap = GridDesignTokens.rowGap * CGFloat(clampedCount - 1)
        return (GridDesignTokens.desktopRowHeight * rows) + totalGap
    }
}

private enum GridCanvasRenderer {
    static func draw(
        frame: GridRenderFrame,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let canvasRect = CGRect(origin: .zero, size: size)
        let backgroundPath = Path(
            roundedRect: canvasRect,
            cornerRadius: GridDesignTokens.radiusCanvas
        )
        context.fill(backgroundPath, with: .color(GridDesignTokens.backgroundSurface))

        guard !frame.cycles.isEmpty else {
            return
        }

        let rowCount = frame.cycles.count
        let totalGap = GridDesignTokens.rowGap * CGFloat(max(rowCount - 1, 0))
        let rowHeight = max(0, (size.height - totalGap) / CGFloat(rowCount))

        for (index, cycle) in frame.cycles.enumerated() {
            let rowRect = CGRect(
                x: 0,
                y: CGFloat(index) * (rowHeight + GridDesignTokens.rowGap),
                width: size.width,
                height: rowHeight
            )
            drawCycle(
                cycle,
                in: &context,
                rowRect: rowRect
            )
        }
    }

    private static func drawCycle(
        _ cycle: GridRenderFrame.Cycle,
        in context: inout GraphicsContext,
        rowRect: CGRect
    ) {
        let horizontalInset = min(GridDesignTokens.rowInset, rowRect.width / 2)
        let verticalInset = min(GridDesignTokens.rowInset, rowRect.height / 2)
        let contentRect = rowRect.insetBy(dx: horizontalInset, dy: verticalInset)
        let stepCount = max(cycle.stepCount, 1)
        let totalGap = GridDesignTokens.stepGap * CGFloat(max(stepCount - 1, 0))
        let stepWidth = max(0, (contentRect.width - totalGap) / CGFloat(stepCount))

        guard stepWidth > 0, contentRect.height > 0 else {
            return
        }

        for stepIndex in 0..<stepCount {
            let stepRect = CGRect(
                x: contentRect.minX + (CGFloat(stepIndex) * (stepWidth + GridDesignTokens.stepGap)),
                y: contentRect.minY,
                width: stepWidth,
                height: contentRect.height
            )

            let visualState = GridStepVisualState.resolve(
                stepIndex: stepIndex,
                activeStepIndex: cycle.activeStepIndex,
                anticipationRange: cycle.anticipationRange,
                resetMark: cycle.resetMark
            )

            drawStep(
                in: &context,
                rect: stepRect,
                state: visualState,
                mode: cycle.mode
            )
        }
    }

    private static func drawStep(
        in context: inout GraphicsContext,
        rect: CGRect,
        state: GridStepVisualState,
        mode: GridRenderFrame.Mode
    ) {
        switch mode {
        case .block:
            let radius = min(
                GridDesignTokens.surfaceRadius,
                rect.width / 2,
                rect.height / 2
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: radius),
                with: .color(state.color)
            )

        case .border:
            let lineWidth = min(
                GridDesignTokens.borderWidth,
                rect.width,
                rect.height
            )
            guard lineWidth > 0 else {
                return
            }
            let inset = lineWidth / 2
            let insetRect = rect.insetBy(dx: inset, dy: inset)
            let radius = max(
                0,
                min(
                    GridDesignTokens.surfaceRadius - inset,
                    insetRect.width / 2,
                    insetRect.height / 2
                )
            )
            context.stroke(
                Path(roundedRect: insetRect, cornerRadius: radius),
                with: .color(state.color),
                lineWidth: lineWidth
            )

        case .lineMD:
            drawLine(
                in: &context,
                rect: rect,
                state: state,
                targetWidth: GridDesignTokens.lineMediumWidth
            )

        case .lineSM:
            drawLine(
                in: &context,
                rect: rect,
                state: state,
                targetWidth: GridDesignTokens.lineSmallWidth
            )
        }
    }

    private static func drawLine(
        in context: inout GraphicsContext,
        rect: CGRect,
        state: GridStepVisualState,
        targetWidth: CGFloat
    ) {
        let lineWidth = min(targetWidth, rect.width)
        guard lineWidth > 0 else {
            return
        }
        let lineRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: lineWidth,
            height: rect.height
        )
        let radius = min(
            GridDesignTokens.lineRadius,
            lineRect.width / 2,
            lineRect.height / 2
        )

        context.fill(
            Path(roundedRect: lineRect, cornerRadius: radius),
            with: .color(state.color)
        )
    }
}

private enum GridStepVisualState {
    case active
    case inactive
    case resetCombined
    case resetGeneral
    case anticipation

    static func resolve(
        stepIndex: Int,
        activeStepIndex: Int?,
        anticipationRange: Range<Int>?,
        resetMark: GridResetMark
    ) -> GridStepVisualState {
        if stepIndex == 0 {
            switch resetMark {
            case .combined:
                return .resetCombined
            case .general:
                return .resetGeneral
            case .none:
                break
            }
        }

        if activeStepIndex == stepIndex {
            return .active
        }

        if anticipationRange?.contains(stepIndex) == true {
            return .anticipation
        }

        return .inactive
    }

    var color: Color {
        switch self {
        case .active:
            GridDesignTokens.stepActive
        case .inactive:
            GridDesignTokens.stepInactive
        case .resetCombined:
            GridDesignTokens.resetCombined
        case .resetGeneral:
            GridDesignTokens.resetGeneral
        case .anticipation:
            GridDesignTokens.anticipation
        }
    }
}

private enum GridDesignTokens {
    static let backgroundSurface = Color(red: 16.0 / 255.0, green: 16.0 / 255.0, blue: 18.0 / 255.0)
    static let stepActive = Color(red: 245.0 / 255.0, green: 247.0 / 255.0, blue: 250.0 / 255.0)
    static let stepInactive = Color(red: 36.0 / 255.0, green: 38.0 / 255.0, blue: 43.0 / 255.0)
    static let resetCombined = Color(red: 116.0 / 255.0, green: 215.0 / 255.0, blue: 154.0 / 255.0)
    static let resetGeneral = Color(red: 170.0 / 255.0, green: 130.0 / 255.0, blue: 219.0 / 255.0)
    static let anticipation = Color(red: 233.0 / 255.0, green: 130.0 / 255.0, blue: 132.0 / 255.0)

    static let surfaceRadius: CGFloat = 8
    static let lineRadius: CGFloat = 12
    static let radiusCanvas: CGFloat = 12
    static let borderWidth: CGFloat = 4
    static let lineMediumWidth: CGFloat = 8
    static let lineSmallWidth: CGFloat = 4
    static let rowGap: CGFloat = 16
    static let rowInset: CGFloat = 16
    static let stepGap: CGFloat = 8
    static let desktopPanelHeight: CGFloat = 560
    static let desktopRowHeight: CGFloat = (desktopPanelHeight - (rowGap * 3)) / 4
}

final class GridPreviewDriver {
    private let cycleEngine: any CycleEngine = TimeDomainFactory.makeCycleEngine()
    private let resetDetector: any ResetDetector = TimeDomainFactory.makeResetDetector()
    private var previousStatesBySlot: [CycleSlot: CycleState] = [:]

    func reset() {
        previousStatesBySlot = [:]
    }

    func makeFrame(
        settings: [GridCycleSettings],
        bpm: Int,
        offset: Offset,
        elapsedSeconds: TimeInterval
    ) -> GridRenderFrame {
        let enabledSettings = settings
            .filter(\.isEnabled)
            .sorted { $0.slot.rawValue < $1.slot.rawValue }

        guard !enabledSettings.isEmpty else {
            previousStatesBySlot = [:]
            return GridRenderFrame(cycles: [])
        }

        let beat = max(
            0,
            (elapsedSeconds * (Double(bpm) / 60.0)) + offset.beats(atTempo: Double(bpm))
        )
        let currentStates = cycleEngine.resolveStates(
            for: enabledSettings.map(\.cycleConfig),
            beat: beat,
            frozenOriginBeat: 0
        )

        let resetStates = resetStates(
            currentStates: currentStates,
            enabledSettings: enabledSettings
        )
        let resetMarks = GridResetMarkMapper.map(resetStates)

        previousStatesBySlot = Dictionary(
            uniqueKeysWithValues: currentStates.map { ($0.config.slot, $0) }
        )

        let statesBySlot = Dictionary(
            uniqueKeysWithValues: currentStates.map { ($0.config.slot, $0) }
        )

        let cycles = enabledSettings.compactMap { setting -> GridRenderFrame.Cycle? in
            guard let state = statesBySlot[setting.slot] else {
                return nil
            }

            return GridRenderFrame.Cycle(
                slot: setting.slot,
                mode: setting.visualMode.renderMode(for: setting.stepNumber),
                stepCount: state.config.stepNumber.rawValue,
                activeStepIndex: state.currentStep,
                anticipationRange: state.anticipationRange,
                resetMark: resetMarks[setting.slot] ?? .none
            )
        }

        return GridRenderFrame(cycles: cycles)
    }

    private func resetStates(
        currentStates: [CycleState],
        enabledSettings: [GridCycleSettings]
    ) -> [CycleResetState] {
        let previousStates = enabledSettings.compactMap { previousStatesBySlot[$0.slot] }

        guard previousStates.count == currentStates.count else {
            return []
        }

        return resetDetector.detectResets(
            previous: previousStates,
            current: currentStates
        )
    }
}

private extension GridVisualMode {
    func renderMode(for stepNumber: StepNumber) -> GridRenderFrame.Mode {
        switch self {
        case .block:
            return .block
        case .border:
            return .border
        case .line:
            return stepNumber.rawValue > StepNumber.thirtyTwo.rawValue ? .lineSM : .lineMD
        }
    }
}

struct GridRendererShowcase: View {
    private let sections = GridRendererShowcaseData.sections

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kairos Grid Renderer")
                        .font(.title2.weight(.semibold))
                    Text("SwiftUI Canvas renderer wired to static CycleState snapshots from KairosCore contracts.")
                        .foregroundStyle(.secondary)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.caption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        GridRenderer(frame: section.frame)
                            .frame(height: GridRenderer.idealHeight(for: section.frame.cycles.count))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1305, alignment: .leading)
        }
        .frame(minWidth: 960, minHeight: 720)
    }
}

private struct GridRendererShowcaseSection: Identifiable {
    let frame: GridRenderFrame
    let title: String
    let caption: String

    var id: String {
        title
    }
}

private enum GridRendererShowcaseData {
    private static let resetDetector: any ResetDetector = TimeDomainFactory.makeResetDetector()

    static let sections: [GridRendererShowcaseSection] = [
        GridRendererShowcaseSection(
            frame: blockFrame,
            title: "Block · 1 cycle",
            caption: "Active, inactive and anticipation on a single 16-step row."
        ),
        GridRendererShowcaseSection(
            frame: borderFrame,
            title: "Border · 3 cycles",
            caption: "Combined reset is derived from two wrapped cycles while the third keeps its current phase."
        ),
        GridRendererShowcaseSection(
            frame: lineMDFrame,
            title: "Line MD · 4 cycles",
            caption: "General reset derived from four wrapped cycles with density scaling up to 128 steps."
        ),
        GridRendererShowcaseSection(
            frame: lineSMFrame,
            title: "Line SM · 2 cycles",
            caption: "High-density line rendering with 64 and 128 steps."
        ),
    ]

    private static let blockFrame = GridRenderFrame(
        mode: .block,
        currentStates: [
            makeState(
                slot: .one,
                stepNumber: .sixteen,
                currentStep: 13,
                cycleIteration: 2,
                anticipationRange: 12..<16
            ),
        ]
    )

    private static let borderFrame = GridRenderFrame(
        mode: .border,
        currentStates: [
            makeState(
                slot: .one,
                stepNumber: .eight,
                currentStep: 0,
                cycleIteration: 4,
                anticipationRange: 7..<8
            ),
            makeState(
                slot: .two,
                stepNumber: .sixteen,
                currentStep: 0,
                cycleIteration: 2,
                anticipationRange: 12..<16
            ),
            makeState(
                slot: .three,
                stepNumber: .thirtyTwo,
                currentStep: 9,
                cycleIteration: 1,
                anticipationRange: 28..<32
            ),
        ],
        resetStates: resetDetector.detectResets(
            previous: [
                makeState(
                    slot: .one,
                    stepNumber: .eight,
                    currentStep: 7,
                    cycleIteration: 3,
                    anticipationRange: 7..<8
                ),
                makeState(
                    slot: .two,
                    stepNumber: .sixteen,
                    currentStep: 15,
                    cycleIteration: 1,
                    anticipationRange: 12..<16
                ),
                makeState(
                    slot: .three,
                    stepNumber: .thirtyTwo,
                    currentStep: 8,
                    cycleIteration: 1,
                    anticipationRange: 28..<32
                ),
            ],
            current: [
                makeState(
                    slot: .one,
                    stepNumber: .eight,
                    currentStep: 0,
                    cycleIteration: 4,
                    anticipationRange: 7..<8
                ),
                makeState(
                    slot: .two,
                    stepNumber: .sixteen,
                    currentStep: 0,
                    cycleIteration: 2,
                    anticipationRange: 12..<16
                ),
                makeState(
                    slot: .three,
                    stepNumber: .thirtyTwo,
                    currentStep: 9,
                    cycleIteration: 1,
                    anticipationRange: 28..<32
                ),
            ]
        )
    )

    private static let lineMDFrame = GridRenderFrame(
        mode: .lineMD,
        currentStates: [
            makeState(
                slot: .one,
                stepNumber: .four,
                currentStep: 0,
                cycleIteration: 8,
                anticipationRange: nil
            ),
            makeState(
                slot: .two,
                stepNumber: .sixteen,
                currentStep: 0,
                cycleIteration: 3,
                anticipationRange: 12..<16
            ),
            makeState(
                slot: .three,
                stepNumber: .thirtyTwo,
                currentStep: 0,
                cycleIteration: 2,
                anticipationRange: 28..<32
            ),
            makeState(
                slot: .four,
                stepNumber: .oneHundredTwentyEight,
                currentStep: 0,
                cycleIteration: 1,
                anticipationRange: 120..<128
            ),
        ],
        resetStates: resetDetector.detectResets(
            previous: [
                makeState(
                    slot: .one,
                    stepNumber: .four,
                    currentStep: 3,
                    cycleIteration: 7,
                    anticipationRange: nil
                ),
                makeState(
                    slot: .two,
                    stepNumber: .sixteen,
                    currentStep: 15,
                    cycleIteration: 2,
                    anticipationRange: 12..<16
                ),
                makeState(
                    slot: .three,
                    stepNumber: .thirtyTwo,
                    currentStep: 31,
                    cycleIteration: 1,
                    anticipationRange: 28..<32
                ),
                makeState(
                    slot: .four,
                    stepNumber: .oneHundredTwentyEight,
                    currentStep: 127,
                    cycleIteration: 0,
                    anticipationRange: 120..<128
                ),
            ],
            current: [
                makeState(
                    slot: .one,
                    stepNumber: .four,
                    currentStep: 0,
                    cycleIteration: 8,
                    anticipationRange: nil
                ),
                makeState(
                    slot: .two,
                    stepNumber: .sixteen,
                    currentStep: 0,
                    cycleIteration: 3,
                    anticipationRange: 12..<16
                ),
                makeState(
                    slot: .three,
                    stepNumber: .thirtyTwo,
                    currentStep: 0,
                    cycleIteration: 2,
                    anticipationRange: 28..<32
                ),
                makeState(
                    slot: .four,
                    stepNumber: .oneHundredTwentyEight,
                    currentStep: 0,
                    cycleIteration: 1,
                    anticipationRange: 120..<128
                ),
            ]
        )
    )

    private static let lineSMFrame = GridRenderFrame(
        mode: .lineSM,
        currentStates: [
            makeState(
                slot: .one,
                stepNumber: .sixtyFour,
                currentStep: 52,
                cycleIteration: 4,
                anticipationRange: 60..<64
            ),
            makeState(
                slot: .two,
                stepNumber: .oneHundredTwentyEight,
                currentStep: 124,
                cycleIteration: 1,
                anticipationRange: 120..<128
            ),
        ]
    )

    private static func makeState(
        slot: CycleSlot,
        stepNumber: StepNumber,
        currentStep: Int?,
        cycleIteration: Int?,
        anticipationRange: Range<Int>?
    ) -> CycleState {
        CycleState(
            config: CycleConfig(
                slot: slot,
                stepNumber: stepNumber,
                pulse: .oneQuarter
            ),
            currentStep: currentStep,
            cycleIteration: cycleIteration,
            anticipationRange: anticipationRange
        )
    }
}

#Preview("Grid Renderer Showcase") {
    GridRendererShowcase()
}
