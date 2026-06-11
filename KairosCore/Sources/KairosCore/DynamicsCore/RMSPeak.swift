import Foundation

/// RMS/peak measurement surface for the RT audio seam.
public protocol RMSPeakMeasuring: Sendable {
    func rootMeanSquare(of samples: UnsafeBufferPointer<Float>) -> Float
    func peakMagnitude(of samples: UnsafeBufferPointer<Float>) -> Float
}
