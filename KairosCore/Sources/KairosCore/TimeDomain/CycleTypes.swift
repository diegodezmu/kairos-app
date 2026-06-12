import Foundation

/// Stable identity for the four cycle slots exposed by the product.
public enum CycleSlot: Int, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
}

/// Allowed step counts from PRD 5.3.
public enum StepNumber: Int, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case four = 4
    case eight = 8
    case sixteen = 16
    case thirtyTwo = 32
    case sixtyFour = 64
    case oneHundredTwentyEight = 128
}

/// Allowed pulse note fractions from PRD 5.3 / 15.5.
public enum Pulse: Double, CaseIterable, Sendable {
    case oneSixteenth = 0.0625
    case oneEighth = 0.125
    case oneQuarter = 0.25
    case oneHalf = 0.5
    case one = 1
    case two = 2
    case four = 4
    case eight = 8
    case sixteen = 16
    case thirtyTwo = 32
    case sixtyFour = 64

    /// Resolves the musical note value to beat duration where a quarter note is 1 beat.
    public var stepDurationBeats: Double {
        rawValue * 4.0
    }
}

/// Immutable cycle definition consumed by the temporal layer.
public struct CycleConfig: Sendable, Equatable {
    public var slot: CycleSlot
    public var stepNumber: StepNumber
    public var pulse: Pulse

    public init(
        slot: CycleSlot,
        stepNumber: StepNumber,
        pulse: Pulse
    ) {
        self.slot = slot
        self.stepNumber = stepNumber
        self.pulse = pulse
    }
}

/// Resolved cycle state for a single render frame or metronome scheduling instant.
public struct CycleState: Sendable, Equatable {
    public var config: CycleConfig

    /// Zero-based active step. `nil` when no deterministic origin exists yet.
    public var currentStep: Int?

    /// Zero-based cycle iteration from the frozen origin. `nil` when origin is absent.
    public var cycleIteration: Int?

    /// Final steps to highlight in red, using zero-based half-open indexing.
    public var anticipationRange: Range<Int>?

    public init(
        config: CycleConfig,
        currentStep: Int?,
        cycleIteration: Int?,
        anticipationRange: Range<Int>?
    ) {
        self.config = config
        self.currentStep = currentStep
        self.cycleIteration = cycleIteration
        self.anticipationRange = anticipationRange
    }
}
