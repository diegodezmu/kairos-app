import Foundation

/// Peak threshold evaluator for clip detection.
public protocol ClipDetector: Sendable {
    func isClipping(peakAmplitude: Float) -> Bool

    func detectClipping(
        leftPeak: Float,
        rightPeak: Float
    ) -> (left: Bool, right: Bool)
}
