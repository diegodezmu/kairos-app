import Foundation

public enum AudioIOSpikeRunner {
    public static func run(captureDurationSeconds: TimeInterval = 1.0) throws -> AudioIOSpikeReport {
        let partA = try SyntheticValidationRunner.run()
        let partB = LiveInputSpikeRunner.run(captureDurationSeconds: captureDurationSeconds)
        return AudioIOSpikeReport(partA: partA, partB: partB)
    }
}
