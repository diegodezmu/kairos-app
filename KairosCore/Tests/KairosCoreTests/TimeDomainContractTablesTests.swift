import XCTest
@testable import KairosCore

final class TimeDomainContractTablesTests: XCTestCase {
    func testSection531_currentStepAndCycleIterationTable() throws {
        let cases: [PositionTableRow] = [
            .init(
                name: "origin beat starts at step zero",
                stepNumber: .sixteen,
                pulse: .oneQuarter,
                beat: 100.0,
                frozenOriginBeat: 100.0,
                expectedCurrentStep: 0,
                expectedCycleIteration: 0
            ),
            .init(
                name: "fractional beat floors inside first iteration",
                stepNumber: .sixteen,
                pulse: .oneQuarter,
                beat: 103.99,
                frozenOriginBeat: 100.0,
                expectedCurrentStep: 15,
                expectedCycleIteration: 0
            ),
            .init(
                name: "exact cycle wrap returns to step zero on next iteration",
                stepNumber: .sixteen,
                pulse: .oneQuarter,
                beat: 104.0,
                frozenOriginBeat: 100.0,
                expectedCurrentStep: 0,
                expectedCycleIteration: 1
            ),
            .init(
                name: "whole-beat pulse keeps zero-based modulo",
                stepNumber: .eight,
                pulse: .one,
                beat: 110.5,
                frozenOriginBeat: 100.0,
                expectedCurrentStep: 2,
                expectedCycleIteration: 1
            ),
            .init(
                name: "post-tempo sample stays continuous with frozen origin beat",
                stepNumber: .oneHundredTwentyEight,
                pulse: .oneQuarter,
                beat: 139.665_991,
                frozenOriginBeat: 100.0,
                expectedCurrentStep: 30,
                expectedCycleIteration: 1
            ),
            .init(
                name: "longer pulse still advances iterations deterministically",
                stepNumber: .four,
                pulse: .two,
                beat: 124.0,
                frozenOriginBeat: 100.0,
                expectedCurrentStep: 0,
                expectedCycleIteration: 3
            ),
        ]

        XCTAssertEqual(cases.count, 6)
        throw XCTSkip("F1-SPEC freeze only. Implement CycleEngine table runner in F1-TD.")
    }

    func testSection551_resetDetectionTable() throws {
        let cases: [ResetTableRow] = [
            .init(
                name: "general reset marks every active cycle when all wrap together",
                previous: [
                    .state(slot: .one, stepNumber: .sixteen, pulse: .oneQuarter, currentStep: 15, cycleIteration: 0),
                    .state(slot: .two, stepNumber: .four, pulse: .one, currentStep: 3, cycleIteration: 1),
                ],
                current: [
                    .state(slot: .one, stepNumber: .sixteen, pulse: .oneQuarter, currentStep: 0, cycleIteration: 1),
                    .state(slot: .two, stepNumber: .four, pulse: .one, currentStep: 0, cycleIteration: 2),
                ],
                expectedMarks: [
                    .init(slot: .one, mark: .general),
                    .init(slot: .two, mark: .general),
                ]
            ),
            .init(
                name: "combined reset marks only the cycles that wrap together",
                previous: [
                    .state(slot: .one, stepNumber: .eight, pulse: .oneQuarter, currentStep: 7, cycleIteration: 0),
                    .state(slot: .two, stepNumber: .eight, pulse: .oneQuarter, currentStep: 7, cycleIteration: 2),
                    .state(slot: .three, stepNumber: .four, pulse: .one, currentStep: 1, cycleIteration: 4),
                ],
                current: [
                    .state(slot: .one, stepNumber: .eight, pulse: .oneQuarter, currentStep: 0, cycleIteration: 1),
                    .state(slot: .two, stepNumber: .eight, pulse: .oneQuarter, currentStep: 0, cycleIteration: 3),
                    .state(slot: .three, stepNumber: .four, pulse: .one, currentStep: 2, cycleIteration: 4),
                ],
                expectedMarks: [
                    .init(slot: .one, mark: .combined),
                    .init(slot: .two, mark: .combined),
                    .init(slot: .three, mark: .none),
                ]
            ),
            .init(
                name: "single-cycle wrap does not produce combined or general emphasis",
                previous: [
                    .state(slot: .one, stepNumber: .four, pulse: .one, currentStep: 3, cycleIteration: 0),
                    .state(slot: .two, stepNumber: .four, pulse: .one, currentStep: 1, cycleIteration: 0),
                ],
                current: [
                    .state(slot: .one, stepNumber: .four, pulse: .one, currentStep: 0, cycleIteration: 1),
                    .state(slot: .two, stepNumber: .four, pulse: .one, currentStep: 2, cycleIteration: 0),
                ],
                expectedMarks: [
                    .init(slot: .one, mark: .none),
                    .init(slot: .two, mark: .none),
                ]
            ),
        ]

        XCTAssertEqual(cases.count, 3)
        throw XCTSkip("F1-SPEC freeze only. Implement ResetDetector table runner in F1-TD.")
    }

    func testSection552_anticipationTable() throws {
        let cases: [AnticipationTableRow] = [
            .init(stepNumber: .one, expectedRange: nil),
            .init(stepNumber: .two, expectedRange: nil),
            .init(stepNumber: .four, expectedRange: nil),
            .init(stepNumber: .eight, expectedRange: 7..<8),
            .init(stepNumber: .sixteen, expectedRange: 12..<16),
            .init(stepNumber: .thirtyTwo, expectedRange: 28..<32),
            .init(stepNumber: .sixtyFour, expectedRange: 60..<64),
            .init(stepNumber: .oneHundredTwentyEight, expectedRange: 120..<128),
        ]

        XCTAssertEqual(cases.count, 8)
        throw XCTSkip("F1-SPEC freeze only. Implement anticipation lookup in F1-TD.")
    }

    func testSection56_offsetConversionTable() throws {
        let cases: [OffsetConversionTableRow] = [
            .init(offsetMilliseconds: 200.0, tempo: 120.0, expectedOffsetBeats: 0.4),
            .init(offsetMilliseconds: -50.0, tempo: 90.0, expectedOffsetBeats: -0.075),
            .init(offsetMilliseconds: 125.0, tempo: 60.0, expectedOffsetBeats: 0.125),
            .init(offsetMilliseconds: -200.0, tempo: 180.0, expectedOffsetBeats: -0.6),
        ]

        XCTAssertEqual(cases.count, 4)
        throw XCTSkip("F1-SPEC freeze only. Implement Offset conversion in F1-TD.")
    }
}

private struct PositionTableRow {
    var name: String
    var stepNumber: StepNumber
    var pulse: Pulse
    var beat: Double
    var frozenOriginBeat: Double
    var expectedCurrentStep: Int
    var expectedCycleIteration: Int
}

private struct ResetTableRow {
    var name: String
    var previous: [CycleState]
    var current: [CycleState]
    var expectedMarks: [CycleResetState]
}

private struct AnticipationTableRow {
    var stepNumber: StepNumber
    var expectedRange: Range<Int>?
}

private struct OffsetConversionTableRow {
    var offsetMilliseconds: Double
    var tempo: Double
    var expectedOffsetBeats: Double
}

private extension CycleState {
    static func state(
        slot: CycleSlot,
        stepNumber: StepNumber,
        pulse: Pulse,
        currentStep: Int?,
        cycleIteration: Int?
    ) -> CycleState {
        CycleState(
            config: CycleConfig(slot: slot, stepNumber: stepNumber, pulse: pulse),
            currentStep: currentStep,
            cycleIteration: cycleIteration,
            anticipationRange: nil
        )
    }
}
