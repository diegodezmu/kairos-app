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
        let stepModes: [Mode]?
        let stepCount: Int
        let activeStepIndex: Int?
        let anticipationRange: Range<Int>?
        let resetMark: GridResetMark
        let allowsCustomEditing: Bool

        var id: Int {
            slot.rawValue
        }
    }

    let cycles: [Cycle]

    var accessibilityLabel: String {
        guard
            cycles.allSatisfy({ $0.stepModes == nil }),
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
                    stepModes: nil,
                    stepCount: state.config.stepNumber.rawValue,
                    activeStepIndex: state.currentStep,
                    anticipationRange: state.anticipationRange,
                    resetMark: resetMarks[state.config.slot] ?? .none,
                    allowsCustomEditing: false
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
    var onStepTap: ((CycleSlot, Int) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                    context.withCGContext { cgContext in
                        GridCanvasRenderer.draw(
                            frame: frame,
                            in: cgContext,
                            size: size
                        )
                    }
                }

                if let onStepTap {
                    GridInteractionOverlay(
                        targets: GridLayoutMetrics.editableTargets(
                            for: frame,
                            size: geometry.size
                        ),
                        onStepTap: onStepTap
                    )
                }
            }
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
        in context: CGContext,
        size: CGSize
    ) {
        let canvasRect = CGRect(origin: .zero, size: size)
        let backgroundPath = CGPath(
            roundedRect: canvasRect,
            cornerWidth: GridDesignTokens.radiusCanvas,
            cornerHeight: GridDesignTokens.radiusCanvas,
            transform: nil
        )
        context.setFillColor(GridDesignTokens.backgroundSurface.cgColor)
        context.addPath(backgroundPath)
        context.fillPath()

        guard !frame.cycles.isEmpty else {
            return
        }

        let rowCount = frame.cycles.count
        let totalGap = GridDesignTokens.rowGap * CGFloat(max(rowCount - 1, 0))
        let rowHeight = max(0, (size.height - totalGap) / CGFloat(rowCount))

        for (index, cycle) in frame.cycles.enumerated() {
            let rowRect = GridLayoutMetrics.rowRect(
                at: index,
                rowHeight: rowHeight,
                totalWidth: size.width
            )
            drawCycle(
                cycle,
                in: context,
                rowRect: rowRect
            )
        }
    }

    private static func drawCycle(
        _ cycle: GridRenderFrame.Cycle,
        in context: CGContext,
        rowRect: CGRect
    ) {
        let horizontalInset = min(GridDesignTokens.rowInset, rowRect.width / 2)
        let verticalInset = min(GridDesignTokens.rowInset, rowRect.height / 2)
        let contentRect = rowRect.insetBy(dx: horizontalInset, dy: verticalInset)
        let stepCount = max(cycle.stepCount, 1)
        let stepWidth = GridLayoutMetrics.stepWidth(
            stepCount: stepCount,
            contentRect: contentRect
        )

        guard stepWidth > 0, contentRect.height > 0 else {
            return
        }

        for stepIndex in 0..<stepCount {
            let stepRect = GridLayoutMetrics.stepRect(
                stepIndex: stepIndex,
                stepCount: stepCount,
                contentRect: contentRect
            )

            let visualState = GridStepVisualState.resolve(
                stepIndex: stepIndex,
                activeStepIndex: cycle.activeStepIndex,
                anticipationRange: cycle.anticipationRange,
                resetMark: cycle.resetMark
            )
            let mode = cycle.stepModes?[safe: stepIndex] ?? cycle.mode

            drawStep(
                in: context,
                rect: stepRect,
                state: visualState,
                mode: mode
            )
        }
    }

    private static func drawStep(
        in context: CGContext,
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
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            context.setFillColor(state.color.cgColor)
            context.addPath(path)
            context.fillPath()

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
            let path = CGPath(
                roundedRect: insetRect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            context.setStrokeColor(state.color.cgColor)
            context.setLineWidth(lineWidth)
            context.addPath(path)
            context.strokePath()

        case .lineMD:
            drawLine(
                in: context,
                rect: rect,
                state: state,
                targetWidth: GridDesignTokens.lineMediumWidth
            )

        case .lineSM:
            drawLine(
                in: context,
                rect: rect,
                state: state,
                targetWidth: GridDesignTokens.lineSmallWidth
            )
        }
    }

    private static func drawLine(
        in context: CGContext,
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

        let path = CGPath(
            roundedRect: lineRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        context.setFillColor(state.color.cgColor)
        context.addPath(path)
        context.fillPath()
    }
}

enum GridStepVisualState: Equatable {
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

        if
            activeStepIndex == stepIndex,
            anticipationRange?.contains(stepIndex) == true
        {
            return .anticipation
        }

        if activeStepIndex == stepIndex {
            return .active
        }

        return .inactive
    }

    var color: GridResolvedColor {
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

struct GridResolvedColor: Sendable, Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let opacity: CGFloat

    init(
        red: Int,
        green: Int,
        blue: Int,
        opacity: CGFloat = 1
    ) {
        self.red = CGFloat(red) / 255.0
        self.green = CGFloat(green) / 255.0
        self.blue = CGFloat(blue) / 255.0
        self.opacity = opacity
    }

    var color: Color {
        Color(
            .sRGB,
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(opacity)
        )
    }

    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [red, green, blue, opacity]
        )!
    }
}

private enum GridDesignTokens {
    static let backgroundSurface = GridResolvedColor(red: 16, green: 16, blue: 18)
    static let stepActive = GridResolvedColor(red: 245, green: 247, blue: 250)
    static let stepInactive = GridResolvedColor(red: 36, green: 38, blue: 43)
    static let resetCombined = GridResolvedColor(red: 116, green: 215, blue: 154)
    static let resetGeneral = GridResolvedColor(red: 170, green: 130, blue: 219)
    static let anticipation = GridResolvedColor(red: 233, green: 130, blue: 132)

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
    private var latchedResetMarksBySlot: [CycleSlot: GridResetMark] = [:]

    func reset() {
        previousStatesBySlot = [:]
        latchedResetMarksBySlot = [:]
    }

    func makeFrame(
        settings: [GridCycleSettings],
        bpm: Int,
        offset: Offset,
        elapsedSeconds: TimeInterval
    ) -> GridRenderFrame {
        let beat = max(
            0,
            (elapsedSeconds * (Double(bpm) / 60.0)) + offset.beats(atTempo: Double(bpm))
        )
        return makeFrame(
            settings: settings,
            beat: beat
        )
    }

    func makeFrame(
        settings: [GridCycleSettings],
        beat: Double
    ) -> GridRenderFrame {
        let enabledSettings = settings
            .filter(\.isEnabled)
            .sorted { $0.slot.rawValue < $1.slot.rawValue }

        guard !enabledSettings.isEmpty else {
            previousStatesBySlot = [:]
            latchedResetMarksBySlot = [:]
            return GridRenderFrame(cycles: [])
        }

        let currentStates = cycleEngine.resolveStates(
            for: enabledSettings.map(\.cycleConfig),
            beat: beat,
            frozenOriginBeat: 0
        )

        let resetStates = resetStates(
            currentStates: currentStates,
            enabledSettings: enabledSettings
        )
        let resetMarks = resolveResetMarks(
            currentStates: currentStates,
            detectedResetMarks: GridResetMarkMapper.map(resetStates)
        )

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

            let presentation = setting.visualMode.presentation(
                for: setting.stepNumber,
                customStepModes: setting.customStepModes
            )

            return GridRenderFrame.Cycle(
                slot: setting.slot,
                mode: presentation.fallbackMode,
                stepModes: presentation.stepModes,
                stepCount: state.config.stepNumber.rawValue,
                activeStepIndex: state.currentStep,
                anticipationRange: state.anticipationRange,
                resetMark: resetMarks[setting.slot] ?? .none,
                allowsCustomEditing: presentation.allowsCustomEditing
            )
        }

        return GridRenderFrame(cycles: cycles)
    }

    private func resolveResetMarks(
        currentStates: [CycleState],
        detectedResetMarks: [CycleSlot: GridResetMark]
    ) -> [CycleSlot: GridResetMark] {
        var nextLatchedMarksBySlot: [CycleSlot: GridResetMark] = [:]

        for state in currentStates {
            guard state.currentStep == 0 else {
                continue
            }

            let slot = state.config.slot
            if let detectedMark = detectedResetMarks[slot], detectedMark != .none {
                nextLatchedMarksBySlot[slot] = detectedMark
                continue
            }

            if let latchedMark = latchedResetMarksBySlot[slot], latchedMark != .none {
                nextLatchedMarksBySlot[slot] = latchedMark
            }
        }

        latchedResetMarksBySlot = nextLatchedMarksBySlot
        return nextLatchedMarksBySlot
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
    func presentation(
        for stepNumber: StepNumber,
        customStepModes: [GridStepDisplayMode]?
    ) -> GridCyclePresentation {
        switch self {
        case .block:
            return GridCyclePresentation(
                fallbackMode: .block,
                stepModes: nil,
                allowsCustomEditing: false
            )
        case .border:
            return GridCyclePresentation(
                fallbackMode: .border,
                stepModes: nil,
                allowsCustomEditing: false
            )
        case .line:
            return GridCyclePresentation(
                fallbackMode: renderMode(for: .line, stepNumber: stepNumber),
                stepModes: nil,
                allowsCustomEditing: false
            )
        case .custom:
            guard stepNumber != .oneHundredTwentyEight else {
                return GridCyclePresentation(
                    fallbackMode: .lineSM,
                    stepModes: nil,
                    allowsCustomEditing: false
                )
            }

            let modes = SettingsDefaults.normalizedCustomStepModes(
                customStepModes,
                stepCount: stepNumber.rawValue,
                fallback: .block
            ) ?? Array(repeating: .block, count: stepNumber.rawValue)

            return GridCyclePresentation(
                fallbackMode: renderMode(for: .block, stepNumber: stepNumber),
                stepModes: modes.map { renderMode(for: $0, stepNumber: stepNumber) },
                allowsCustomEditing: true
            )
        }
    }

    private func renderMode(
        for displayMode: GridStepDisplayMode,
        stepNumber: StepNumber
    ) -> GridRenderFrame.Mode {
        switch displayMode {
        case .block:
            return .block
        case .border:
            return .border
        case .line:
            return stepNumber.rawValue > StepNumber.thirtyTwo.rawValue ? .lineSM : .lineMD
        }
    }
}

private struct GridCyclePresentation {
    let fallbackMode: GridRenderFrame.Mode
    let stepModes: [GridRenderFrame.Mode]?
    let allowsCustomEditing: Bool
}

private struct GridEditableStepTarget: Identifiable {
    let cycleSlot: CycleSlot
    let stepIndex: Int
    let rect: CGRect

    var id: String {
        "\(cycleSlot.rawValue)-\(stepIndex)"
    }
}

private enum GridLayoutMetrics {
    static func rowRect(
        at index: Int,
        rowHeight: CGFloat,
        totalWidth: CGFloat
    ) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(index) * (rowHeight + GridDesignTokens.rowGap),
            width: totalWidth,
            height: rowHeight
        )
    }

    static func stepWidth(
        stepCount: Int,
        contentRect: CGRect
    ) -> CGFloat {
        let totalGap = GridDesignTokens.stepGap * CGFloat(max(stepCount - 1, 0))
        return max(0, (contentRect.width - totalGap) / CGFloat(stepCount))
    }

    static func stepRect(
        stepIndex: Int,
        stepCount: Int,
        contentRect: CGRect
    ) -> CGRect {
        let width = stepWidth(
            stepCount: stepCount,
            contentRect: contentRect
        )

        return CGRect(
            x: contentRect.minX + (CGFloat(stepIndex) * (width + GridDesignTokens.stepGap)),
            y: contentRect.minY,
            width: width,
            height: contentRect.height
        )
    }

    static func editableTargets(
        for frame: GridRenderFrame,
        size: CGSize
    ) -> [GridEditableStepTarget] {
        guard !frame.cycles.isEmpty else {
            return []
        }

        let rowCount = frame.cycles.count
        let totalGap = GridDesignTokens.rowGap * CGFloat(max(rowCount - 1, 0))
        let rowHeight = max(0, (size.height - totalGap) / CGFloat(rowCount))

        return frame.cycles.enumerated().flatMap { index, cycle in
            guard cycle.allowsCustomEditing else {
                return [GridEditableStepTarget]()
            }

            let rowRect = rowRect(
                at: index,
                rowHeight: rowHeight,
                totalWidth: size.width
            )
            let horizontalInset = min(GridDesignTokens.rowInset, rowRect.width / 2)
            let verticalInset = min(GridDesignTokens.rowInset, rowRect.height / 2)
            let contentRect = rowRect.insetBy(dx: horizontalInset, dy: verticalInset)

            return (0..<max(cycle.stepCount, 0)).map { stepIndex in
                GridEditableStepTarget(
                    cycleSlot: cycle.slot,
                    stepIndex: stepIndex,
                    rect: stepRect(
                        stepIndex: stepIndex,
                        stepCount: cycle.stepCount,
                        contentRect: contentRect
                    )
                )
            }
        }
    }
}

private struct GridInteractionOverlay: View {
    let targets: [GridEditableStepTarget]
    let onStepTap: (CycleSlot, Int) -> Void

    var body: some View {
        ForEach(targets) { target in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: target.rect.width, height: target.rect.height)
                .position(
                    x: target.rect.midX,
                    y: target.rect.midY
                )
                .onTapGesture {
                    onStepTap(target.cycleSlot, target.stepIndex)
                }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
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
