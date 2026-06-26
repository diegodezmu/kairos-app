import AVFoundation
import CoreAudio
import Foundation
import KairosCore

struct MetronomeScheduleContext: Equatable {
    let currentBeat: Double
    let tempoBPM: Double
    let pulse: Pulse
    let offset: Offset

    var beatsPerSecond: Double {
        tempoBPM / 60.0
    }

    var intervalBeats: Double {
        pulse.stepDurationBeats
    }

    var currentEffectiveBeat: Double {
        currentBeat + offset.beats(atTempo: tempoBPM)
    }
}

struct MetronomeScheduledTick: Equatable {
    let tickIndex: Int64
    let delaySeconds: Double
}

enum MetronomeTickScheduler {
    private static let boundaryToleranceBeats = 0.000_5

    static func ticksToSchedule(
        context: MetronomeScheduleContext,
        horizonSeconds: Double,
        lastScheduledTick: Int64?
    ) -> [MetronomeScheduledTick] {
        guard
            context.tempoBPM > 0,
            context.intervalBeats > 0,
            horizonSeconds >= 0
        else {
            return []
        }

        let currentEffectiveBeat = context.currentEffectiveBeat
        let horizonEffectiveBeat = currentEffectiveBeat
            + (horizonSeconds * context.beatsPerSecond)
        let intervalBeats = context.intervalBeats
        let boundaryTick = Int64(floor(currentEffectiveBeat / intervalBeats))
        let boundaryBeat = Double(boundaryTick) * intervalBeats
        let isOnBoundary = abs(currentEffectiveBeat - boundaryBeat) <= boundaryToleranceBeats

        let startTick: Int64
        if let lastScheduledTick {
            startTick = max(
                lastScheduledTick + 1,
                boundaryTick + (isOnBoundary ? 0 : 1)
            )
        } else {
            startTick = boundaryTick + (isOnBoundary ? 0 : 1)
        }

        var ticks: [MetronomeScheduledTick] = []
        var nextTick = startTick

        while true {
            let nextTickBeat = Double(nextTick) * intervalBeats
            guard nextTickBeat <= horizonEffectiveBeat + boundaryToleranceBeats else {
                break
            }

            let delayBeats = nextTickBeat - currentEffectiveBeat
            let delaySeconds = max(delayBeats / context.beatsPerSecond, 0)
            ticks.append(
                MetronomeScheduledTick(
                    tickIndex: nextTick,
                    delaySeconds: delaySeconds
                )
            )
            nextTick += 1
        }

        return ticks
    }
}

@MainActor
final class MetronomeClickEngine {
    private static let scheduleHorizonSeconds = 0.25
    private static let transportRegressionToleranceBeats = 0.05

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let clickFormat = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 2
    )

    private var clickBuffer: AVAudioPCMBuffer?
    private var lastScheduledTick: Int64?
    private var lastObservedEffectiveBeat: Double?
    private var lastPulse: Pulse?
    private var lastOffsetMilliseconds: Double?

    init() {
        if let clickFormat {
            clickBuffer = Self.makeClickBuffer(format: clickFormat)
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: clickFormat)
            engine.prepare()
        }
    }

    func schedule(context: MetronomeScheduleContext) {
        guard
            let clickBuffer,
            ensurePlaybackReady()
        else {
            return
        }

        let currentEffectiveBeat = context.currentEffectiveBeat
        if shouldResetSchedule(
            for: context,
            currentEffectiveBeat: currentEffectiveBeat
        ) {
            resetScheduledClicks()
        }

        let scheduledTicks = MetronomeTickScheduler.ticksToSchedule(
            context: context,
            horizonSeconds: Self.scheduleHorizonSeconds,
            lastScheduledTick: lastScheduledTick
        )
        guard !scheduledTicks.isEmpty else {
            lastObservedEffectiveBeat = currentEffectiveBeat
            lastPulse = context.pulse
            lastOffsetMilliseconds = context.offset.milliseconds
            return
        }

        let currentHostTime = UInt64(AudioGetCurrentHostTime())
        for scheduledTick in scheduledTicks {
            let hostTime = currentHostTime
                + AudioConvertNanosToHostTime(
                    UInt64((scheduledTick.delaySeconds * 1_000_000_000.0).rounded())
                )
            playerNode.scheduleBuffer(
                clickBuffer,
                at: AVAudioTime(hostTime: hostTime),
                options: []
            )
        }

        lastScheduledTick = scheduledTicks.last?.tickIndex
        lastObservedEffectiveBeat = currentEffectiveBeat
        lastPulse = context.pulse
        lastOffsetMilliseconds = context.offset.milliseconds
    }

    func stop() {
        resetScheduledClicks()
    }

    private func shouldResetSchedule(
        for context: MetronomeScheduleContext,
        currentEffectiveBeat: Double
    ) -> Bool {
        if lastPulse != context.pulse {
            return true
        }

        if lastOffsetMilliseconds != context.offset.milliseconds {
            return true
        }

        guard let lastObservedEffectiveBeat else {
            return false
        }

        return currentEffectiveBeat
            < lastObservedEffectiveBeat - Self.transportRegressionToleranceBeats
    }

    private func ensurePlaybackReady() -> Bool {
        guard clickBuffer != nil else {
            return false
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return false
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        return true
    }

    private func resetScheduledClicks() {
        if playerNode.isPlaying {
            playerNode.stop()
        }
        playerNode.reset()
        lastScheduledTick = nil
        lastObservedEffectiveBeat = nil
        lastPulse = nil
        lastOffsetMilliseconds = nil
    }

    private static func makeClickBuffer(
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let durationSeconds = 0.018
        let frameCount = AVAudioFrameCount(
            max((format.sampleRate * durationSeconds).rounded(), 1)
        )
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ),
            let channelData = buffer.floatChannelData
        else {
            return nil
        }

        buffer.frameLength = frameCount
        let channelCount = Int(format.channelCount)
        let sampleRate = format.sampleRate
        var clickPhase = 0.0
        var lowpassedNoise = 0.0

        // Pure click transient: no resonant body, almost flat pitch, no echo tail.
        for frame in 0 ..< Int(frameCount) {
            let time = Double(frame) / sampleRate
            let attack = min(time / 0.00008, 1.0)

            let clickFrequency = 3_200.0 + (140.0 * exp(-time * 650.0))
            clickPhase += (2.0 * .pi * clickFrequency) / sampleRate
            let tone = sin(clickPhase) * exp(-time * 420.0)
            let edge = 0.14 * sin(2.0 * .pi * 5_400.0 * time) * exp(-time * 760.0)

            let noiseSeed = sin((Double(frame) * 12.9898) + 78.233) * 43_758.5453
            let whiteNoise = ((noiseSeed - floor(noiseSeed)) * 2.0) - 1.0
            lowpassedNoise += (whiteNoise - lowpassedNoise) * 0.22
            let clickNoise = (whiteNoise - lowpassedNoise) * exp(-time * 900.0)

            let sample = tanh(
                ((tone * 0.78) + edge + (clickNoise * 0.34))
                    * attack
                    * 1.7
            ) * 0.52
            let clampedSample = max(-0.95, min(0.95, Float(sample)))

            for channel in 0 ..< channelCount {
                channelData[channel][frame] = clampedSample
            }
        }

        return buffer
    }
}
