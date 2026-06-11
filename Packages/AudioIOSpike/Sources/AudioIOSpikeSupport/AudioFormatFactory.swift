import AVFoundation
import CoreAudio
import Foundation

enum AudioFormatFactory {
    static func makeFloatPCMFormat(
        sampleRate: Double,
        channels: AVAudioChannelCount
    ) throws -> AVAudioFormat {
        let tag = AudioChannelLayoutTag(kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels))
        guard let channelLayout = AVAudioChannelLayout(layoutTag: tag) else {
            throw NSError(domain: "AudioIOSpike", code: -10)
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: false,
            channelLayout: channelLayout
        )

        return format
    }
}
