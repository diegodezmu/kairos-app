import Foundation
import SwiftUI
import KairosCore

struct LevelRenderFrame: Sendable, Equatable {
    enum Layout: String, Sendable {
        case fourWindows = "Four Windows"
        case singleExpanded = "Single Expanded"

        var displayName: String {
            rawValue
        }
    }

    struct Lane: Identifiable, Sendable, Equatable {
        struct Column: Sendable, Equatable {
            let minimumDB: CGFloat
            let maximumDB: CGFloat
            let meanDB: CGFloat
        }

        struct Channel: Sendable, Equatable {
            let currentDB: CGFloat
            let borderColor: LevelResolvedColor
            let fillColor: LevelResolvedColor
            let columns: [Column]
        }

        let lane: LaneID
        let targetDB: CGFloat
        let historyRange: HistoryRange
        let latestHostTime: UInt64
        let left: Channel
        let right: Channel

        var id: Int {
            lane.rawValue
        }
    }

    let layout: Layout
    let lanes: [Lane]
    let generalResetMarks: [UInt64]
}

struct LevelRenderer: View {
    let frame: LevelRenderFrame

    var body: some View {
        Group {
            switch frame.layout {
            case .singleExpanded:
                if let lane = frame.lanes.first {
                    LevelWindowCanvas(
                        lane: lane,
                        generalResetMarks: frame.generalResetMarks
                    )
                }
            case .fourWindows:
                HStack(spacing: LevelDesignTokens.windowGap) {
                    ForEach(frame.lanes) { lane in
                        LevelWindowCanvas(
                            lane: lane,
                            generalResetMarks: frame.generalResetMarks
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(frame.layout.displayName) level renderer"))
    }

    static func idealHeight(for layout: LevelRenderFrame.Layout) -> CGFloat {
        switch layout {
        case .fourWindows:
            return LevelDesignTokens.fourWindowHeight
        case .singleExpanded:
            return LevelDesignTokens.singleExpandedHeight
        }
    }
}

private struct LevelWindowCanvas: View {
    let lane: LevelRenderFrame.Lane
    let generalResetMarks: [UInt64]

    var body: some View {
        Canvas(
            opaque: true,
            colorMode: .linear,
            rendersAsynchronously: false
        ) { context, size in
            LevelCanvasRenderer.draw(
                lane: lane,
                generalResetMarks: generalResetMarks,
                in: &context,
                size: size
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: LevelDesignTokens.radiusCanvas,
                style: .continuous
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Source \(lane.lane.rawValue) level meter"))
    }
}

private enum LevelCanvasRenderer {
    private static let scaleBands: [(db: CGFloat, label: String)] = [
        (0, "0"),
        (-6, "- 6"),
        (-12, "- 12"),
        (-18, "- 18"),
        (-24, "- 24"),
        (-30, "- 30"),
        (-60, "- 60"),
    ]

    static func draw(
        lane: LevelRenderFrame.Lane,
        generalResetMarks: [UInt64],
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let canvasRect = CGRect(origin: .zero, size: size)
        let backgroundPath = Path(
            roundedRect: canvasRect,
            cornerRadius: LevelDesignTokens.radiusCanvas
        )
        context.fill(backgroundPath, with: .color(LevelDesignTokens.backgroundSurface.color))

        let contentRect = canvasRect.insetBy(
            dx: min(LevelDesignTokens.panelPadding, canvasRect.width / 4),
            dy: min(LevelDesignTokens.panelPadding, canvasRect.height / 4)
        )
        let meterX = contentRect.minX + LevelDesignTokens.labelWidth + LevelDesignTokens.labelGap
        let meterRect = CGRect(
            x: meterX,
            y: contentRect.minY,
            width: max(0, contentRect.width - (LevelDesignTokens.labelWidth + LevelDesignTokens.labelGap)),
            height: max(0, contentRect.height)
        )

        guard meterRect.width > 0, meterRect.height > 0 else {
            return
        }

        context.fill(
            Path(meterRect),
            with: .color(LevelDesignTokens.meterBackground.color)
        )

        drawChannel(lane.left, in: &context, meterRect: meterRect)
        drawChannel(lane.right, in: &context, meterRect: meterRect)
        drawResetMarks(
            generalResetMarks,
            latestHostTime: lane.latestHostTime,
            historyRange: lane.historyRange,
            in: &context,
            meterRect: meterRect
        )
        drawScale(in: &context, meterRect: meterRect)
        drawBorders(for: lane.left, in: &context, meterRect: meterRect)
        drawBorders(for: lane.right, in: &context, meterRect: meterRect)
        drawLabels(in: &context, meterRect: meterRect)
    }

    private static func drawChannel(
        _ channel: LevelRenderFrame.Lane.Channel,
        in context: inout GraphicsContext,
        meterRect: CGRect
    ) {
        let meanPoints = historyPoints(
            for: channel.columns,
            currentDB: channel.currentDB,
            in: meterRect,
            value: \.meanDB
        )

        guard let firstPoint = meanPoints.first else {
            return
        }

        var fillPath = Path()
        fillPath.move(to: CGPoint(x: meterRect.minX, y: meterRect.maxY))
        fillPath.addLine(to: firstPoint)
        fillPath.addLines(meanPoints)
        fillPath.addLine(to: CGPoint(x: meterRect.maxX, y: meterRect.maxY))
        fillPath.closeSubpath()

        context.fill(fillPath, with: .color(channel.fillColor.color))

        let upperPoints = historyPoints(
            for: channel.columns,
            currentDB: channel.currentDB,
            in: meterRect,
            value: \.maximumDB
        )
        let lowerPoints = historyPoints(
            for: channel.columns,
            currentDB: channel.currentDB,
            in: meterRect,
            value: \.minimumDB
        )

        if let rangePath = rangeEnvelopePath(
            upperPoints: upperPoints,
            lowerPoints: lowerPoints
        ) {
            context.fill(
                rangePath,
                with: .color(channel.fillColor.withOpacity(0.16).color)
            )
        }
    }

    private static func drawBorders(
        for channel: LevelRenderFrame.Lane.Channel,
        in context: inout GraphicsContext,
        meterRect: CGRect
    ) {
        let borderPoints = historyPoints(
            for: channel.columns,
            currentDB: channel.currentDB,
            in: meterRect,
            value: \.meanDB
        )

        guard let firstPoint = borderPoints.first else {
            return
        }

        var borderPath = Path()
        borderPath.move(to: firstPoint)
        borderPath.addLines(Array(borderPoints.dropFirst()))

        context.stroke(
            borderPath,
            with: .color(channel.borderColor.color),
            style: StrokeStyle(
                lineWidth: LevelDesignTokens.borderWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private static func drawResetMarks(
        _ marks: [UInt64],
        latestHostTime: UInt64,
        historyRange: HistoryRange,
        in context: inout GraphicsContext,
        meterRect: CGRect
    ) {
        let visibleRangeMilliseconds = UInt64(historyRange.rawValue * 1_000.0)
        guard visibleRangeMilliseconds > 0 else {
            return
        }

        for mark in marks {
            guard latestHostTime >= mark else {
                continue
            }

            let age = latestHostTime - mark
            guard age <= visibleRangeMilliseconds else {
                continue
            }

            let progress = CGFloat(age) / CGFloat(visibleRangeMilliseconds)
            let centerX = meterRect.maxX - (progress * meterRect.width)
            let rect = CGRect(
                x: centerX - (LevelDesignTokens.resetMarkSize.width / 2),
                y: meterRect.minY + 8,
                width: LevelDesignTokens.resetMarkSize.width,
                height: min(LevelDesignTokens.resetMarkSize.height, meterRect.height - 8)
            )

            context.fill(
                Path(roundedRect: rect, cornerRadius: LevelDesignTokens.resetMarkSize.width / 2),
                with: .color(LevelDesignTokens.resetGeneral.withOpacity(0.78).color)
            )
        }
    }

    private static func drawScale(
        in context: inout GraphicsContext,
        meterRect: CGRect
    ) {
        for band in scaleBands {
            let rawY = yPosition(for: band.db, in: meterRect)
            let y = floor(rawY) + 0.5
            var path = Path()
            path.move(to: CGPoint(x: meterRect.minX, y: y))
            path.addLine(to: CGPoint(x: meterRect.maxX, y: y))

            let color = band.db == -12
                ? LevelDesignTokens.scaleAccent.color
                : LevelDesignTokens.meterScaleLine.color

            context.stroke(
                path,
                with: .color(color),
                lineWidth: LevelDesignTokens.scaleLineWidth
            )
        }
    }

    private static func drawLabels(
        in context: inout GraphicsContext,
        meterRect: CGRect
    ) {
        let labelX = meterRect.minX - LevelDesignTokens.labelGap

        for band in scaleBands {
            let y = yPosition(for: band.db, in: meterRect)
            let color = band.db == -12
                ? LevelDesignTokens.scaleAccent.color
                : LevelDesignTokens.textTertiary.color

            let label = Text(band.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)

            context.draw(
                label,
                at: CGPoint(x: labelX, y: y),
                anchor: .trailing
            )
        }
    }

    private static func historyPoints(
        for columns: [LevelRenderFrame.Lane.Column],
        currentDB: CGFloat,
        in meterRect: CGRect,
        value: KeyPath<LevelRenderFrame.Lane.Column, CGFloat>
    ) -> [CGPoint] {
        guard !columns.isEmpty else {
            return [
                CGPoint(
                    x: meterRect.maxX,
                    y: yPosition(for: currentDB, in: meterRect)
                )
            ]
        }

        let step = meterRect.width / CGFloat(max(columns.count, 1))
        var points = columns.enumerated().map { index, column in
            CGPoint(
                x: meterRect.minX + (CGFloat(index) * step),
                y: yPosition(for: column[keyPath: value], in: meterRect)
            )
        }
        points.append(
            CGPoint(
                x: meterRect.maxX,
                y: yPosition(for: currentDB, in: meterRect)
            )
        )
        return points
    }

    private static func rangeEnvelopePath(
        upperPoints: [CGPoint],
        lowerPoints: [CGPoint]
    ) -> Path? {
        guard
            let firstUpper = upperPoints.first,
            upperPoints.count == lowerPoints.count
        else {
            return nil
        }

        var path = Path()
        path.move(to: firstUpper)
        path.addLines(Array(upperPoints.dropFirst()))
        path.addLines(Array(lowerPoints.reversed()))
        path.closeSubpath()
        return path
    }

    private static func yPosition(
        for db: CGFloat,
        in rect: CGRect
    ) -> CGFloat {
        let clamped = min(max(db, LevelDecibelScale.floorDB), LevelDecibelScale.ceilingDB)
        let progress = (LevelDecibelScale.ceilingDB - clamped) / LevelDecibelScale.visibleRange
        return rect.minY + (progress * rect.height)
    }
}

private final class LevelPresentationPipeline {
    private enum SemanticState {
        case inTarget
        case outOfTarget
    }

    private struct ChannelKey: Hashable {
        let lane: LaneID
        let side: LevelChannelSide
    }

    private struct BorderAnimationState {
        var semanticState: SemanticState
        var displayedOutTargetMix: CGFloat
        var lastTimestamp: TimeInterval?
    }

    private var borderStates: [ChannelKey: BorderAnimationState] = [:]

    func makeFrame(
        layout: LevelRenderFrame.Layout,
        inputs: [LevelLaneInput],
        generalResetMarks: [UInt64],
        timestamp: TimeInterval
    ) -> LevelRenderFrame {
        let lanes = inputs.map { input in
            LevelRenderFrame.Lane(
                lane: input.lane,
                targetDB: input.targetDB,
                historyRange: input.history.range,
                latestHostTime: input.latestHostTime,
                left: resolveChannel(
                    currentSample: input.currentSample,
                    history: input.history,
                    lane: input.lane,
                    side: .left,
                    targetDB: input.targetDB,
                    timestamp: timestamp
                ),
                right: resolveChannel(
                    currentSample: input.currentSample,
                    history: input.history,
                    lane: input.lane,
                    side: .right,
                    targetDB: input.targetDB,
                    timestamp: timestamp
                )
            )
        }

        return LevelRenderFrame(
            layout: layout,
            lanes: lanes,
            generalResetMarks: generalResetMarks
        )
    }

    private func resolveChannel(
        currentSample: LaneDynamicsSample,
        history: LaneHistorySnapshot,
        lane: LaneID,
        side: LevelChannelSide,
        targetDB: CGFloat,
        timestamp: TimeInterval
    ) -> LevelRenderFrame.Lane.Channel {
        let currentAmplitude = side == .left ? currentSample.rmsLeft : currentSample.rmsRight
        let currentDB = LevelDecibelScale.displayDBFS(for: currentAmplitude)

        let key = ChannelKey(lane: lane, side: side)
        let semanticState = semanticState(
            currentDB: currentDB,
            targetDB: targetDB,
            previous: borderStates[key]?.semanticState
        )

        var animationState = borderStates[key] ?? BorderAnimationState(
            semanticState: semanticState,
            displayedOutTargetMix: semanticState == .outOfTarget ? 1 : 0,
            lastTimestamp: timestamp
        )

        animationState.semanticState = semanticState

        let targetMix: CGFloat = semanticState == .outOfTarget ? 1 : 0
        let deltaTime = max(0, timestamp - (animationState.lastTimestamp ?? timestamp))
        let progress = min(1, CGFloat(deltaTime / LevelDesignTokens.targetCrossfadeDuration))
        animationState.displayedOutTargetMix += (targetMix - animationState.displayedOutTargetMix) * progress
        animationState.lastTimestamp = timestamp
        borderStates[key] = animationState

        let fillColor = isClipping(currentSample: currentSample, side: side)
            ? LevelDesignTokens.clip
            : LevelDesignTokens.meterFillBody

        return LevelRenderFrame.Lane.Channel(
            currentDB: currentDB,
            borderColor: LevelDesignTokens.inTarget.blended(
                with: LevelDesignTokens.outTarget,
                amount: animationState.displayedOutTargetMix
            ),
            fillColor: fillColor,
            columns: history.buckets.map { bucket in
                LevelRenderFrame.Lane.Column(
                    minimumDB: LevelDecibelScale.displayDBFS(
                        for: side == .left ? bucket.minimumRMSLeft : bucket.minimumRMSRight
                    ),
                    maximumDB: LevelDecibelScale.displayDBFS(
                        for: side == .left ? bucket.maximumRMSLeft : bucket.maximumRMSRight
                    ),
                    meanDB: LevelDecibelScale.displayDBFS(
                        for: side == .left ? bucket.meanRMSLeft : bucket.meanRMSRight
                    )
                )
            }
        )
    }

    private func semanticState(
        currentDB: CGFloat,
        targetDB: CGFloat,
        previous: SemanticState?
    ) -> SemanticState {
        let distance = abs(currentDB - targetDB)
        let currentState = previous ?? (distance > LevelDesignTokens.targetMarginDB ? .outOfTarget : .inTarget)

        switch currentState {
        case .inTarget:
            return distance > LevelDesignTokens.targetMarginDB ? .outOfTarget : .inTarget
        case .outOfTarget:
            return distance < (LevelDesignTokens.targetMarginDB - LevelDesignTokens.targetHysteresisDB)
                ? .inTarget
                : .outOfTarget
        }
    }

    private func isClipping(
        currentSample: LaneDynamicsSample,
        side: LevelChannelSide
    ) -> Bool {
        switch side {
        case .left:
            return currentSample.clipLeft
        case .right:
            return currentSample.clipRight
        }
    }
}

private struct LevelLaneInput {
    let lane: LaneID
    let targetDB: CGFloat
    let currentSample: LaneDynamicsSample
    let history: LaneHistorySnapshot
    let latestHostTime: UInt64
}

private enum LevelChannelSide {
    case left
    case right
}

private struct LevelLaneSettings {
    let lane: LaneID
    let targetDB: CGFloat
    let historyRange: HistoryRange
    let baseDB: Double
    let slowSwingDB: Double
    let fastSwingDB: Double
    let stereoSpreadDB: Double
    let clipPeriodMilliseconds: UInt64?
    let clipChannel: LevelChannelSide?
}

private final class LevelShowcaseDriver: ObservableObject {
    private let historyBuffer: any HistoryBuffer = DynamicsCoreFactory.makeHistoryBuffer()
    private let resetDetector: any ResetDetector = TimeDomainFactory.makeResetDetector()
    private let clipDetectors: [any ClipDetector] = LaneID.allCases.map { _ in
        DynamicsCoreFactory.makeClipDetector()
    }
    private let presentationPipeline = LevelPresentationPipeline()
    private let historyStepMilliseconds: UInt64 = 100
    private let resetStepMilliseconds: UInt64 = 500
    private let seedDurationMilliseconds: UInt64 = UInt64(HistoryRange.twoMinutes.rawValue * 1_000.0)
    private let startDate = Date()
    private let fourWindowSettings: [LevelLaneSettings] = [
        LevelLaneSettings(
            lane: .one,
            targetDB: -12,
            historyRange: .tenSeconds,
            baseDB: -11.5,
            slowSwingDB: 3.5,
            fastSwingDB: 1.5,
            stereoSpreadDB: 1.2,
            clipPeriodMilliseconds: 19_000,
            clipChannel: .left
        ),
        LevelLaneSettings(
            lane: .two,
            targetDB: -18,
            historyRange: .thirtySeconds,
            baseDB: -17.0,
            slowSwingDB: 5.0,
            fastSwingDB: 1.8,
            stereoSpreadDB: 1.6,
            clipPeriodMilliseconds: nil,
            clipChannel: nil
        ),
        LevelLaneSettings(
            lane: .three,
            targetDB: -9,
            historyRange: .oneMinute,
            baseDB: -13.0,
            slowSwingDB: 6.5,
            fastSwingDB: 2.4,
            stereoSpreadDB: 2.0,
            clipPeriodMilliseconds: 23_000,
            clipChannel: .right
        ),
        LevelLaneSettings(
            lane: .four,
            targetDB: -24,
            historyRange: .twoMinutes,
            baseDB: -24.5,
            slowSwingDB: 7.5,
            fastSwingDB: 2.2,
            stereoSpreadDB: 2.5,
            clipPeriodMilliseconds: nil,
            clipChannel: nil
        ),
    ]
    private let expandedSetting = LevelLaneSettings(
        lane: .one,
        targetDB: -12,
        historyRange: .thirtySeconds,
        baseDB: -11.5,
        slowSwingDB: 3.5,
        fastSwingDB: 1.5,
        stereoSpreadDB: 1.2,
        clipPeriodMilliseconds: 19_000,
        clipChannel: .left
    )

    private var historyCursorMilliseconds: UInt64 = 0
    private var resetCursorMilliseconds: UInt64 = 0
    private var previousResetStates: [CycleState]
    private var generalResetMarks: [UInt64] = []

    init() {
        previousResetStates = LevelShowcaseDriver.syntheticCycleStates(at: 0)
        seedHistory()
        seedResetMarks()
    }

    func frames(at date: Date) -> (expanded: LevelRenderFrame, split: LevelRenderFrame) {
        let elapsedMilliseconds = UInt64(
            max(0, (date.timeIntervalSince(startDate) * 1_000.0).rounded())
        )
        let playheadMilliseconds = seedDurationMilliseconds + elapsedMilliseconds

        advanceHistory(to: playheadMilliseconds)
        advanceResetMarks(to: playheadMilliseconds)

        let currentSample = syntheticDisplaySample(at: playheadMilliseconds)
        let timestamp = date.timeIntervalSinceReferenceDate

        let expandedFrame = presentationPipeline.makeFrame(
            layout: .singleExpanded,
            inputs: [
                makeInput(
                    for: expandedSetting,
                    from: currentSample,
                    columnCount: LevelDesignTokens.expandedColumnCount
                ),
            ],
            generalResetMarks: generalResetMarks,
            timestamp: timestamp
        )

        let splitFrame = presentationPipeline.makeFrame(
            layout: .fourWindows,
            inputs: fourWindowSettings.map {
                makeInput(
                    for: $0,
                    from: currentSample,
                    columnCount: LevelDesignTokens.fourWindowColumnCount
                )
            },
            generalResetMarks: generalResetMarks,
            timestamp: timestamp
        )

        return (expandedFrame, splitFrame)
    }

    private func seedHistory() {
        appendHistorySample(at: 0)
        while historyCursorMilliseconds + historyStepMilliseconds <= seedDurationMilliseconds {
            historyCursorMilliseconds += historyStepMilliseconds
            appendHistorySample(at: historyCursorMilliseconds)
        }
    }

    private func seedResetMarks() {
        while resetCursorMilliseconds + resetStepMilliseconds <= seedDurationMilliseconds {
            let next = resetCursorMilliseconds + resetStepMilliseconds
            recordResetMarks(at: next)
            resetCursorMilliseconds = next
        }
    }

    private func advanceHistory(to targetMilliseconds: UInt64) {
        while historyCursorMilliseconds + historyStepMilliseconds <= targetMilliseconds {
            historyCursorMilliseconds += historyStepMilliseconds
            appendHistorySample(at: historyCursorMilliseconds)
        }
    }

    private func advanceResetMarks(to targetMilliseconds: UInt64) {
        while resetCursorMilliseconds + resetStepMilliseconds <= targetMilliseconds {
            let next = resetCursorMilliseconds + resetStepMilliseconds
            recordResetMarks(at: next)
            resetCursorMilliseconds = next
        }

        generalResetMarks.removeAll { mark in
            targetMilliseconds > mark && (targetMilliseconds - mark) > seedDurationMilliseconds
        }
    }

    private func appendHistorySample(at milliseconds: UInt64) {
        historyBuffer.append(
            makeDynamicsSample(
                at: milliseconds,
                includeClipState: false
            )
        )
    }

    private func syntheticDisplaySample(at milliseconds: UInt64) -> DynamicsSample {
        makeDynamicsSample(
            at: milliseconds,
            includeClipState: true
        )
    }

    private func makeInput(
        for settings: LevelLaneSettings,
        from sample: DynamicsSample,
        columnCount: Int
    ) -> LevelLaneInput {
        LevelLaneInput(
            lane: settings.lane,
            targetDB: settings.targetDB,
            currentSample: laneSample(from: sample, lane: settings.lane),
            history: historyBuffer.snapshot(
                for: settings.lane,
                range: settings.historyRange,
                columnCount: columnCount
            ),
            latestHostTime: sample.hostTime
        )
    }

    private func recordResetMarks(at milliseconds: UInt64) {
        let currentStates = LevelShowcaseDriver.syntheticCycleStates(at: milliseconds)
        let resetStates = resetDetector.detectResets(
            previous: previousResetStates,
            current: currentStates
        )

        if resetStates.contains(where: { $0.mark == .general }) {
            generalResetMarks.append(milliseconds)
        }

        previousResetStates = currentStates
    }

    private func makeDynamicsSample(
        at milliseconds: UInt64,
        includeClipState: Bool
    ) -> DynamicsSample {
        let fourWindowSamples = Dictionary(
            uniqueKeysWithValues: fourWindowSettings.map { settings in
                (settings.lane, makeLaneSample(settings: settings, at: milliseconds, includeClipState: includeClipState))
            }
        )
        let expandedSample = makeLaneSample(
            settings: expandedSetting,
            at: milliseconds,
            includeClipState: includeClipState
        )

        return DynamicsSample(
            hostTime: milliseconds,
            sampleTime: Int64(milliseconds),
            frameCount: 1,
            sampleRate: 1_000,
            lane1: expandedSample,
            lane2: fourWindowSamples[.two] ?? LevelShowcaseDriver.emptyLaneSample,
            lane3: fourWindowSamples[.three] ?? LevelShowcaseDriver.emptyLaneSample,
            lane4: fourWindowSamples[.four] ?? LevelShowcaseDriver.emptyLaneSample
        )
    }

    private func makeLaneSample(
        settings: LevelLaneSettings,
        at milliseconds: UInt64,
        includeClipState: Bool
    ) -> LaneDynamicsSample {
        let time = Double(milliseconds) / 1_000.0
        let lanePhase = Double(settings.lane.rawValue) * 0.73

        let bodyDB =
            settings.baseDB +
            (settings.slowSwingDB * sin((time * 0.38) + lanePhase)) +
            (settings.fastSwingDB * sin((time * 1.14) + (lanePhase * 0.61)))

        let leftDB = max(
            LevelDecibelScale.floorDB,
            min(
                -0.5,
                bodyDB + (settings.stereoSpreadDB * sin((time * 0.87) + lanePhase))
            )
        )
        let rightDB = max(
            LevelDecibelScale.floorDB,
            min(
                -0.5,
                bodyDB - (settings.stereoSpreadDB * cos((time * 0.93) + (lanePhase * 0.77)))
            )
        )

        let rmsLeft = LevelDecibelScale.amplitude(for: CGFloat(leftDB))
        let rmsRight = LevelDecibelScale.amplitude(for: CGFloat(rightDB))

        var peakLeft = min(0.98, max(rmsLeft * 1.45, rmsLeft))
        var peakRight = min(0.98, max(rmsRight * 1.45, rmsRight))

        if
            let clipPeriodMilliseconds = settings.clipPeriodMilliseconds,
            let clipChannel = settings.clipChannel
        {
            let window = milliseconds % clipPeriodMilliseconds
            let clipActive = window >= (clipPeriodMilliseconds - 700)

            if clipActive {
                switch clipChannel {
                case .left:
                    peakLeft = 1.04
                case .right:
                    peakRight = 1.04
                }
            }
        }

        let clipState: (left: Bool, right: Bool)
        if includeClipState {
            let detector = clipDetectors[settings.lane.rawValue - 1]
            clipState = detector.detectClipping(
                leftPeak: peakLeft,
                rightPeak: peakRight
            )
        } else {
            clipState = (false, false)
        }

        return LaneDynamicsSample(
            rmsLeft: rmsLeft,
            rmsRight: rmsRight,
            peakLeft: peakLeft,
            peakRight: peakRight,
            clipLeft: clipState.left,
            clipRight: clipState.right
        )
    }

    private static func syntheticCycleStates(at milliseconds: UInt64) -> [CycleState] {
        let stepDurationMilliseconds: UInt64 = 500
        let absoluteStep = Int(milliseconds / stepDurationMilliseconds)
        let currentStep = absoluteStep % StepNumber.sixteen.rawValue
        let cycleIteration = absoluteStep / StepNumber.sixteen.rawValue

        return CycleSlot.allCases.map { slot in
            CycleState(
                config: CycleConfig(
                    slot: slot,
                    stepNumber: .sixteen,
                    pulse: .oneQuarter
                ),
                currentStep: currentStep,
                cycleIteration: cycleIteration,
                anticipationRange: 12..<16
            )
        }
    }

    private func laneSample(
        from sample: DynamicsSample,
        lane: LaneID
    ) -> LaneDynamicsSample {
        switch lane {
        case .one:
            return sample.lane1
        case .two:
            return sample.lane2
        case .three:
            return sample.lane3
        case .four:
            return sample.lane4
        }
    }

    private static let emptyLaneSample = LaneDynamicsSample(
        rmsLeft: 0,
        rmsRight: 0,
        peakLeft: 0,
        peakRight: 0,
        clipLeft: false,
        clipRight: false
    )
}

struct LevelRendererShowcase: View {
    @StateObject private var driver = LevelShowcaseDriver()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let frames = driver.frames(at: timeline.date)

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kairos Level Renderer")
                            .font(.title2.weight(.semibold))
                        Text("SwiftUI Canvas renderer driven by synthetic DynamicsSample payloads, HistoryBuffer snapshots, and ResetDetector events from KairosCore.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Single Expanded")
                            .font(.headline)
                        Text("One full-width lane using a 30 s history viewport, reset marks, and per-channel target feedback.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LevelRenderer(frame: frames.expanded)
                            .frame(
                                width: 1_696,
                                height: LevelRenderer.idealHeight(for: .singleExpanded)
                            )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Four Windows")
                            .font(.headline)
                        Text("Four desktop windows sharing the same drawing language while varying targets and history ranges.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LevelRenderer(frame: frames.split)
                            .frame(
                                width: 1_305,
                                height: LevelRenderer.idealHeight(for: .fourWindows)
                            )
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 1_400, minHeight: 900)
    }
}

private enum LevelDecibelScale {
    static let ceilingDB: CGFloat = 0
    static let floorDB: CGFloat = -60
    static let visibleRange: CGFloat = abs(floorDB - ceilingDB)

    static func displayDBFS(for amplitude: Float) -> CGFloat {
        guard amplitude > 0 else {
            return floorDB
        }

        let db = 20 * log10(Double(amplitude))
        return min(max(CGFloat(db), floorDB), ceilingDB)
    }

    static func amplitude(for db: CGFloat) -> Float {
        Float(pow(10, Double(db) / 20))
    }
}

struct LevelResolvedColor: Sendable, Equatable {
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

    func withOpacity(_ value: CGFloat) -> LevelResolvedColor {
        LevelResolvedColor(
            red: Int((red * 255.0).rounded()),
            green: Int((green * 255.0).rounded()),
            blue: Int((blue * 255.0).rounded()),
            opacity: value
        )
    }

    func blended(
        with other: LevelResolvedColor,
        amount: CGFloat
    ) -> LevelResolvedColor {
        let clampedAmount = min(max(amount, 0), 1)
        let inverse = 1 - clampedAmount

        return LevelResolvedColor(
            red: Int((((red * inverse) + (other.red * clampedAmount)) * 255.0).rounded()),
            green: Int((((green * inverse) + (other.green * clampedAmount)) * 255.0).rounded()),
            blue: Int((((blue * inverse) + (other.blue * clampedAmount)) * 255.0).rounded()),
            opacity: (opacity * inverse) + (other.opacity * clampedAmount)
        )
    }
}

private enum LevelDesignTokens {
    static let backgroundSurface = LevelResolvedColor(red: 16, green: 16, blue: 18)
    static let meterBackground = LevelResolvedColor(red: 22, green: 23, blue: 26)
    static let meterScaleLine = LevelResolvedColor(red: 47, green: 50, blue: 56)
    static let scaleAccent = LevelResolvedColor(red: 67, green: 120, blue: 184)
    static let textTertiary = LevelResolvedColor(red: 135, green: 146, blue: 160)
    static let inTarget = LevelResolvedColor(red: 67, green: 185, blue: 115)
    static let outTarget = LevelResolvedColor(red: 202, green: 82, blue: 86)
    static let clip = LevelResolvedColor(red: 54, green: 23, blue: 24, opacity: 0.92)
    static let resetGeneral = LevelResolvedColor(red: 170, green: 130, blue: 219)

    // Figma exposes the semantic token name via MCP search, but none of the anchored
    // Level nodes bind it directly. This fallback keeps the mass neutral until the
    // token value becomes addressable through a bound node.
    static let meterFillBody = LevelResolvedColor(red: 61, green: 65, blue: 72, opacity: 0.88)

    static let radiusCanvas: CGFloat = 12
    static let panelPadding: CGFloat = 16
    static let labelWidth: CGFloat = 32
    static let labelGap: CGFloat = 24
    static let windowGap: CGFloat = 8
    static let scaleLineWidth: CGFloat = 1
    static let borderWidth: CGFloat = 2
    static let resetMarkSize = CGSize(width: 8, height: 32)
    static let targetMarginDB: CGFloat = 6
    static let targetHysteresisDB: CGFloat = 1.5
    static let targetCrossfadeDuration: TimeInterval = 0.2
    static let expandedColumnCount = 240
    static let fourWindowColumnCount = 56
    static let singleExpandedHeight: CGFloat = 518.5
    static let fourWindowHeight: CGFloat = 337
}

#Preview {
    LevelRendererShowcase()
}
