import XCTest
@testable import KairosCore

final class DynamicsCoreContractTablesTests: XCTestCase {
    func testSection772_laneSignalStateTransitionsTable() throws {
        let cases: [LaneSignalTransitionTableRow] = [
            .init(
                name: "disabled lane stays disabled regardless of signal",
                previousState: .disabled,
                laneEnabled: false,
                maxRMSDBFS: -12.0,
                clipDetectedNow: true,
                millisecondsSinceLastAboveFloor: 0,
                millisecondsSinceLastClip: 0,
                expectedState: .disabled,
                expectedDisplayLabel: ""
            ),
            .init(
                name: "healthy signal shows receiving",
                previousState: .noSignal,
                laneEnabled: true,
                maxRMSDBFS: -24.0,
                clipDetectedNow: false,
                millisecondsSinceLastAboveFloor: 0,
                millisecondsSinceLastClip: 5_000,
                expectedState: .receiving,
                expectedDisplayLabel: "Source 1"
            ),
            .init(
                name: "silence below floor does not fall to noSignal before 2 seconds",
                previousState: .receiving,
                laneEnabled: true,
                maxRMSDBFS: -70.0,
                clipDetectedNow: false,
                millisecondsSinceLastAboveFloor: 1_500,
                millisecondsSinceLastClip: 5_000,
                expectedState: .receiving,
                expectedDisplayLabel: "Source 1"
            ),
            .init(
                name: "silence below floor for 2 seconds becomes noSignal",
                previousState: .receiving,
                laneEnabled: true,
                maxRMSDBFS: -70.0,
                clipDetectedNow: false,
                millisecondsSinceLastAboveFloor: 2_000,
                millisecondsSinceLastClip: 5_000,
                expectedState: .noSignal,
                expectedDisplayLabel: "No signal"
            ),
            .init(
                name: "quiet but valid bus at minus fifty stays receiving",
                previousState: .receiving,
                laneEnabled: true,
                maxRMSDBFS: -50.0,
                clipDetectedNow: false,
                millisecondsSinceLastAboveFloor: 0,
                millisecondsSinceLastClip: 5_000,
                expectedState: .receiving,
                expectedDisplayLabel: "Source 1"
            ),
            .init(
                name: "fresh clip takes precedence immediately",
                previousState: .receiving,
                laneEnabled: true,
                maxRMSDBFS: -9.0,
                clipDetectedNow: true,
                millisecondsSinceLastAboveFloor: 0,
                millisecondsSinceLastClip: 0,
                expectedState: .clipping,
                expectedDisplayLabel: "Clipping"
            ),
            .init(
                name: "clip hold keeps clipping for almost two seconds after peak clears",
                previousState: .clipping,
                laneEnabled: true,
                maxRMSDBFS: -18.0,
                clipDetectedNow: false,
                millisecondsSinceLastAboveFloor: 0,
                millisecondsSinceLastClip: 1_999,
                expectedState: .clipping,
                expectedDisplayLabel: "Clipping"
            ),
            .init(
                name: "after clip hold expires a healthy signal returns to receiving",
                previousState: .clipping,
                laneEnabled: true,
                maxRMSDBFS: -18.0,
                clipDetectedNow: false,
                millisecondsSinceLastAboveFloor: 0,
                millisecondsSinceLastClip: 2_000,
                expectedState: .receiving,
                expectedDisplayLabel: "Source 1"
            ),
            .init(
                name: "after clip hold expires and silence debounce is also met, state falls to noSignal",
                previousState: .clipping,
                laneEnabled: true,
                maxRMSDBFS: -70.0,
                clipDetectedNow: false,
                millisecondsSinceLastAboveFloor: 2_000,
                millisecondsSinceLastClip: 2_000,
                expectedState: .noSignal,
                expectedDisplayLabel: "No signal"
            ),
        ]

        XCTAssertEqual(cases.count, 9)
        for row in cases {
            let status = LaneSignalStateEvaluator.evaluate(
                lane: .one,
                previousState: row.previousState,
                laneEnabled: row.laneEnabled,
                maxRMSAmplitude: DynamicsDecibelScale.dbfsToAmplitude(row.maxRMSDBFS),
                clipDetectedNow: row.clipDetectedNow,
                millisecondsSinceLastAboveFloor: UInt64(row.millisecondsSinceLastAboveFloor),
                millisecondsSinceLastClip: UInt64(row.millisecondsSinceLastClip),
                channelLabel: "Source 1"
            )

            XCTAssertEqual(status.state, row.expectedState, row.name)
            XCTAssertEqual(status.displayLabel, row.expectedDisplayLabel, row.name)
        }
    }
}

private struct LaneSignalTransitionTableRow {
    var name: String
    var previousState: LaneSignalState
    var laneEnabled: Bool
    var maxRMSDBFS: Float
    var clipDetectedNow: Bool
    var millisecondsSinceLastAboveFloor: Int
    var millisecondsSinceLastClip: Int
    var expectedState: LaneSignalState
    var expectedDisplayLabel: String
}
