import Foundation

/// Reset mark rendered on the first step for the frame that wrapped.
public enum GridResetMark: String, Sendable {
    case none
    case combined
    case general
}

/// Reset outcome for one cycle slot on a specific frame.
public struct CycleResetState: Sendable, Equatable {
    public var slot: CycleSlot
    public var mark: GridResetMark

    public init(slot: CycleSlot, mark: GridResetMark) {
        self.slot = slot
        self.mark = mark
    }
}

/// Detects combined/general resets from consecutive cycle states.
public protocol ResetDetector: Sendable {
    func detectResets(
        previous: [CycleState],
        current: [CycleState]
    ) -> [CycleResetState]
}
