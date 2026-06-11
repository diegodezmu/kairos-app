import Foundation

/// ClockSource implementation for an externally-driven MIDI transport.
public struct MIDIClock: ClockSource, Sendable {
    private let timeline: ClockTimelineBox

    public init() {
        self.timeline = .makeExternal()
    }

    init(
        snapshot: ExternalClockSnapshot? = nil,
        hostTimeUnitsPerSecond: Double = 1_000_000_000.0
    ) {
        self.timeline = .makeExternal(
            snapshot: snapshot,
            hostTimeUnitsPerSecond: hostTimeUnitsPerSecond
        )
    }

    public var tempo: Double {
        timeline.tempo
    }

    public func beat(atHostTime hostTime: UInt64) -> Double {
        timeline.beat(atHostTime: hostTime)
    }

    public var isPlaying: Bool {
        timeline.isPlaying
    }

    public var quantum: Double {
        timeline.quantum
    }

    public var originHostTime: UInt64? {
        timeline.originHostTime
    }

    public var hasOrigin: Bool {
        timeline.hasOrigin
    }

    public func adoptSharedOrigin(hostTime: UInt64) {
        timeline.adoptSharedOrigin(hostTime: hostTime)
    }

    func update(with snapshot: ExternalClockSnapshot) {
        timeline.update(with: snapshot)
    }
}
