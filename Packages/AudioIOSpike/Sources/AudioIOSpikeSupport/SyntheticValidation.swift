import AVFoundation
import Foundation

public enum SyntheticValidationRunner {
    private static let targetRMSDBFSByChannel: [Float] = [
        -12.0, -7.0,
        -18.0, -9.0,
        -24.0, -4.5,
        -30.0, -15.0,
    ]

    private static let frequencyByChannel: [Double] = [
        211.0, 257.0,
        307.0, 353.0,
        401.0, 449.0,
        503.0, 557.0,
    ]

    public static func run(
        sampleRate: Double = 48_000,
        windowMs: Double = audioIOSpikeIntegrationWindowMs
    ) throws -> SyntheticValidationReport {
        let frameCount = Int((sampleRate * (windowMs / 1_000)).rounded())
        let referenceBuffer = try makeReferenceBuffer(
            sampleRate: sampleRate,
            frameCount: frameCount
        )
        let measured = try AudioLevelMeter.measure(buffer: referenceBuffer)

        let laneMeasurements = (0..<audioIOSpikeLaneCount).map { laneIndex in
            let baseChannel = laneIndex * audioIOSpikeChannelsPerLane
            let lane = measured.lane(laneIndex)
            let targetLeft = targetRMSDBFSByChannel[baseChannel]
            let targetRight = targetRMSDBFSByChannel[baseChannel + 1]
            let measuredLeft = DecibelScale.amplitudeToDBFS(lane.rmsLeft)
            let measuredRight = DecibelScale.amplitudeToDBFS(lane.rmsRight)

            return SyntheticLaneMeasurement(
                laneNumber: laneIndex + 1,
                targetRMSLeftDBFS: targetLeft,
                targetRMSRightDBFS: targetRight,
                measuredRMSLeftDBFS: measuredLeft,
                measuredRMSRightDBFS: measuredRight,
                deltaLeftDB: measuredLeft - targetLeft,
                deltaRightDB: measuredRight - targetRight
            )
        }

        let clipBuffer = try makeReferenceBuffer(
            sampleRate: sampleRate,
            frameCount: frameCount
        )
        let injectedPeak: Float = 1.01
        clipBuffer.floatChannelData![5][frameCount / 2] = injectedPeak
        let clipMeasurement = try AudioLevelMeter.measure(buffer: clipBuffer)
        let clipLane = clipMeasurement.lane(2)

        return SyntheticValidationReport(
            sampleRate: sampleRate,
            windowMs: windowMs,
            frameCount: frameCount,
            laneMeasurements: laneMeasurements,
            clipTestLane: 3,
            clipTestRightChannelTriggered: clipLane.clipRight,
            clipTestLeftChannelStayedClear: !clipLane.clipLeft,
            clipTestInjectedPeak: injectedPeak
        )
    }

    private static func makeReferenceBuffer(
        sampleRate: Double,
        frameCount: Int
    ) throws -> AVAudioPCMBuffer {
        let format = try AudioFormatFactory.makeFloatPCMFormat(
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(audioIOSpikeMeasuredChannelCount)
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw NSError(domain: "AudioIOSpike", code: -2)
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            throw AudioLevelMeterError.missingFloatChannelData
        }

        for channelIndex in 0..<audioIOSpikeMeasuredChannelCount {
            let rmsLinear = powf(10, targetRMSDBFSByChannel[channelIndex] / 20)
            let peakAmplitude = rmsLinear * sqrtf(2)
            let phaseOffset = Double(channelIndex) * (.pi / 8)
            let frequency = frequencyByChannel[channelIndex]
            let channel = channelData[channelIndex]

            for frameIndex in 0..<frameCount {
                let phase = (2 * Double.pi * frequency * Double(frameIndex) / sampleRate) + phaseOffset
                channel[frameIndex] = sinf(Float(phase)) * peakAmplitude
            }
        }

        return buffer
    }
}
