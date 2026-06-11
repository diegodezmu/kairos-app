import Foundation

public let audioIOSpikeLaneCount = 4
public let audioIOSpikeChannelsPerLane = 2
public let audioIOSpikeMeasuredChannelCount = audioIOSpikeLaneCount * audioIOSpikeChannelsPerLane
public let audioIOSpikeIntegrationWindowMs = 300.0
public let audioIOSpikeClipThreshold: Float = 1.0

public struct LaneDynamicsSample: Sendable, Equatable {
    public var rmsLeft: Float
    public var rmsRight: Float
    public var peakLeft: Float
    public var peakRight: Float
    public var clipLeft: Bool
    public var clipRight: Bool

    public init(
        rmsLeft: Float,
        rmsRight: Float,
        peakLeft: Float,
        peakRight: Float,
        clipLeft: Bool,
        clipRight: Bool
    ) {
        self.rmsLeft = rmsLeft
        self.rmsRight = rmsRight
        self.peakLeft = peakLeft
        self.peakRight = peakRight
        self.clipLeft = clipLeft
        self.clipRight = clipRight
    }

    public var clip: Bool {
        clipLeft || clipRight
    }

    public static let zero = LaneDynamicsSample(
        rmsLeft: 0,
        rmsRight: 0,
        peakLeft: 0,
        peakRight: 0,
        clipLeft: false,
        clipRight: false
    )
}

public struct DynamicsSample: Sendable, Equatable {
    public var hostTime: UInt64
    public var sampleTime: Int64
    public var frameCount: UInt32
    public var sampleRate: Double
    public var lane1: LaneDynamicsSample
    public var lane2: LaneDynamicsSample
    public var lane3: LaneDynamicsSample
    public var lane4: LaneDynamicsSample

    public init(
        hostTime: UInt64,
        sampleTime: Int64,
        frameCount: UInt32,
        sampleRate: Double,
        lane1: LaneDynamicsSample,
        lane2: LaneDynamicsSample,
        lane3: LaneDynamicsSample,
        lane4: LaneDynamicsSample
    ) {
        self.hostTime = hostTime
        self.sampleTime = sampleTime
        self.frameCount = frameCount
        self.sampleRate = sampleRate
        self.lane1 = lane1
        self.lane2 = lane2
        self.lane3 = lane3
        self.lane4 = lane4
    }

    public func lane(_ index: Int) -> LaneDynamicsSample {
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

    public static let zero = DynamicsSample(
        hostTime: 0,
        sampleTime: 0,
        frameCount: 0,
        sampleRate: 0,
        lane1: .zero,
        lane2: .zero,
        lane3: .zero,
        lane4: .zero
    )
}

public enum PartBStatus: String, Sendable {
    case passed
    case pending
    case failed
}

public struct SyntheticLaneMeasurement: Sendable {
    public var laneNumber: Int
    public var targetRMSLeftDBFS: Float
    public var targetRMSRightDBFS: Float
    public var measuredRMSLeftDBFS: Float
    public var measuredRMSRightDBFS: Float
    public var deltaLeftDB: Float
    public var deltaRightDB: Float
}

public struct SyntheticValidationReport: Sendable {
    public var sampleRate: Double
    public var windowMs: Double
    public var frameCount: Int
    public var laneMeasurements: [SyntheticLaneMeasurement]
    public var clipTestLane: Int
    public var clipTestRightChannelTriggered: Bool
    public var clipTestLeftChannelStayedClear: Bool
    public var clipTestInjectedPeak: Float

    public var passed: Bool {
        laneMeasurements.allSatisfy {
            abs($0.deltaLeftDB) <= 0.5 && abs($0.deltaRightDB) <= 0.5
        } && clipTestRightChannelTriggered && clipTestLeftChannelStayedClear
    }
}

public struct LiveInputCaptureReport: Sendable {
    public var status: PartBStatus
    public var reason: String
    public var deviceName: String?
    public var deviceUID: String?
    public var inputChannels: Int?
    public var tapChannelCount: Int?
    public var measuredChannels: Int?
    public var requestedFrameCount: UInt32?
    public var observedFrameCount: UInt32?
    public var callbackCount: UInt32
    public var publishedSampleCount: Int
    public var droppedSampleCount: UInt32
    public var firstSample: DynamicsSample?
    public var lastSample: DynamicsSample?
}

public struct AudioIOSpikeReport: Sendable {
    public var partA: SyntheticValidationReport
    public var partB: LiveInputCaptureReport
}

public enum DecibelScale {
    public static func amplitudeToDBFS(_ value: Float) -> Float {
        guard value > 0 else {
            return -.infinity
        }
        return 20 * log10f(value)
    }
}
