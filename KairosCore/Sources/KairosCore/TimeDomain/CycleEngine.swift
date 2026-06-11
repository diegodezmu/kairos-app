import Foundation

/// Pure cycle resolver over a beat that already includes local offset.
public protocol CycleEngine: Sendable {
    /// Resolves a single cycle.
    ///
    /// - Parameters:
    ///   - config: Cycle definition to resolve.
    ///   - beat: Beat already shifted by local `Offset`, when applicable.
    ///   - frozenOriginBeat: Latched origin beat captured once by the TimeDomain owner.
    func resolveState(
        for config: CycleConfig,
        beat: Double,
        frozenOriginBeat: Double?
    ) -> CycleState

    /// Resolves multiple active cycles for the same beat.
    func resolveStates(
        for configs: [CycleConfig],
        beat: Double,
        frozenOriginBeat: Double?
    ) -> [CycleState]
}
