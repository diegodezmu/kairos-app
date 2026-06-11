import Foundation

/// Captures `originBeat` exactly once from the shared transport origin.
struct OriginLatch: Sendable {
    private(set) var frozenOriginBeat: Double?

    init(frozenOriginBeat: Double? = nil) {
        self.frozenOriginBeat = frozenOriginBeat
    }

    mutating func observe(clock: some ClockSource) -> Double? {
        observe(
            hasOrigin: clock.hasOrigin,
            originHostTime: clock.originHostTime,
            beatAtHostTime: clock.beat(atHostTime:)
        )
    }

    mutating func observe(
        hasOrigin: Bool,
        originHostTime: UInt64?,
        beatAtHostTime: (UInt64) -> Double
    ) -> Double? {
        guard frozenOriginBeat == nil else {
            return frozenOriginBeat
        }

        guard hasOrigin, let originHostTime else {
            return nil
        }

        let beat = beatAtHostTime(originHostTime)
        frozenOriginBeat = beat
        return beat
    }

    mutating func reset() {
        frozenOriginBeat = nil
    }
}
