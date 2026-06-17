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
            let startHostTime: UInt64
            let endHostTime: UInt64
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
        let name: String
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
}

struct LevelRenderer: View {
    let frame: LevelRenderFrame

    var body: some View {
        Group {
            switch frame.layout {
            case .singleExpanded:
                if let lane = frame.lanes.first {
                    LevelWindowCanvas(lane: lane)
                }
            case .fourWindows:
                HStack(spacing: LevelDesignTokens.windowGap) {
                    ForEach(frame.lanes) { lane in
                        LevelWindowCanvas(lane: lane)
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

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                    context.withCGContext { cgContext in
                        LevelCanvasRenderer.draw(
                            lane: lane,
                            in: cgContext,
                            size: size
                        )
                    }
                }

                Text(lane.name)
                    .font(Font.custom("Inter", size: 14).weight(.medium))
                    .foregroundStyle(LevelDesignTokens.textSecondary.color)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, LevelDesignTokens.titleTopPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                LevelScaleLabelsOverlay(size: geometry.size)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: LevelDesignTokens.radiusCanvas,
                style: .continuous
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(lane.name) level meter"))
    }
}

private struct LevelScaleLabelsOverlay: View {
    let size: CGSize

    var body: some View {
        let canvasRect = CGRect(origin: .zero, size: size)
        let contentRect = LevelCanvasLayout.contentRect(in: canvasRect)
        let meterRect = CGRect(
            x: contentRect.minX + LevelDesignTokens.labelWidth + LevelDesignTokens.labelGap,
            y: contentRect.minY,
            width: max(0, contentRect.width - (LevelDesignTokens.labelWidth + LevelDesignTokens.labelGap)),
            height: max(0, contentRect.height)
        )

        if meterRect.width > 0, meterRect.height > 0 {
            ZStack(alignment: .topLeading) {
                ForEach(LevelScaleGuide.bands, id: \.label) { band in
                    Text(band.label)
                        .font(Font.custom("Inter", size: 14).weight(.medium))
                        .foregroundStyle(labelColor(for: band.db))
                        .frame(
                            width: LevelDesignTokens.labelWidth,
                            alignment: .trailing
                        )
                        .position(
                            x: contentRect.minX + (LevelDesignTokens.labelWidth / 2),
                            y: LevelScaleGuide.yPosition(for: band.db, in: meterRect)
                        )
                }
            }
        }
    }

    private func labelColor(for db: CGFloat) -> Color {
        // All scale labels share the same tertiary grey — the target reference is
        // expressed by the dashed line, not by tinting the -12 label.
        LevelDesignTokens.textTertiary.color
    }
}

private enum LevelScaleGuide {
    static let bands: [(db: CGFloat, label: String)] = [
        (0, "0"),
        (-6, "- 6"),
        (-12, "- 12"),
        (-18, "- 18"),
        (-24, "- 24"),
        (-30, "- 30"),
        (-60, "- 60"),
    ]

    static func yPosition(
        for db: CGFloat,
        in rect: CGRect
    ) -> CGFloat {
        let clamped = min(max(db, LevelDecibelScale.floorDB), LevelDecibelScale.ceilingDB)
        let progress = (LevelDecibelScale.ceilingDB - clamped) / LevelDecibelScale.visibleRange
        return rect.minY + (progress * rect.height)
    }
}

private enum LevelCanvasLayout {
    static func contentRect(in canvasRect: CGRect) -> CGRect {
        let horizontalInset = min(LevelDesignTokens.panelPadding, canvasRect.width / 4)
        let bottomInset = min(LevelDesignTokens.panelPadding, canvasRect.height / 4)
        let topInset = min(LevelDesignTokens.titleStackHeight, canvasRect.height / 3)

        return CGRect(
            x: canvasRect.minX + horizontalInset,
            y: canvasRect.minY + topInset,
            width: max(0, canvasRect.width - (horizontalInset * 2)),
            height: max(0, canvasRect.height - topInset - bottomInset)
        )
    }
}

private enum LevelCanvasRenderer {
    static func draw(
        lane: LevelRenderFrame.Lane,
        in context: CGContext,
        size: CGSize
    ) {
        let canvasRect = CGRect(origin: .zero, size: size)
        let backgroundPath = CGPath(
            roundedRect: canvasRect,
            cornerWidth: LevelDesignTokens.radiusCanvas,
            cornerHeight: LevelDesignTokens.radiusCanvas,
            transform: nil
        )
        context.setFillColor(LevelDesignTokens.backgroundSurface.cgColor)
        context.addPath(backgroundPath)
        context.fillPath()

        let contentRect = LevelCanvasLayout.contentRect(in: canvasRect)
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

        context.setFillColor(LevelDesignTokens.meterBackground.cgColor)
        context.fill(meterRect)

        drawChannel(
            lane.left,
            latestHostTime: lane.latestHostTime,
            historyRange: lane.historyRange,
            in: context,
            meterRect: meterRect
        )
        drawChannel(
            lane.right,
            latestHostTime: lane.latestHostTime,
            historyRange: lane.historyRange,
            in: context,
            meterRect: meterRect
        )
        drawScale(in: context, meterRect: meterRect)
        drawTargetLine(
            targetDB: lane.targetDB,
            in: context,
            meterRect: meterRect
        )
        drawBorders(
            for: lane.left,
            latestHostTime: lane.latestHostTime,
            historyRange: lane.historyRange,
            in: context,
            meterRect: meterRect
        )
        drawBorders(
            for: lane.right,
            latestHostTime: lane.latestHostTime,
            historyRange: lane.historyRange,
            in: context,
            meterRect: meterRect
        )
    }

    private static func drawChannel(
        _ channel: LevelRenderFrame.Lane.Channel,
        latestHostTime: UInt64,
        historyRange: HistoryRange,
        in context: CGContext,
        meterRect: CGRect
    ) {
        let meanPoints = LevelMassGeometry.contourPoints(
            for: channel.columns,
            currentDB: channel.currentDB,
            latestHostTime: latestHostTime,
            historyRange: historyRange,
            in: meterRect,
            value: \.meanDB
        )

        for fillRect in LevelMassGeometry.fillRects(
            contourPoints: meanPoints,
            meterRect: meterRect
        ) {
            context.setFillColor(channel.fillColor.cgColor)
            context.fill(fillRect)
        }
        // The min/max range envelope (a light translucent band) is not part of the
        // Figma design — it reads as a grey shadow/projection artifact, so it is
        // intentionally not drawn. Only the solid mass + mean border remain.
    }

    private static func drawBorders(
        for channel: LevelRenderFrame.Lane.Channel,
        latestHostTime: UInt64,
        historyRange: HistoryRange,
        in context: CGContext,
        meterRect: CGRect
    ) {
        let borderPoints = LevelMassGeometry.contourPoints(
            for: channel.columns,
            currentDB: channel.currentDB,
            latestHostTime: latestHostTime,
            historyRange: historyRange,
            in: meterRect,
            value: \.meanDB
        )

        guard let firstPoint = borderPoints.first else {
            return
        }

        // `addLines(between:)` starts its own subpath at the array's first element,
        // so passing the full array (not dropFirst) is required — otherwise the
        // first segment from the meter's left edge is never stroked, leaving the
        // start of the history without a coloured border.
        _ = firstPoint
        let borderPath = CGMutablePath()
        borderPath.addLines(between: borderPoints)

        context.setStrokeColor(channel.borderColor.cgColor)
        context.setLineWidth(LevelDesignTokens.borderWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(borderPath)
        context.strokePath()
    }

    private static func drawScale(
        in context: CGContext,
        meterRect: CGRect
    ) {
        for band in LevelScaleGuide.bands {
            let rawY = LevelScaleGuide.yPosition(for: band.db, in: meterRect)
            let y = floor(rawY) + 0.5
            let path = CGMutablePath()
            path.move(to: CGPoint(x: meterRect.minX, y: y))
            path.addLine(to: CGPoint(x: meterRect.maxX, y: y))

            // All scale bands are the subtle guide colour. The accent now belongs
            // exclusively to the target reference line (drawTargetLine), which is
            // bound to the lane's target level and may sit at any dB.
            context.setStrokeColor(LevelDesignTokens.meterScaleLine.cgColor)
            context.setLineWidth(LevelDesignTokens.scaleLineWidth)
            context.addPath(path)
            context.strokePath()
        }
    }

    /// Dashed reference line at the lane's target level. Bound to the sidebar
    /// `Target level` control, so it tracks changes in real time.
    private static func drawTargetLine(
        targetDB: CGFloat,
        in context: CGContext,
        meterRect: CGRect
    ) {
        let rawY = LevelScaleGuide.yPosition(for: targetDB, in: meterRect)
        let y = floor(rawY) + 0.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: meterRect.minX, y: y))
        path.addLine(to: CGPoint(x: meterRect.maxX, y: y))

        context.saveGState()
        context.setStrokeColor(LevelDesignTokens.scaleAccent.cgColor)
        context.setLineWidth(LevelDesignTokens.scaleLineWidth * 2)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

}

enum LevelMassGeometry {
    static func contourPoints(
        for columns: [LevelRenderFrame.Lane.Column],
        currentDB: CGFloat,
        latestHostTime: UInt64,
        historyRange: HistoryRange,
        in meterRect: CGRect,
        value: KeyPath<LevelRenderFrame.Lane.Column, CGFloat>
    ) -> [CGPoint] {
        let currentPoint = CGPoint(
            x: meterRect.maxX,
            y: yPosition(for: currentDB, in: meterRect)
        )

        guard !columns.isEmpty else {
            return [
                CGPoint(x: meterRect.minX, y: currentPoint.y),
                currentPoint,
            ]
        }

        let visibleRangeMilliseconds = UInt64(historyRange.rawValue * 1_000.0)
        let historyPoints = columns
            .sorted { $0.endHostTime < $1.endHostTime }
            .map { column in
                CGPoint(
                    x: xPosition(
                        for: column.endHostTime,
                        latestHostTime: latestHostTime,
                        visibleRangeMilliseconds: visibleRangeMilliseconds,
                        in: meterRect
                    ),
                    y: yPosition(for: column[keyPath: value], in: meterRect)
                )
            }
            .reduce(into: [CGPoint]()) { points, point in
                if let last = points.last, abs(last.x - point.x) < 0.5 {
                    points[points.count - 1] = point
                } else {
                    points.append(point)
                }
            }

        guard let firstHistoryPoint = historyPoints.first else {
            return [
                CGPoint(x: meterRect.minX, y: currentPoint.y),
                currentPoint,
            ]
        }

        var points = [CGPoint(x: meterRect.minX, y: firstHistoryPoint.y)]
        if firstHistoryPoint.x > meterRect.minX {
            points.append(firstHistoryPoint)
        }

        points.append(contentsOf: historyPoints.dropFirst())

        if let lastHistoryPoint = historyPoints.last, lastHistoryPoint.x < meterRect.maxX {
            points.append(
                CGPoint(
                x: meterRect.maxX,
                y: lastHistoryPoint.y
                )
            )
        }

        if let last = points.last, abs(last.x - currentPoint.x) < 0.5 {
            // The right edge must always represent the live RMS point. Replacing
            // the last history sample avoids a vertical border spike at maxX and
            // keeps the visible edge locked to the current reading instead of the
            // latest history bucket mean.
            points[points.count - 1] = currentPoint
        } else if !isEquivalent(points.last, currentPoint) {
            points.append(currentPoint)
        }

        return points
    }

    static func fillRects(
        contourPoints: [CGPoint],
        meterRect: CGRect
    ) -> [CGRect] {
        guard contourPoints.count >= 2 else {
            return []
        }

        return zip(contourPoints, contourPoints.dropFirst()).flatMap { startPoint, endPoint in
            guard endPoint.x > startPoint.x else {
                return [CGRect]()
            }

            let segmentWidth = endPoint.x - startPoint.x
            let sliceCount = max(Int(ceil(segmentWidth)), 1)
            let sliceWidth = segmentWidth / CGFloat(sliceCount)

            return (0..<sliceCount).compactMap { index in
                let sliceMinX = startPoint.x + (CGFloat(index) * sliceWidth)
                let sliceMaxX = min(endPoint.x, sliceMinX + sliceWidth)
                let expandedMinX = max(startPoint.x, sliceMinX - 0.5)
                let expandedMaxX = min(endPoint.x, sliceMaxX + 0.5)
                let startProgress = (sliceMinX - startPoint.x) / segmentWidth
                let endProgress = (sliceMaxX - startPoint.x) / segmentWidth
                let startY = startPoint.y + ((endPoint.y - startPoint.y) * startProgress)
                let endY = startPoint.y + ((endPoint.y - startPoint.y) * endProgress)
                let topY = min(startY, endY)
                let height = meterRect.maxY - topY

                guard expandedMaxX > expandedMinX, height > 0 else {
                    return nil
                }

                return CGRect(
                    x: expandedMinX,
                    y: topY,
                    width: expandedMaxX - expandedMinX,
                    height: height
                )
            }
        }
    }

    static func fillSegments(
        contourPoints: [CGPoint],
        meterRect: CGRect
    ) -> [[CGPoint]] {
        guard contourPoints.count >= 2 else {
            return []
        }

        return zip(contourPoints, contourPoints.dropFirst()).map { startPoint, endPoint in
            [
                CGPoint(x: startPoint.x, y: meterRect.maxY),
                startPoint,
                endPoint,
                CGPoint(x: endPoint.x, y: meterRect.maxY),
            ]
        }
    }

    private static func yPosition(
        for db: CGFloat,
        in rect: CGRect
    ) -> CGFloat {
        let clamped = min(max(db, LevelDecibelScale.floorDB), LevelDecibelScale.ceilingDB)
        let progress = (LevelDecibelScale.ceilingDB - clamped) / LevelDecibelScale.visibleRange
        return rect.minY + (progress * rect.height)
    }

    private static func xPosition(
        for hostTime: UInt64,
        latestHostTime: UInt64,
        visibleRangeMilliseconds: UInt64,
        in rect: CGRect
    ) -> CGFloat {
        guard visibleRangeMilliseconds > 0 else {
            return rect.maxX
        }

        let clampedHostTime = min(hostTime, latestHostTime)
        let age = latestHostTime - clampedHostTime
        let progress = min(1, CGFloat(age) / CGFloat(visibleRangeMilliseconds))
        return rect.maxX - (progress * rect.width)
    }

    private static func isEquivalent(
        _ lhs: CGPoint?,
        _ rhs: CGPoint
    ) -> Bool {
        guard let lhs else {
            return false
        }

        return abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    }
}

final class LevelPresentationPipeline {
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
        timestamp: TimeInterval
    ) -> LevelRenderFrame {
        let lanes = inputs.map { input in
            LevelRenderFrame.Lane(
                lane: input.lane,
                name: input.name,
                targetDB: input.targetDB,
                historyRange: input.history.range,
                latestHostTime: input.latestHostTime,
                left: resolveChannel(
                    currentSample: input.currentSample,
                    history: input.history,
                    lane: input.lane,
                    side: .left,
                    targetDB: input.targetDB,
                    targetMarginDB: input.targetMarginDB,
                    timestamp: timestamp
                ),
                right: resolveChannel(
                    currentSample: input.currentSample,
                    history: input.history,
                    lane: input.lane,
                    side: .right,
                    targetDB: input.targetDB,
                    targetMarginDB: input.targetMarginDB,
                    timestamp: timestamp
                )
            )
        }

        return LevelRenderFrame(
            layout: layout,
            lanes: lanes
        )
    }

    private func resolveChannel(
        currentSample: LaneDynamicsSample,
        history: LaneHistorySnapshot,
        lane: LaneID,
        side: LevelChannelSide,
        targetDB: CGFloat,
        targetMarginDB: CGFloat,
        timestamp: TimeInterval
    ) -> LevelRenderFrame.Lane.Channel {
        let currentAmplitude = side == .left ? currentSample.rmsLeft : currentSample.rmsRight
        let currentDB = LevelDecibelScale.displayDBFS(for: currentAmplitude)

        let key = ChannelKey(lane: lane, side: side)
        let semanticState = semanticState(
            currentDB: currentDB,
            targetDB: targetDB,
            targetMarginDB: targetMarginDB,
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
                    startHostTime: bucket.startHostTime,
                    endHostTime: bucket.endHostTime,
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
        targetMarginDB: CGFloat,
        previous: SemanticState?
    ) -> SemanticState {
        let distance = abs(currentDB - targetDB)
        let hysteresis = min(LevelDesignTokens.targetHysteresisDB, targetMarginDB * 0.5)
        let reentryMargin = max(targetMarginDB - hysteresis, 0)
        let currentState = previous ?? (distance > targetMarginDB ? .outOfTarget : .inTarget)

        switch currentState {
        case .inTarget:
            return distance > targetMarginDB ? .outOfTarget : .inTarget
        case .outOfTarget:
            return distance < reentryMargin
                ? .inTarget
                : .outOfTarget
        }
    }

    private func isClipping(
        currentSample: LaneDynamicsSample,
        side: LevelChannelSide
    ) -> Bool {
        let detectorClip = side == .left ? currentSample.clipLeft : currentSample.clipRight

        // Live's post-fader output meter clamps at 1.0 (0 dBFS), so a true
        // >0 dBFS overload can't be observed there. Treat a level pinned at the
        // ceiling as clipping — that is exactly what reads as "in the red" on the
        // Ableton track meter, and turns the mass into the level-clip colour.
        let amplitude = side == .left ? currentSample.peakLeft : currentSample.peakRight
        let atCeiling = LevelDecibelScale.displayDBFS(for: amplitude) >= LevelDecibelScale.ceilingDB - 0.1

        return detectorClip || atCeiling
    }
}

struct LevelLaneInput {
    let lane: LaneID
    let name: String
    let targetDB: CGFloat
    let targetMarginDB: CGFloat
    let currentSample: LaneDynamicsSample
    let history: LaneHistorySnapshot
    let latestHostTime: UInt64
}

enum LevelChannelSide {
    case left
    case right
}

private struct LevelLaneProfile {
    let lane: LaneID
    let baseDB: Double
    let slowSwingDB: Double
    let fastSwingDB: Double
    let stereoSpreadDB: Double
    let clipPeriodMilliseconds: UInt64?
    let clipChannel: LevelChannelSide?
}

private struct LevelLaneSettings {
    let lane: LaneID
    let targetDB: CGFloat
    let targetMarginDB: CGFloat
    let historyRange: HistoryRange
    let baseDB: Double
    let slowSwingDB: Double
    let fastSwingDB: Double
    let stereoSpreadDB: Double
    let clipPeriodMilliseconds: UInt64?
    let clipChannel: LevelChannelSide?
}

struct LevelPreviewSnapshot {
    let expandedFrame: LevelRenderFrame
    let splitFrame: LevelRenderFrame
    let statuses: [LaneID: LaneInputStatus]
}

final class LevelPreviewDriver {
    private var historyBuffer: any HistoryBuffer = DynamicsCoreFactory.makeHistoryBuffer()
    private var clipDetectors: [any ClipDetector] = LaneID.allCases.map { _ in
        DynamicsCoreFactory.makeClipDetector()
    }
    private var statusMachines = LevelPreviewDriver.makeStatusMachines()
    private let presentationPipeline = LevelPresentationPipeline()
    private let historyStepMilliseconds: UInt64 = 100
    private let seedDurationMilliseconds: UInt64 = UInt64(HistoryRange.twoMinutes.rawValue * 1_000.0)
    private let showcaseStartDate = Date()
    private let showcaseSplitConfigurations: [LevelLaneConfiguration] = [
        LevelLaneConfiguration(
            lane: .one,
            isEnabled: true,
            name: "Drums",
            targetLevelDB: -12,
            historyRange: .tenSeconds
        ),
        LevelLaneConfiguration(
            lane: .two,
            isEnabled: true,
            name: "FX",
            targetLevelDB: -18,
            historyRange: .thirtySeconds
        ),
        LevelLaneConfiguration(
            lane: .three,
            isEnabled: true,
            name: "Drums",
            targetLevelDB: -9,
            historyRange: .oneMinute
        ),
        LevelLaneConfiguration(
            lane: .four,
            isEnabled: true,
            name: "Drums",
            targetLevelDB: -24,
            historyRange: .twoMinutes
        ),
    ]
    private let showcaseExpandedConfiguration = LevelLaneConfiguration(
        lane: .one,
        isEnabled: true,
        name: "Drums",
        targetLevelDB: -12,
        historyRange: .thirtySeconds
    )

    private var historyCursorMilliseconds: UInt64 = 0

    init() {
        reset()
    }

    func reset() {
        historyBuffer = DynamicsCoreFactory.makeHistoryBuffer()
        clipDetectors = LaneID.allCases.map { _ in
            DynamicsCoreFactory.makeClipDetector()
        }
        statusMachines = Self.makeStatusMachines()
        historyCursorMilliseconds = 0
        seedHistory()
    }

    func snapshot(
        at elapsedMilliseconds: UInt64,
        timestamp: TimeInterval,
        laneConfigurations: [LevelLaneConfiguration]
    ) -> LevelPreviewSnapshot {
        let enabledConfigurations = laneConfigurations
            .filter(\.isEnabled)
            .sorted { $0.lane.rawValue < $1.lane.rawValue }
        let preparedSample = prepareSample(at: elapsedMilliseconds)
        let frames = makeFrames(
            sample: preparedSample,
            splitConfigurations: enabledConfigurations,
            expandedConfiguration: enabledConfigurations.first,
            timestamp: timestamp
        )

        return LevelPreviewSnapshot(
            expandedFrame: frames.expanded,
            splitFrame: frames.split,
            statuses: makeStatuses(
                from: preparedSample,
                laneConfigurations: laneConfigurations,
                elapsedMilliseconds: elapsedMilliseconds
            )
        )
    }

    func showcaseFrames(at date: Date) -> (expanded: LevelRenderFrame, split: LevelRenderFrame) {
        let elapsedMilliseconds = UInt64(
            max(0, (date.timeIntervalSince(showcaseStartDate) * 1_000.0).rounded())
        )
        let preparedSample = prepareSample(at: elapsedMilliseconds)
        let frames = makeFrames(
            sample: preparedSample,
            splitConfigurations: showcaseSplitConfigurations,
            expandedConfiguration: showcaseExpandedConfiguration,
            timestamp: date.timeIntervalSinceReferenceDate
        )
        return (frames.expanded, frames.split)
    }

    private func seedHistory() {
        appendHistorySample(at: 0)
        while historyCursorMilliseconds + historyStepMilliseconds <= seedDurationMilliseconds {
            historyCursorMilliseconds += historyStepMilliseconds
            appendHistorySample(at: historyCursorMilliseconds)
        }
    }

    private func advanceHistory(to targetMilliseconds: UInt64) {
        while historyCursorMilliseconds + historyStepMilliseconds <= targetMilliseconds {
            historyCursorMilliseconds += historyStepMilliseconds
            appendHistorySample(at: historyCursorMilliseconds)
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

    private func prepareSample(at elapsedMilliseconds: UInt64) -> DynamicsSample {
        let playheadMilliseconds = seedDurationMilliseconds + elapsedMilliseconds

        if playheadMilliseconds < historyCursorMilliseconds {
            reset()
        }

        advanceHistory(to: playheadMilliseconds)
        return syntheticDisplaySample(at: playheadMilliseconds)
    }

    private func syntheticDisplaySample(at milliseconds: UInt64) -> DynamicsSample {
        makeDynamicsSample(
            at: milliseconds,
            includeClipState: true
        )
    }

    private func makeFrames(
        sample: DynamicsSample,
        splitConfigurations: [LevelLaneConfiguration],
        expandedConfiguration: LevelLaneConfiguration?,
        timestamp: TimeInterval
    ) -> (expanded: LevelRenderFrame, split: LevelRenderFrame) {
        let splitInputs = splitConfigurations.compactMap { configuration -> LevelLaneInput? in
            guard let settings = makeLaneSettings(for: configuration) else {
                return nil
            }

            return makeInput(
                for: settings,
                from: sample,
                columnCount: LevelDesignTokens.fourWindowColumnCount
            )
        }
        let expandedInputs: [LevelLaneInput]

        if
            let expandedConfiguration,
            let settings = makeLaneSettings(for: expandedConfiguration)
        {
            expandedInputs = [
                makeInput(
                    for: settings,
                    from: sample,
                    columnCount: LevelDesignTokens.expandedColumnCount
                ),
            ]
        } else {
            expandedInputs = []
        }

        return (
            expanded: presentationPipeline.makeFrame(
                layout: .singleExpanded,
                inputs: expandedInputs,
                timestamp: timestamp
            ),
            split: presentationPipeline.makeFrame(
                layout: .fourWindows,
                inputs: splitInputs,
                timestamp: timestamp
            )
        )
    }

    private func makeStatuses(
        from sample: DynamicsSample,
        laneConfigurations: [LevelLaneConfiguration],
        elapsedMilliseconds: UInt64
    ) -> [LaneID: LaneInputStatus] {
        let configurationsByLane = Dictionary(
            uniqueKeysWithValues: laneConfigurations.map { ($0.lane, $0) }
        )
        var statuses: [LaneID: LaneInputStatus] = [:]

        for lane in LaneID.allCases {
            let configuration = configurationsByLane[lane]
                ?? LevelLaneConfiguration(
                    lane: lane,
                    isEnabled: false,
                    name: "",
                    targetLevelDB: SettingsDefaults.defaultTargetLevelDB,
                    targetMarginDB: SettingsDefaults.defaultTargetMarginDB,
                    historyRange: SettingsDefaults.defaultHistoryRange
                )
            var machine = statusMachines[lane]
                ?? DynamicsCoreFactory.makeLaneInputStatusMachine(
                    lane: lane,
                    channelLabel: Self.channelLabel(for: lane),
                    laneEnabled: configuration.isEnabled
                )

            machine.setEnabled(configuration.isEnabled)
            statuses[lane] = machine.consume(
                laneSample(from: sample, lane: lane),
                atMilliseconds: seedDurationMilliseconds + elapsedMilliseconds
            )
            statusMachines[lane] = machine
        }

        return statuses
    }

    private func makeInput(
        for settings: LevelLaneSettings,
        from sample: DynamicsSample,
        columnCount: Int
    ) -> LevelLaneInput {
        LevelLaneInput(
            lane: settings.lane,
            name: Self.channelLabel(for: settings.lane),
            targetDB: settings.targetDB,
            targetMarginDB: settings.targetMarginDB,
            currentSample: laneSample(from: sample, lane: settings.lane),
            history: historyBuffer.snapshot(
                for: settings.lane,
                range: settings.historyRange,
                columnCount: columnCount
            ),
            latestHostTime: sample.hostTime
        )
    }

    private func makeDynamicsSample(
        at milliseconds: UInt64,
        includeClipState: Bool
    ) -> DynamicsSample {
        let samplesByLane = Dictionary(
            uniqueKeysWithValues: Self.laneProfiles.map { profile in
                (
                    profile.lane,
                    makeLaneSample(
                        profile: profile,
                        at: milliseconds,
                        includeClipState: includeClipState
                    )
                )
            }
        )

        return DynamicsSample(
            hostTime: milliseconds,
            sampleTime: Int64(milliseconds),
            frameCount: 1,
            sampleRate: 1_000,
            lane1: samplesByLane[.one] ?? Self.emptyLaneSample,
            lane2: samplesByLane[.two] ?? Self.emptyLaneSample,
            lane3: samplesByLane[.three] ?? Self.emptyLaneSample,
            lane4: samplesByLane[.four] ?? Self.emptyLaneSample
        )
    }

    private func makeLaneSample(
        profile: LevelLaneProfile,
        at milliseconds: UInt64,
        includeClipState: Bool
    ) -> LaneDynamicsSample {
        let time = Double(milliseconds) / 1_000.0
        let lanePhase = Double(profile.lane.rawValue) * 0.73

        let bodyDB =
            profile.baseDB +
            (profile.slowSwingDB * sin((time * 0.38) + lanePhase)) +
            (profile.fastSwingDB * sin((time * 1.14) + (lanePhase * 0.61)))

        let leftDB = max(
            LevelDecibelScale.floorDB,
            min(
                -0.5,
                bodyDB + (profile.stereoSpreadDB * sin((time * 0.87) + lanePhase))
            )
        )
        let rightDB = max(
            LevelDecibelScale.floorDB,
            min(
                -0.5,
                bodyDB - (profile.stereoSpreadDB * cos((time * 0.93) + (lanePhase * 0.77)))
            )
        )

        let rmsLeft = LevelDecibelScale.amplitude(for: CGFloat(leftDB))
        let rmsRight = LevelDecibelScale.amplitude(for: CGFloat(rightDB))

        var peakLeft = min(0.98, max(rmsLeft * 1.45, rmsLeft))
        var peakRight = min(0.98, max(rmsRight * 1.45, rmsRight))

        if
            let clipPeriodMilliseconds = profile.clipPeriodMilliseconds,
            let clipChannel = profile.clipChannel
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
            let detector = clipDetectors[profile.lane.rawValue - 1]
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

    private func makeLaneSettings(
        for configuration: LevelLaneConfiguration
    ) -> LevelLaneSettings? {
        guard let profile = Self.laneProfiles.first(where: { $0.lane == configuration.lane }) else {
            return nil
        }

        return LevelLaneSettings(
            lane: configuration.lane,
            targetDB: CGFloat(configuration.targetLevelDB),
            targetMarginDB: CGFloat(configuration.targetMarginDB),
            historyRange: configuration.historyRange,
            baseDB: profile.baseDB,
            slowSwingDB: profile.slowSwingDB,
            fastSwingDB: profile.fastSwingDB,
            stereoSpreadDB: profile.stereoSpreadDB,
            clipPeriodMilliseconds: profile.clipPeriodMilliseconds,
            clipChannel: profile.clipChannel
        )
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

    private static func makeStatusMachines() -> [LaneID: LaneInputStatusMachine] {
        Dictionary(
            uniqueKeysWithValues: LaneID.allCases.map { lane in
                (
                    lane,
                    DynamicsCoreFactory.makeLaneInputStatusMachine(
                        lane: lane,
                        channelLabel: channelLabel(for: lane)
                    )
                )
            }
        )
    }

    private static func channelLabel(for lane: LaneID) -> String {
        switch lane {
        case .one:
            return "BlackHole 1-2"
        case .two:
            return "BlackHole 3-4"
        case .three:
            return "BlackHole 5-6"
        case .four:
            return "BlackHole 7-8"
        }
    }

    private static let laneProfiles: [LevelLaneProfile] = [
        LevelLaneProfile(
            lane: .one,
            baseDB: -11.5,
            slowSwingDB: 3.5,
            fastSwingDB: 1.5,
            stereoSpreadDB: 1.2,
            clipPeriodMilliseconds: 19_000,
            clipChannel: .left
        ),
        LevelLaneProfile(
            lane: .two,
            baseDB: -17.0,
            slowSwingDB: 5.0,
            fastSwingDB: 1.8,
            stereoSpreadDB: 1.6,
            clipPeriodMilliseconds: nil,
            clipChannel: nil
        ),
        LevelLaneProfile(
            lane: .three,
            baseDB: -13.0,
            slowSwingDB: 6.5,
            fastSwingDB: 2.4,
            stereoSpreadDB: 2.0,
            clipPeriodMilliseconds: 23_000,
            clipChannel: .right
        ),
        LevelLaneProfile(
            lane: .four,
            baseDB: -24.5,
            slowSwingDB: 7.5,
            fastSwingDB: 2.2,
            stereoSpreadDB: 2.5,
            clipPeriodMilliseconds: nil,
            clipChannel: nil
        ),
    ]

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
    @StateObject private var driver = ShowcaseDriver()

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
                        Text("One full-width lane using a 30 s history viewport and per-channel target feedback.")
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

private final class ShowcaseDriver: ObservableObject {
    private let previewDriver = LevelPreviewDriver()

    func frames(at date: Date) -> (expanded: LevelRenderFrame, split: LevelRenderFrame) {
        previewDriver.showcaseFrames(at: date)
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

    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [red, green, blue, opacity]
        )!
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
    static let textSecondary = LevelResolvedColor(red: 174, green: 184, blue: 196)
    static let textTertiary = LevelResolvedColor(red: 135, green: 146, blue: 160)
    static let inTarget = LevelResolvedColor(red: 67, green: 185, blue: 115)
    static let outTarget = LevelResolvedColor(red: 202, green: 82, blue: 86)
    // `color/kairos/level-clip` → `primitive/color/red/200` (#361718), solid.
    static let clip = LevelResolvedColor(red: 54, green: 23, blue: 24)

    // `color/kairos/meter-fill-body` → neutral-200 (#24262B), drawn solid.
    static let meterFillBody = LevelResolvedColor(red: 36, green: 38, blue: 43)

    static let radiusCanvas: CGFloat = 12
    static let panelPadding: CGFloat = 16
    static let titleTopPadding: CGFloat = 8
    static let titleHeight: CGFloat = 20
    static let titleGap: CGFloat = 8
    static let titleStackHeight: CGFloat = titleTopPadding + titleHeight + titleGap
    static let labelWidth: CGFloat = 32
    static let labelGap: CGFloat = 24
    static let windowGap: CGFloat = 8
    static let scaleLineWidth: CGFloat = 1
    static let borderWidth: CGFloat = 2
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
