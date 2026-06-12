import Foundation

/// Default deterministic cycle resolver for the frozen TimeDomain contract.
struct DefaultCycleEngine: CycleEngine {
    func resolveState(
        for config: CycleConfig,
        beat: Double,
        frozenOriginBeat: Double?
    ) -> CycleState {
        let anticipationRange = Self.anticipationRange(for: config.stepNumber)

        guard let frozenOriginBeat else {
            return CycleState(
                config: config,
                currentStep: nil,
                cycleIteration: nil,
                anticipationRange: anticipationRange
            )
        }

        let stepNumber = config.stepNumber.rawValue
        let elapsedBeats = beat - frozenOriginBeat
        let stepFloat = elapsedBeats / config.pulse.stepDurationBeats
        let wrappedStepIndex = Int(floor(stepFloat))
        let currentStep = positiveModulo(wrappedStepIndex, stepNumber)
        let cycleIteration = Int(floor(stepFloat / Double(stepNumber)))

        return CycleState(
            config: config,
            currentStep: currentStep,
            cycleIteration: cycleIteration,
            anticipationRange: anticipationRange
        )
    }

    func resolveStates(
        for configs: [CycleConfig],
        beat: Double,
        frozenOriginBeat: Double?
    ) -> [CycleState] {
        configs.map { resolveState(for: $0, beat: beat, frozenOriginBeat: frozenOriginBeat) }
    }

    static func anticipationRange(for stepNumber: StepNumber) -> Range<Int>? {
        switch stepNumber {
        case .one, .two, .four:
            return nil
        case .eight:
            return 7..<8
        case .sixteen:
            return 12..<16
        case .thirtyTwo:
            return 28..<32
        case .sixtyFour:
            return 60..<64
        case .oneHundredTwentyEight:
            return 120..<128
        }
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
