import XCTest
import KairosCore

final class TimeDomainPublicConstructionTests: XCTestCase {
    func testCycleEngineAndResetDetectorAreConstructibleViaFactory() {
        let engine = TimeDomainFactory.makeCycleEngine()
        let detector = TimeDomainFactory.makeResetDetector()
        let configs = [
            CycleConfig(slot: .one, stepNumber: .four, pulse: .one),
            CycleConfig(slot: .two, stepNumber: .eight, pulse: .oneHalf),
        ]

        let previous = engine.resolveStates(
            for: configs,
            beat: 3.5,
            frozenOriginBeat: 0.0
        )
        let current = engine.resolveStates(
            for: configs,
            beat: 4.0,
            frozenOriginBeat: 0.0
        )

        XCTAssertEqual(current.map(\.currentStep), [1, 2])
        XCTAssertEqual(current.map(\.cycleIteration), [0, 0])
        XCTAssertEqual(
            detector.detectResets(previous: previous, current: current),
            [
                CycleResetState(slot: .one, mark: .none),
                CycleResetState(slot: .two, mark: .none),
            ]
        )
    }

    func testOffsetIsConstructibleViaFactory() {
        let offset = TimeDomainFactory.makeOffset(milliseconds: 125.0)

        XCTAssertEqual(offset.beats(atTempo: 120.0), 0.25, accuracy: 0.000_000_1)
    }
}
