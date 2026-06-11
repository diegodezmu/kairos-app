import Foundation

/// Shared musical clock consumed by the temporal core.
///
/// Contract notes:
/// - `quantum` is the transport quantum, never the cycle length.
/// - `beat(atHostTime:)` must stay continuous across tempo changes.
/// - The frozen `originBeat` used by `CycleEngine` is intentionally not exposed here;
///   it is latched once per peer by the TimeDomain owner when `originHostTime`
///   becomes known.
public protocol ClockSource: Sendable {
    /// Current transport tempo in BPM.
    var tempo: Double { get }

    /// Continuous musical position for the requested host time.
    func beat(atHostTime hostTime: UInt64) -> Double

    /// Whether transport is currently running.
    var isPlaying: Bool { get }

    /// Shared transport quantum used by the underlying clock source.
    var quantum: Double { get }

    /// Shared transport start host time when known.
    var originHostTime: UInt64? { get }

    /// `true` only after `originHostTime` is known and the owner has latched
    /// its local `originBeat`.
    var hasOrigin: Bool { get }

    /// Adopts a shared transport origin received from a side channel.
    func adoptSharedOrigin(hostTime: UInt64)
}
