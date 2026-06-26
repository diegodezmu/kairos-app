import Foundation
import KairosCore

enum DesktopShellFormatters {
    struct PulseOption: Hashable {
        let title: String
        let value: Pulse
    }

    static let metronomePulseOptions: [PulseOption] = [
        PulseOption(title: Pulse.oneSixteenth.displayLabel, value: .oneSixteenth),
        PulseOption(title: Pulse.oneEighth.displayLabel, value: .oneEighth),
        PulseOption(title: Pulse.oneQuarter.displayLabel, value: .oneQuarter),
        PulseOption(title: Pulse.oneHalf.displayLabel, value: .oneHalf),
        PulseOption(title: Pulse.one.displayLabel, value: .one),
    ]

    static func elapsedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }

        return "\(remainingSeconds)s"
    }

    static func bpm(_ bpm: Int) -> String {
        "\(String(format: "%.2f", Double(bpm))) bpm"
    }

    static func bpm(_ bpm: Double) -> String {
        "\(String(format: "%.2f", bpm)) bpm"
    }

    static func bpmControl(_ bpm: Int) -> String {
        String(format: "%.2f", Double(bpm))
    }

    static func latency(_ milliseconds: Double) -> String {
        String(format: "%.2f ms", milliseconds)
    }

    static func latencyInput(_ milliseconds: Double) -> String {
        String(format: "%.2f", milliseconds)
    }

    static func targetLevel(_ db: Double) -> String {
        "\(Int(db.rounded())) db"
    }

    static func margin(_ db: Double) -> String {
        "\(Int(db.rounded())) db"
    }
}
