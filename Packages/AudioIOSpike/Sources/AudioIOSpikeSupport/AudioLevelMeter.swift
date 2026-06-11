import AVFoundation
import Accelerate
import Foundation

public enum AudioLevelMeterError: Error {
    case missingFloatChannelData
    case insufficientChannelCount(expected: Int, actual: Int)
}

private struct ChannelMeasurement {
    var rms: Float
    var peak: Float
    var clipped: Bool
}

public enum AudioLevelMeter {
    public static func measure(
        buffer: AVAudioPCMBuffer,
        measuredChannelCount: Int = audioIOSpikeMeasuredChannelCount,
        hostTime: UInt64 = 0,
        sampleTime: Int64 = 0
    ) throws -> DynamicsSample {
        guard let channelData = buffer.floatChannelData else {
            throw AudioLevelMeterError.missingFloatChannelData
        }

        let actualChannelCount = Int(buffer.format.channelCount)
        guard actualChannelCount >= measuredChannelCount else {
            throw AudioLevelMeterError.insufficientChannelCount(
                expected: measuredChannelCount,
                actual: actualChannelCount
            )
        }

        return measure(
            floatChannelData: channelData,
            frameCount: Int(buffer.frameLength),
            sampleRate: buffer.format.sampleRate,
            hostTime: hostTime,
            sampleTime: sampleTime
        )
    }

    public static func measure(
        floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        sampleRate: Double,
        hostTime: UInt64 = 0,
        sampleTime: Int64 = 0
    ) -> DynamicsSample {
        DynamicsSample(
            hostTime: hostTime,
            sampleTime: sampleTime,
            frameCount: UInt32(frameCount),
            sampleRate: sampleRate,
            lane1: measureLane(floatChannelData, baseChannelIndex: 0, frameCount: frameCount),
            lane2: measureLane(floatChannelData, baseChannelIndex: 2, frameCount: frameCount),
            lane3: measureLane(floatChannelData, baseChannelIndex: 4, frameCount: frameCount),
            lane4: measureLane(floatChannelData, baseChannelIndex: 6, frameCount: frameCount)
        )
    }

    private static func measureLane(
        _ channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        baseChannelIndex: Int,
        frameCount: Int
    ) -> LaneDynamicsSample {
        let left = measureChannel(channelData[baseChannelIndex], frameCount: frameCount)
        let right = measureChannel(channelData[baseChannelIndex + 1], frameCount: frameCount)

        return LaneDynamicsSample(
            rmsLeft: left.rms,
            rmsRight: right.rms,
            peakLeft: left.peak,
            peakRight: right.peak,
            clipLeft: left.clipped,
            clipRight: right.clipped
        )
    }

    private static func measureChannel(
        _ samples: UnsafePointer<Float>,
        frameCount: Int
    ) -> ChannelMeasurement {
        guard frameCount > 0 else {
            return ChannelMeasurement(rms: 0, peak: 0, clipped: false)
        }

        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameCount))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(frameCount))

        return ChannelMeasurement(
            rms: rms,
            peak: peak,
            clipped: peak > audioIOSpikeClipThreshold
        )
    }
}
