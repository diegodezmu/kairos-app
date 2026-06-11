import AppKit
import Foundation
import QuartzCore
import SwiftUI

enum RenderPerfSpike {
    static let launchArgument = "--render-perf-spike"
    static let canvasSize = CGSize(width: 1728, height: 540)
    static let cycles = 4
    static let stepsPerCycle = 128
    static let warmupFrames = 120
    static let measuredFrames = 600
    static let targetFrameBudgetMs = 1000.0 / 60.0

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

struct RenderPerfSpikeView: View {
    @StateObject private var benchmark = RenderPerfSpikeBenchmark()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: false) { context, size in
                benchmark.recordFrame(
                    timestamp: timeline.date.timeIntervalSinceReferenceDate,
                    size: size
                ) { frameIndex in
                    RenderPerfSpikeRenderer.draw(
                        in: &context,
                        size: size,
                        frameIndex: frameIndex
                    )
                }
            }
        }
        .frame(
            width: RenderPerfSpike.canvasSize.width,
            height: RenderPerfSpike.canvasSize.height
        )
        .background(Color.black)
    }
}

@MainActor
private final class RenderPerfSpikeBenchmark: ObservableObject {
    private var frameIndex = 0
    private var isFinished = false
    private var measurementStartedAt: TimeInterval?
    private var lastFrameTimestamp: TimeInterval?
    private var measuredDrawDurationsMs: [Double] = []
    private var measuredFrameIntervalsMs: [Double] = []

    func recordFrame(
        timestamp: TimeInterval,
        size: CGSize,
        draw: (Int) -> Void
    ) {
        guard !isFinished else {
            return
        }

        let currentFrame = frameIndex
        frameIndex += 1

        let drawStartedAt = CACurrentMediaTime()
        draw(currentFrame)
        let drawEndedAt = CACurrentMediaTime()

        if let lastFrameTimestamp {
            let intervalMs = (timestamp - lastFrameTimestamp) * 1_000.0
            if currentFrame >= RenderPerfSpike.warmupFrames {
                measuredFrameIntervalsMs.append(intervalMs)
            }
        }

        lastFrameTimestamp = timestamp

        if currentFrame >= RenderPerfSpike.warmupFrames {
            if measurementStartedAt == nil {
                measurementStartedAt = timestamp
            }
            let drawDurationMs = (drawEndedAt - drawStartedAt) * 1_000.0
            measuredDrawDurationsMs.append(drawDurationMs)
        }

        if measuredDrawDurationsMs.count >= RenderPerfSpike.measuredFrames {
            finish(size: size)
        }
    }

    private func finish(size: CGSize) {
        guard !isFinished else {
            return
        }

        isFinished = true

        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let elapsedSeconds = max(
            (lastFrameTimestamp ?? 0.0) - (measurementStartedAt ?? 0.0),
            0.0001
        )
        let averageFPS = Double(measuredDrawDurationsMs.count) / elapsedSeconds
        let frameIntervalBudgetMs = RenderPerfSpike.targetFrameBudgetMs
        let stableFrameCount = measuredFrameIntervalsMs.filter { $0 <= frameIntervalBudgetMs }.count
        let stableFrameRatio = Double(stableFrameCount) / Double(max(measuredFrameIntervalsMs.count, 1))
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())

        print("RENDER_PERF_SPIKE_RESULT_BEGIN")
        print("renderer=Canvas")
        print("window_points=\(Int(size.width.rounded()))x\(Int(size.height.rounded()))")
        print("backing_scale=\(Self.format(scale))")
        print("window_pixels=\(pixelWidth)x\(pixelHeight)")
        print("cycles=\(RenderPerfSpike.cycles)")
        print("steps_per_cycle=\(RenderPerfSpike.stepsPerCycle)")
        print("mode=line")
        print("warmup_frames=\(RenderPerfSpike.warmupFrames)")
        print("measured_frames=\(RenderPerfSpike.measuredFrames)")
        print("elapsed_seconds=\(Self.format(elapsedSeconds))")
        print("fps_avg=\(Self.format(averageFPS))")
        print("frame_interval_avg_ms=\(Self.format(Self.average(measuredFrameIntervalsMs)))")
        print("frame_interval_p95_ms=\(Self.format(Self.percentile(measuredFrameIntervalsMs, 0.95)))")
        print("frame_interval_max_ms=\(Self.format(measuredFrameIntervalsMs.max() ?? 0.0))")
        print("draw_cpu_avg_ms=\(Self.format(Self.average(measuredDrawDurationsMs)))")
        print("draw_cpu_p95_ms=\(Self.format(Self.percentile(measuredDrawDurationsMs, 0.95)))")
        print("draw_cpu_max_ms=\(Self.format(measuredDrawDurationsMs.max() ?? 0.0))")
        print("stable_60fps_ratio_percent=\(Self.format(stableFrameRatio * 100.0))")
        print("target_60fps_met=\(averageFPS >= 59.0 && Self.percentile(measuredFrameIntervalsMs, 0.95) <= frameIntervalBudgetMs ? "yes" : "no")")
        print("RENDER_PERF_SPIKE_RESULT_END")

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0.0
        }
        return values.reduce(0.0, +) / Double(values.count)
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else {
            return 0.0
        }

        let sorted = values.sorted()
        let clampedPercentile = min(max(percentile, 0.0), 1.0)
        let index = Int((Double(sorted.count - 1) * clampedPercentile).rounded())
        return sorted[index]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private enum RenderPerfSpikeRenderer {
    private static let backgroundColor = Color(red: 0.04, green: 0.05, blue: 0.06)
    private static let rowFillColor = Color(red: 0.08, green: 0.09, blue: 0.10)
    private static let guideColor = Color.white.opacity(0.08)
    private static let inactiveColor = Color.white.opacity(0.16)
    private static let activeColor = Color(red: 0.94, green: 0.97, blue: 1.00)
    private static let anticipationColor = Color(red: 0.97, green: 0.31, blue: 0.36)
    private static let generalResetColor = Color(red: 0.64, green: 0.42, blue: 0.94)

    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        frameIndex: Int
    ) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(backgroundColor)
        )

        let contentInsetX: CGFloat = 24.0
        let contentInsetY: CGFloat = 20.0
        let rowSpacing: CGFloat = 18.0
        let cycles = RenderPerfSpike.cycles
        let steps = RenderPerfSpike.stepsPerCycle
        let availableWidth = size.width - (contentInsetX * 2.0)
        let availableHeight = size.height - (contentInsetY * 2.0) - (rowSpacing * CGFloat(cycles - 1))
        let rowHeight = availableHeight / CGFloat(cycles)
        let stepWidth = availableWidth / CGFloat(steps)
        let lineWidth = max(1.0, min(4.0, stepWidth * 0.34))
        let currentStep = frameIndex % steps
        let anticipationStart = max(steps - 8, 0)
        let isGeneralResetFrame = currentStep == 0

        for cycleIndex in 0..<cycles {
            let originY = contentInsetY + (CGFloat(cycleIndex) * (rowHeight + rowSpacing))
            let rowRect = CGRect(
                x: contentInsetX,
                y: originY,
                width: availableWidth,
                height: rowHeight
            )

            context.fill(
                Path(roundedRect: rowRect, cornerRadius: 10.0),
                with: .color(rowFillColor)
            )

            let guideRect = CGRect(
                x: contentInsetX,
                y: originY + rowHeight - 1.0,
                width: availableWidth,
                height: 1.0
            )
            context.fill(Path(guideRect), with: .color(guideColor))

            for stepIndex in 0..<steps {
                let originX = contentInsetX + (CGFloat(stepIndex) * stepWidth)
                let stepRect = CGRect(
                    x: originX,
                    y: originY + 6.0,
                    width: lineWidth,
                    height: rowHeight - 12.0
                )
                let stepColor = colorForStep(
                    stepIndex: stepIndex,
                    currentStep: currentStep,
                    anticipationStart: anticipationStart,
                    isGeneralResetFrame: isGeneralResetFrame
                )
                context.fill(Path(stepRect), with: .color(stepColor))
            }
        }
    }

    private static func colorForStep(
        stepIndex: Int,
        currentStep: Int,
        anticipationStart: Int,
        isGeneralResetFrame: Bool
    ) -> Color {
        if isGeneralResetFrame, stepIndex == 0 {
            return generalResetColor
        }

        if stepIndex == currentStep {
            return activeColor
        }

        if stepIndex >= anticipationStart {
            return anticipationColor
        }

        return inactiveColor
    }
}
