import CAbletonLink

public struct LinkSmokeResult: Sendable, Equatable {
    public let tempo: Double
    public let isEnabled: Bool
    public let peerCount: UInt64

    public init(tempo: Double, isEnabled: Bool, peerCount: UInt64) {
        self.tempo = tempo
        self.isEnabled = isEnabled
        self.peerCount = peerCount
    }

    public var report: String {
        "Ableton Link smoke ok: enabled=\(isEnabled) peers=\(peerCount) tempo=\(tempo)"
    }
}

public enum LinkSDKSmoke {
    public static func run(initialTempo: Double = 120.0) -> LinkSmokeResult {
        let link = abl_link_create(initialTempo)
        let sessionState = abl_link_create_session_state()

        defer {
            abl_link_destroy_session_state(sessionState)
            abl_link_destroy(link)
        }

        abl_link_capture_app_session_state(link, sessionState)

        return LinkSmokeResult(
            tempo: abl_link_tempo(sessionState),
            isEnabled: abl_link_is_enabled(link),
            peerCount: abl_link_num_peers(link)
        )
    }
}
