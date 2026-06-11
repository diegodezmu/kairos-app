import Accelerate
import Foundation

struct DefaultRMSPeakMeter: RMSPeakMeasuring {
    func rootMeanSquare(of samples: UnsafeBufferPointer<Float>) -> Float {
        guard let baseAddress = samples.baseAddress, !samples.isEmpty else {
            return 0
        }

        var rootMeanSquare: Float = 0
        vDSP_rmsqv(baseAddress, 1, &rootMeanSquare, vDSP_Length(samples.count))
        return rootMeanSquare
    }

    func peakMagnitude(of samples: UnsafeBufferPointer<Float>) -> Float {
        guard let baseAddress = samples.baseAddress, !samples.isEmpty else {
            return 0
        }

        var peakMagnitude: Float = 0
        vDSP_maxmgv(baseAddress, 1, &peakMagnitude, vDSP_Length(samples.count))
        return peakMagnitude
    }
}
