import Foundation

struct ExternalClockSnapshot: Sendable {
    var tempo: Double
    var beat: Double
    var isPlaying: Bool
    var quantum: Double
    var originHostTime: UInt64?
    var hasOrigin: Bool
    var hostTime: UInt64

    init(
        tempo: Double,
        beat: Double,
        isPlaying: Bool,
        quantum: Double,
        originHostTime: UInt64?,
        hasOrigin: Bool,
        hostTime: UInt64
    ) {
        self.tempo = tempo
        self.beat = beat
        self.isPlaying = isPlaying
        self.quantum = quantum
        self.originHostTime = originHostTime
        self.hasOrigin = hasOrigin
        self.hostTime = hostTime
    }
}

private struct ClockTimelineState {
    var tempo: Double
    var quantum: Double
    var isPlaying: Bool
    var anchorBeat: Double
    var anchorHostTime: UInt64
    var originHostTime: UInt64?
    var hasOrigin: Bool
    var hostTimeUnitsPerSecond: Double
}

final class ClockTimelineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: ClockTimelineState

    private init(state: ClockTimelineState) {
        self.state = state
    }

    var tempo: Double {
        withLock { $0.tempo }
    }

    var quantum: Double {
        withLock { $0.quantum }
    }

    var isPlaying: Bool {
        withLock { $0.isPlaying }
    }

    var originHostTime: UInt64? {
        withLock { $0.originHostTime }
    }

    var hasOrigin: Bool {
        withLock { $0.hasOrigin }
    }

    func beat(atHostTime hostTime: UInt64) -> Double {
        withLock { beat(state: $0, atHostTime: hostTime) }
    }

    func play(atHostTime hostTime: UInt64) {
        withLock { state in
            state.anchorBeat = 0
            state.anchorHostTime = hostTime
            state.originHostTime = hostTime
            state.hasOrigin = true
            state.isPlaying = true
        }
    }

    func stop(atHostTime hostTime: UInt64) {
        withLock { state in
            state.anchorBeat = beat(state: state, atHostTime: hostTime)
            state.anchorHostTime = hostTime
            state.isPlaying = false
        }
    }

    func reset(atHostTime hostTime: UInt64) {
        withLock { state in
            state.anchorBeat = 0
            state.anchorHostTime = hostTime
            state.originHostTime = hostTime
            state.hasOrigin = true
        }
    }

    func setTempo(_ tempo: Double, atHostTime hostTime: UInt64) {
        withLock { state in
            state.anchorBeat = beat(state: state, atHostTime: hostTime)
            state.anchorHostTime = hostTime
            state.tempo = tempo
        }
    }

    func setQuantum(_ quantum: Double) {
        withLock { state in
            state.quantum = quantum
        }
    }

    func update(with snapshot: ExternalClockSnapshot) {
        withLock { state in
            state.anchorBeat = snapshot.beat
            state.anchorHostTime = snapshot.hostTime
            state.tempo = snapshot.tempo
            state.isPlaying = snapshot.isPlaying
            state.quantum = snapshot.quantum
            state.originHostTime = snapshot.originHostTime
            state.hasOrigin = snapshot.hasOrigin
        }
    }

    func adoptSharedOrigin(hostTime: UInt64) {
        withLock { state in
            state.originHostTime = hostTime
            state.hasOrigin = true
        }
    }

    private func beat(state: ClockTimelineState, atHostTime hostTime: UInt64) -> Double {
        guard state.isPlaying else {
            return state.anchorBeat
        }

        let deltaSeconds = signedDifference(hostTime, state.anchorHostTime) / state.hostTimeUnitsPerSecond
        let deltaBeats = deltaSeconds * (state.tempo / 60.0)
        return state.anchorBeat + deltaBeats
    }

    private func signedDifference(_ lhs: UInt64, _ rhs: UInt64) -> Double {
        if lhs >= rhs {
            return Double(lhs - rhs)
        }

        return -Double(rhs - lhs)
    }

    private func withLock<Result>(_ body: (inout ClockTimelineState) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}

extension ClockTimelineBox {
    static func makeInternal(
        tempo: Double = 120.0,
        quantum: Double = 4.0,
        hostTimeUnitsPerSecond: Double = 1_000_000_000.0
    ) -> ClockTimelineBox {
        ClockTimelineBox(
            state: ClockTimelineState(
                tempo: tempo,
                quantum: quantum,
                isPlaying: false,
                anchorBeat: 0,
                anchorHostTime: 0,
                originHostTime: nil,
                hasOrigin: false,
                hostTimeUnitsPerSecond: hostTimeUnitsPerSecond
            )
        )
    }

    static func makeExternal(
        snapshot: ExternalClockSnapshot? = nil,
        hostTimeUnitsPerSecond: Double = 1_000_000_000.0
    ) -> ClockTimelineBox {
        let snapshot = snapshot ?? ExternalClockSnapshot(
            tempo: 120.0,
            beat: 0,
            isPlaying: false,
            quantum: 4.0,
            originHostTime: nil,
            hasOrigin: false,
            hostTime: 0
        )

        return ClockTimelineBox(
            state: ClockTimelineState(
                tempo: snapshot.tempo,
                quantum: snapshot.quantum,
                isPlaying: snapshot.isPlaying,
                anchorBeat: snapshot.beat,
                anchorHostTime: snapshot.hostTime,
                originHostTime: snapshot.originHostTime,
                hasOrigin: snapshot.hasOrigin,
                hostTimeUnitsPerSecond: hostTimeUnitsPerSecond
            )
        )
    }
}
