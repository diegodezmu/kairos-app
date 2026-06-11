import XCTest
@testable import KairosCore

final class DynamicsCoreContractTablesTests: XCTestCase {
    func testSection72_rmsPeakAndClipTable() throws {
        let cases: [ChannelMeasurementTableRow] = [
            .init(
                name: "unity constant signal",
                samples: [1.0, 1.0, 1.0, 1.0],
                expectedRMS: 1.0,
                expectedPeak: 1.0,
                expectedClip: false
            ),
            .init(
                name: "half-scale square wave",
                samples: [0.5, -0.5, 0.5, -0.5],
                expectedRMS: 0.5,
                expectedPeak: 0.5,
                expectedClip: false
            ),
            .init(
                name: "silence stays clear",
                samples: [0.0, 0.0, 0.0, 0.0],
                expectedRMS: 0.0,
                expectedPeak: 0.0,
                expectedClip: false
            ),
            .init(
                name: "single over sample clips above 0 dBFS",
                samples: [1.01, 0.0, 0.0, 0.0],
                expectedRMS: 0.505,
                expectedPeak: 1.01,
                expectedClip: true
            ),
        ]

        XCTAssertEqual(cases.count, 4)
        throw XCTSkip("F1-SPEC freeze only. Implement RMS/peak/clip measurement in F1-DC.")
    }

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
                expectedDisplayLabel: "BlackHole 1-2"
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
                expectedDisplayLabel: "BlackHole 1-2"
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
                expectedDisplayLabel: "BlackHole 1-2"
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
                expectedDisplayLabel: "BlackHole 1-2"
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
        throw XCTSkip("F1-SPEC freeze only. Implement LaneSignalState evaluator in F1-DC.")
    }
}

private struct ChannelMeasurementTableRow {
    var name: String
    var samples: [Float]
    var expectedRMS: Float
    var expectedPeak: Float
    var expectedClip: Bool
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
