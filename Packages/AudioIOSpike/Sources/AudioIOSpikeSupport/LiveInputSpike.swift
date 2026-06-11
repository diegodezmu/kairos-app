import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

public enum LiveInputSpikeRunner {
    public static func run(captureDurationSeconds: TimeInterval = 1.0) -> LiveInputCaptureReport {
        do {
            guard let blackHole = try AudioDeviceCatalog.blackHole16chInput() else {
                return LiveInputCaptureReport(
                    status: .pending,
                    reason: "DECISION-NEEDED (entorno: falta BlackHole 16ch)",
                    deviceName: nil,
                    deviceUID: nil,
                    inputChannels: nil,
                    tapChannelCount: nil,
                    measuredChannels: nil,
                    requestedFrameCount: nil,
                    observedFrameCount: nil,
                    callbackCount: 0,
                    publishedSampleCount: 0,
                    droppedSampleCount: 0,
                    firstSample: nil,
                    lastSample: nil
                )
            }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            try configureInputDevice(blackHole.id, on: inputNode)

            let inputFormat = inputNode.inputFormat(forBus: 0)
            let tapChannelCount = Int(inputFormat.channelCount)
            guard tapChannelCount >= audioIOSpikeMeasuredChannelCount else {
                return LiveInputCaptureReport(
                    status: .failed,
                    reason: "BlackHole opened with only \(tapChannelCount) channels; expected at least 8",
                    deviceName: blackHole.name,
                    deviceUID: blackHole.uid,
                    inputChannels: blackHole.inputChannels,
                    tapChannelCount: tapChannelCount,
                    measuredChannels: audioIOSpikeMeasuredChannelCount,
                    requestedFrameCount: nil,
                    observedFrameCount: nil,
                    callbackCount: 0,
                    publishedSampleCount: 0,
                    droppedSampleCount: 0,
                    firstSample: nil,
                    lastSample: nil
                )
            }

            let tapFormat = try AudioFormatFactory.makeFloatPCMFormat(
                sampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount
            )

            let requestedFrameCount = AVAudioFrameCount(
                max(1, Int((inputFormat.sampleRate * (audioIOSpikeIntegrationWindowMs / 1_000)).rounded()))
            )

            let state = LiveTapState()
            inputNode.installTap(onBus: 0, bufferSize: requestedFrameCount, format: tapFormat) { buffer, time in
                state.callbackCount.increment()
                state.lastFrameCount.store(buffer.frameLength)

                guard let channelData = buffer.floatChannelData else {
                    return
                }

                let sample = AudioLevelMeter.measure(
                    floatChannelData: channelData,
                    frameCount: Int(buffer.frameLength),
                    sampleRate: buffer.format.sampleRate,
                    hostTime: time.hostTime,
                    sampleTime: time.sampleTime
                )

                if !state.ringBuffer.push(sample) {
                    state.droppedCount.increment()
                }
            }

            engine.prepare()
            try engine.start()
            Thread.sleep(forTimeInterval: captureDurationSeconds)
            inputNode.removeTap(onBus: 0)
            engine.stop()

            let publishedSamples = state.ringBuffer.drain()
            let live = LiveInputCaptureReport(
                status: publishedSamples.isEmpty ? .failed : .passed,
                reason: publishedSamples.isEmpty
                    ? "BlackHole estaba presente, pero el callback no publicó muestras"
                    : "BlackHole abierto directamente con AVAudioEngine; callback activo y publicando por ring buffer",
                deviceName: blackHole.name,
                deviceUID: blackHole.uid,
                inputChannels: blackHole.inputChannels,
                tapChannelCount: tapChannelCount,
                measuredChannels: audioIOSpikeMeasuredChannelCount,
                requestedFrameCount: requestedFrameCount,
                observedFrameCount: state.lastFrameCount.load(),
                callbackCount: state.callbackCount.load(),
                publishedSampleCount: publishedSamples.count,
                droppedSampleCount: state.droppedCount.load(),
                firstSample: publishedSamples.first,
                lastSample: publishedSamples.last
            )

            return live
        } catch {
            return LiveInputCaptureReport(
                status: .failed,
                reason: "BlackHole presente pero la apertura directa falló: \(error)",
                deviceName: "BlackHole 16ch",
                deviceUID: nil,
                inputChannels: nil,
                tapChannelCount: nil,
                measuredChannels: audioIOSpikeMeasuredChannelCount,
                requestedFrameCount: nil,
                observedFrameCount: nil,
                callbackCount: 0,
                publishedSampleCount: 0,
                droppedSampleCount: 0,
                firstSample: nil,
                lastSample: nil
            )
        }
    }

    private static func configureInputDevice(
        _ deviceID: AudioDeviceID,
        on inputNode: AVAudioInputNode
    ) throws {
        guard let audioUnit = inputNode.audioUnit else {
            throw NSError(domain: "AudioIOSpike", code: -4)
        }

        var enableInput: UInt32 = 1
        try setAudioUnitUInt32Property(
            audioUnit,
            selector: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Input,
            element: 1,
            value: &enableInput
        )

        var disableOutput: UInt32 = 0
        try setAudioUnitUInt32Property(
            audioUnit,
            selector: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Output,
            element: 0,
            value: &disableOutput
        )

        var mutableDeviceID = deviceID
        try setAudioUnitDeviceProperty(
            audioUnit,
            selector: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: &mutableDeviceID
        )
    }

    private static func setAudioUnitUInt32Property(
        _ audioUnit: AudioUnit,
        selector: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: inout UInt32
    ) throws {
        let status = withUnsafePointer(to: &value) { pointer in
            AudioUnitSetProperty(
                audioUnit,
                selector,
                scope,
                element,
                pointer,
                UInt32(MemoryLayout<UInt32>.stride)
            )
        }

        guard status == noErr else {
            throw AudioHardwareError(operation: "AudioUnitSetProperty(\(selector))", status: status)
        }
    }

    private static func setAudioUnitDeviceProperty(
        _ audioUnit: AudioUnit,
        selector: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: inout AudioDeviceID
    ) throws {
        let status = withUnsafePointer(to: &value) { pointer in
            AudioUnitSetProperty(
                audioUnit,
                selector,
                scope,
                element,
                pointer,
                UInt32(MemoryLayout<AudioDeviceID>.stride)
            )
        }

        guard status == noErr else {
            throw AudioHardwareError(operation: "AudioUnitSetProperty(\(selector))", status: status)
        }
    }
}

private final class LiveTapState {
    let ringBuffer = DynamicsSampleRingBuffer(capacity: 256)
    let callbackCount = AtomicUInt32Box()
    let droppedCount = AtomicUInt32Box()
    let lastFrameCount = AtomicUInt32Box()
}
