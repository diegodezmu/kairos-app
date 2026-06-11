import Foundation

/// Public signal states from PRD 7.7.2.
public enum LaneSignalState: String, Sendable {
    case disabled
    case noSignal
    case receiving
    case clipping
}

/// Sidebar-facing input status for a lane.
public struct LaneInputStatus: Sendable, Equatable {
    public var lane: LaneID
    public var state: LaneSignalState

    /// Honest physical/channel caption, e.g. `BlackHole 1-2`.
    public var channelLabel: String

    /// State-dependent visible label, e.g. `BlackHole 1-2`, `No signal`, `Clipping`.
    public var displayLabel: String

    public init(
        lane: LaneID,
        state: LaneSignalState,
        channelLabel: String,
        displayLabel: String
    ) {
        self.lane = lane
        self.state = state
        self.channelLabel = channelLabel
        self.displayLabel = displayLabel
    }
}
