import Foundation

enum DynamicsMeasurementError: Error, Equatable {
    case insufficientChannelCount(expected: Int, actual: Int)
    case mismatchedFrameCount(expected: Int, actual: Int, channelIndex: Int)
}

private struct ChannelMeasurement {
    var rootMeanSquare: Float
    var peakMagnitude: Float
}

final class DefaultDynamicsMeter: @unchecked Sendable {
    private let rmsPeakMeter: any RMSPeakMeasuring
    private let clipDetectors: [DefaultClipDetector]

    init(
        rmsPeakMeter: any RMSPeakMeasuring = DefaultRMSPeakMeter(),
        clipDetectors: [DefaultClipDetector] = (0..<kairosLaneCount).map { _ in DefaultClipDetector() }
    ) {
        precondition(clipDetectors.count == kairosLaneCount, "Expected one clip detector per lane.")
        self.rmsPeakMeter = rmsPeakMeter
        self.clipDetectors = clipDetectors
    }

    func measure(
        channels: [[Float]],
        sampleRate: Double,
        hostTime: UInt64 = 0,
        sampleTime: Int64 = 0
    ) throws -> DynamicsSample {
        let expectedChannelCount = kairosLaneCount * kairosChannelsPerLane
        guard channels.count >= expectedChannelCount else {
            throw DynamicsMeasurementError.insufficientChannelCount(
                expected: expectedChannelCount,
                actual: channels.count
            )
        }

        let measuredChannels = Array(channels.prefix(expectedChannelCount))
        let frameCount = measuredChannels.first?.count ?? 0
        for (index, channel) in measuredChannels.enumerated() where channel.count != frameCount {
            throw DynamicsMeasurementError.mismatchedFrameCount(
                expected: frameCount,
                actual: channel.count,
                channelIndex: index
            )
        }

        return withUnsafeChannelBuffers(measuredChannels) { channelBuffers in
            measure(
                channels: channelBuffers,
                sampleRate: sampleRate,
                hostTime: hostTime,
                sampleTime: sampleTime
            )
        }
    }

    func measure(
        channels: [UnsafeBufferPointer<Float>],
        sampleRate: Double,
        hostTime: UInt64 = 0,
        sampleTime: Int64 = 0
    ) -> DynamicsSample {
        let frameCount = channels.first?.count ?? 0

        return DynamicsSample(
            hostTime: hostTime,
            sampleTime: sampleTime,
            frameCount: UInt32(frameCount),
            sampleRate: sampleRate,
            lane1: measureLane(
                channels: channels,
                baseChannelIndex: 0,
                detector: clipDetectors[0],
                sampleRate: sampleRate,
                sampleTime: sampleTime
            ),
            lane2: measureLane(
                channels: channels,
                baseChannelIndex: 2,
                detector: clipDetectors[1],
                sampleRate: sampleRate,
                sampleTime: sampleTime
            ),
            lane3: measureLane(
                channels: channels,
                baseChannelIndex: 4,
                detector: clipDetectors[2],
                sampleRate: sampleRate,
                sampleTime: sampleTime
            ),
            lane4: measureLane(
                channels: channels,
                baseChannelIndex: 6,
                detector: clipDetectors[3],
                sampleRate: sampleRate,
                sampleTime: sampleTime
            )
        )
    }

    private func measureLane(
        channels: [UnsafeBufferPointer<Float>],
        baseChannelIndex: Int,
        detector: DefaultClipDetector,
        sampleRate: Double,
        sampleTime: Int64
    ) -> LaneDynamicsSample {
        let left = measureChannel(channels[baseChannelIndex])
        let right = measureChannel(channels[baseChannelIndex + 1])
        let clipState = detector.detectClipping(
            leftPeak: left.peakMagnitude,
            rightPeak: right.peakMagnitude,
            atMilliseconds: dynamicsTimelineMilliseconds(
                sampleTime: sampleTime,
                sampleRate: sampleRate
            )
        )

        return LaneDynamicsSample(
            rmsLeft: left.rootMeanSquare,
            rmsRight: right.rootMeanSquare,
            peakLeft: left.peakMagnitude,
            peakRight: right.peakMagnitude,
            clipLeft: clipState.left,
            clipRight: clipState.right
        )
    }

    private func measureChannel(_ channel: UnsafeBufferPointer<Float>) -> ChannelMeasurement {
        ChannelMeasurement(
            rootMeanSquare: rmsPeakMeter.rootMeanSquare(of: channel),
            peakMagnitude: rmsPeakMeter.peakMagnitude(of: channel)
        )
    }

    private func withUnsafeChannelBuffers<Result>(
        _ channels: [[Float]],
        index: Int = 0,
        accumulated: [UnsafeBufferPointer<Float>] = [],
        body: ([UnsafeBufferPointer<Float>]) throws -> Result
    ) rethrows -> Result {
        if index == channels.count {
            return try body(accumulated)
        }

        return try channels[index].withUnsafeBufferPointer { buffer in
            var next = accumulated
            next.append(buffer)
            return try withUnsafeChannelBuffers(
                channels,
                index: index + 1,
                accumulated: next,
                body: body
            )
        }
    }
}
