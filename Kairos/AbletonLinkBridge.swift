import Foundation
import KairosLinkSDK

struct AbletonLinkSnapshot: Equatable, Sendable {
    let tempoBPM: Double
    let beat: Double
    let phase: Double
    let isPlaying: Bool
    let isEnabled: Bool
    let peerCount: Int

    var elapsedSeconds: TimeInterval {
        guard tempoBPM > 0 else {
            return 0
        }

        return beat / (tempoBPM / 60.0)
    }
}

@MainActor
final class AbletonLinkBridge {
    private let session: LiveLinkSession

    init(initialTempo: Double) {
        session = LiveLinkSession(
            initialTempo: initialTempo,
            quantum: 4,
            isActive: false,
            startStopSyncEnabled: true
        )
    }

    func setActive(_ isActive: Bool) {
        session.setActive(isActive)
    }

    func seedTempo(_ tempo: Double) {
        session.setTempo(tempo)
    }

    func captureSnapshot() -> AbletonLinkSnapshot {
        let snapshot = session.captureSnapshot()
        return AbletonLinkSnapshot(
            tempoBPM: snapshot.tempo,
            beat: snapshot.beat,
            phase: snapshot.phase,
            isPlaying: snapshot.isPlaying,
            isEnabled: snapshot.isEnabled,
            peerCount: Int(snapshot.peerCount)
        )
    }
}
