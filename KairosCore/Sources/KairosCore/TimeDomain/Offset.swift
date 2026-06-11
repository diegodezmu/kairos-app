import Foundation

/// Local offset shared by grid render and metronome click scheduling.
///
/// Product range: `-200 ms ... +200 ms` (PRD 5.6).
public struct Offset: Sendable, Equatable {
    public static let minimumMilliseconds = -200.0
    public static let maximumMilliseconds = 200.0

    public var milliseconds: Double

    public init(milliseconds: Double) {
        self.milliseconds = milliseconds
    }

    /// Converts the local offset to beats using `offsetMs / 1000 * tempo / 60`.
    public func beats(atTempo tempo: Double) -> Double {
        (milliseconds / 1_000.0) * (tempo / 60.0)
    }
}
