import CAbletonLink

public struct LinkSessionSnapshot: Sendable, Equatable {
    public let tempo: Double
    public let beat: Double
    public let phase: Double
    public let isPlaying: Bool
    public let isEnabled: Bool
    public let peerCount: UInt64
    public let clockMicros: Int64

    public init(
        tempo: Double,
        beat: Double,
        phase: Double,
        isPlaying: Bool,
        isEnabled: Bool,
        peerCount: UInt64,
        clockMicros: Int64
    ) {
        self.tempo = tempo
        self.beat = beat
        self.phase = phase
        self.isPlaying = isPlaying
        self.isEnabled = isEnabled
        self.peerCount = peerCount
        self.clockMicros = clockMicros
    }
}

public final class LiveLinkSession {
    private let quantum: Double
    private var link: abl_link

    public init(
        initialTempo: Double = 120.0,
        quantum: Double = 4.0,
        isActive: Bool = false,
        startStopSyncEnabled: Bool = true
    ) {
        self.quantum = quantum
        self.link = abl_link_create(initialTempo)
        abl_link_enable_start_stop_sync(link, startStopSyncEnabled)
        abl_link_enable(link, isActive)
    }

    deinit {
        abl_link_destroy(link)
    }

    public func setActive(_ isActive: Bool) {
        abl_link_enable(link, isActive)
    }

    public func setTempo(_ tempo: Double) {
        let session = abl_link_create_session_state()
        let now = abl_link_clock_micros(link)
        abl_link_capture_app_session_state(link, session)
        abl_link_set_tempo(session, tempo, now)
        abl_link_commit_app_session_state(link, session)
        abl_link_destroy_session_state(session)
    }

    public func requestBeatAtStartPlayingTime(_ beat: Double = 0) {
        let session = abl_link_create_session_state()
        abl_link_capture_app_session_state(link, session)
        abl_link_request_beat_at_start_playing_time(session, beat, quantum)
        abl_link_commit_app_session_state(link, session)
        abl_link_destroy_session_state(session)
    }

    public func captureSnapshot() -> LinkSessionSnapshot {
        let session = abl_link_create_session_state()
        let now = abl_link_clock_micros(link)
        abl_link_capture_app_session_state(link, session)

        let snapshot = LinkSessionSnapshot(
            tempo: abl_link_tempo(session),
            beat: abl_link_beat_at_time(session, now, quantum),
            phase: abl_link_phase_at_time(session, now, quantum),
            isPlaying: abl_link_is_playing(session),
            isEnabled: abl_link_is_enabled(link),
            peerCount: abl_link_num_peers(link),
            clockMicros: now
        )

        abl_link_destroy_session_state(session)
        return snapshot
    }
}
