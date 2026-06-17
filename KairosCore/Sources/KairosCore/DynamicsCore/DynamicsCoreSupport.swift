import Foundation

let dynamicsIntegrationWindowMilliseconds = 300.0
let dynamicsClipThresholdAmplitude: Float = 1.0
let dynamicsClipHoldDurationMilliseconds: UInt64 = 2_000
let laneSignalFloorDBFS: Float = -60.0
let laneSignalFloorAmplitude = DynamicsDecibelScale.dbfsToAmplitude(laneSignalFloorDBFS)
let laneSignalDebounceMilliseconds: UInt64 = 2_000

enum DynamicsDecibelScale {
    static func amplitudeToDBFS(_ amplitude: Float) -> Float {
        guard amplitude > 0 else {
            return -.infinity
        }

        return 20 * log10f(amplitude)
    }

    static func dbfsToAmplitude(_ dbfs: Float) -> Float {
        powf(10, dbfs / 20)
    }
}

extension LaneID {
    var zeroBasedIndex: Int {
        rawValue - 1
    }
}

extension LaneDynamicsSample {
    static let zero = LaneDynamicsSample(
        rmsLeft: 0,
        rmsRight: 0,
        peakLeft: 0,
        peakRight: 0,
        clipLeft: false,
        clipRight: false
    )

    var clip: Bool {
        clipLeft || clipRight
    }

    var maximumRMSAmplitude: Float {
        max(rmsLeft, rmsRight)
    }
}

extension DynamicsSample {
    static let zero = DynamicsSample(
        hostTime: 0,
        sampleTime: 0,
        frameCount: 0,
        sampleRate: 0,
        lane1: .zero,
        lane2: .zero,
        lane3: .zero,
        lane4: .zero
    )

    func lane(_ lane: LaneID) -> LaneDynamicsSample {
        switch lane {
        case .one:
            return lane1
        case .two:
            return lane2
        case .three:
            return lane3
        case .four:
            return lane4
        }
    }

    func lane(at index: Int) -> LaneDynamicsSample {
        switch index {
        case 0:
            return lane1
        case 1:
            return lane2
        case 2:
            return lane3
        case 3:
            return lane4
        default:
            preconditionFailure("Lane index out of range: \(index)")
        }
    }
}

func dynamicsTimelineSeconds(for sample: DynamicsSample) -> Double {
    guard sample.sampleRate > 0 else {
        return Double(sample.hostTime) / 1_000.0
    }

    return Double(sample.sampleTime) / sample.sampleRate
}

func dynamicsTimelineMilliseconds(for sample: DynamicsSample) -> UInt64 {
    guard sample.sampleRate > 0 else {
        return sample.hostTime
    }

    return dynamicsTimelineMilliseconds(
        sampleTime: sample.sampleTime,
        sampleRate: sample.sampleRate
    )
}

func dynamicsTimelineMilliseconds(sampleTime: Int64, sampleRate: Double) -> UInt64 {
    guard sampleRate > 0 else {
        return 0
    }

    let milliseconds = (Double(sampleTime) / sampleRate) * 1_000.0
    return UInt64(max(milliseconds.rounded(), 0))
}
