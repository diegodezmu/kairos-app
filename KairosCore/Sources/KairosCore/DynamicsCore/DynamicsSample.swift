import Foundation

public let kairosLaneCount = 4
public let kairosChannelsPerLane = 2

/// Stable identity for the four stereo lanes defined by PRD 7.1.
public enum LaneID: Int, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
}

/// Linear-amplitude dynamics payload for a single stereo lane.
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
}

/// Fixed-shape RT payload published out of the audio callback seam.
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
}
