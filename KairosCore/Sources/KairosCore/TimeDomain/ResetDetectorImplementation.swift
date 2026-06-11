import Foundation

/// Default reset detector for consecutive deterministic cycle states.
struct DefaultResetDetector: ResetDetector {
    func detectResets(
        previous: [CycleState],
        current: [CycleState]
    ) -> [CycleResetState] {
        let previousBySlot = Dictionary(uniqueKeysWithValues: previous.map { ($0.config.slot, $0) })
        let wrappedSlots = Set(
            current.compactMap { currentState -> CycleSlot? in
                guard
                    let previousState = previousBySlot[currentState.config.slot],
                    let previousIteration = previousState.cycleIteration,
                    let currentIteration = currentState.cycleIteration,
                    let currentStep = currentState.currentStep,
                    currentStep == 0,
                    currentIteration > previousIteration
                else {
                    return nil
                }

                return currentState.config.slot
            }
        )

        let sharedMark: GridResetMark
        switch wrappedSlots.count {
        case let count where current.count >= 2 && count == current.count:
            sharedMark = .general
        case let count where count >= 2:
            sharedMark = .combined
        default:
            sharedMark = .none
        }

        return current.map { currentState in
            let mark: GridResetMark
            if wrappedSlots.contains(currentState.config.slot) {
                mark = sharedMark
            } else {
                mark = .none
            }

            return CycleResetState(slot: currentState.config.slot, mark: mark)
        }
    }
}
