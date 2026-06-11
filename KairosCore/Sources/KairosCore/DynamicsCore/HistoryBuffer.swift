import Foundation

/// Allowed history windows from PRD 7.5.
public enum HistoryRange: Double, CaseIterable, Sendable {
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
}

/// Aggregated history bucket in linear amplitude, per stereo lane.
public struct LaneHistoryBucket: Sendable, Equatable {
    public var startHostTime: UInt64
    public var endHostTime: UInt64
    public var minimumRMSLeft: Float
    public var maximumRMSLeft: Float
    public var meanRMSLeft: Float
    public var minimumRMSRight: Float
    public var maximumRMSRight: Float
    public var meanRMSRight: Float

    public init(
        startHostTime: UInt64,
        endHostTime: UInt64,
        minimumRMSLeft: Float,
        maximumRMSLeft: Float,
        meanRMSLeft: Float,
        minimumRMSRight: Float,
        maximumRMSRight: Float,
        meanRMSRight: Float
    ) {
        self.startHostTime = startHostTime
        self.endHostTime = endHostTime
        self.minimumRMSLeft = minimumRMSLeft
        self.maximumRMSLeft = maximumRMSLeft
        self.meanRMSLeft = meanRMSLeft
        self.minimumRMSRight = minimumRMSRight
        self.maximumRMSRight = maximumRMSRight
        self.meanRMSRight = meanRMSRight
    }
}

/// Snapshot returned to the render/UI side after non-RT aggregation.
public struct LaneHistorySnapshot: Sendable, Equatable {
    public var lane: LaneID
    public var range: HistoryRange
    public var buckets: [LaneHistoryBucket]

    public init(
        lane: LaneID,
        range: HistoryRange,
        buckets: [LaneHistoryBucket]
    ) {
        self.lane = lane
        self.range = range
        self.buckets = buckets
    }
}

/// Per-lane storage of already-measured dynamics values.
public protocol HistoryBuffer: Sendable {
    func append(_ sample: DynamicsSample)

    func snapshot(
        for lane: LaneID,
        range: HistoryRange,
        columnCount: Int
    ) -> LaneHistorySnapshot
}
