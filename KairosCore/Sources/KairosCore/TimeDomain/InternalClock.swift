import Foundation

/// ClockSource implementation for the app-owned internal transport.
public struct InternalClock: ClockSource, Sendable {
    private let timeline: ClockTimelineBox

    public init() {
        self.timeline = .makeInternal()
    }

    init(
        tempo: Double = 120.0,
        quantum: Double = 4.0,
        hostTimeUnitsPerSecond: Double = 1_000_000_000.0
    ) {
        self.timeline = .makeInternal(
            tempo: tempo,
            quantum: quantum,
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

    func play(atHostTime hostTime: UInt64) {
        timeline.play(atHostTime: hostTime)
    }

    func stop(atHostTime hostTime: UInt64) {
        timeline.stop(atHostTime: hostTime)
    }

    func reset(atHostTime hostTime: UInt64) {
        timeline.reset(atHostTime: hostTime)
    }

    func setTempo(_ tempo: Double, atHostTime hostTime: UInt64) {
        timeline.setTempo(tempo, atHostTime: hostTime)
    }

    func setQuantum(_ quantum: Double) {
        timeline.setQuantum(quantum)
    }
}
