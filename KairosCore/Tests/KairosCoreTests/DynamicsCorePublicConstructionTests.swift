import XCTest
import KairosCore

final class DynamicsCorePublicConstructionTests: XCTestCase {
    func testHistoryBufferIsConstructibleViaFactory() {
        let buffer = DynamicsCoreFactory.makeHistoryBuffer(maximumRange: .tenSeconds)
        let sample = makeDynamicsSample(
            hostTime: 1_000,
            sampleTime: 1,
            lane1: makeLaneSample(rmsLeft: 0.25, rmsRight: 0.5)
        )

        buffer.append(sample)

        let snapshot = buffer.snapshot(for: .one, range: .tenSeconds, columnCount: 1)
        XCTAssertEqual(snapshot.buckets.count, 1)
        XCTAssertEqual(snapshot.buckets[0].meanRMSLeft, 0.25, accuracy: 0.000_1)
        XCTAssertEqual(snapshot.buckets[0].meanRMSRight, 0.5, accuracy: 0.000_1)
    }

    func testLaneInputStatusMachineIsConstructibleViaFactory() {
        var machine = DynamicsCoreFactory.makeLaneInputStatusMachine(
            lane: .one,
            channelLabel: "BlackHole 1-2"
        )

        XCTAssertEqual(machine.currentStatus.state, .disabled)

        machine.setEnabled(true)
        let status = machine.consume(
            makeLaneSample(rmsLeft: 0.01, rmsRight: 0.004),
            atMilliseconds: 0
        )

        XCTAssertEqual(machine.laneEnabled, true)
        XCTAssertEqual(status.state, .receiving)
        XCTAssertEqual(status.displayLabel, "BlackHole 1-2")
    }

    func testClipDetectorIsConstructibleViaFactory() {
        let detector = DynamicsCoreFactory.makeClipDetector()

        let clip = detector.detectClipping(leftPeak: 0.5, rightPeak: 1.01)

        XCTAssertFalse(clip.left)
        XCTAssertTrue(clip.right)
    }
}

private func makeLaneSample(
    rmsLeft: Float,
    rmsRight: Float,
    peakLeft: Float? = nil,
    peakRight: Float? = nil,
    clipLeft: Bool = false,
    clipRight: Bool = false
) -> LaneDynamicsSample {
    LaneDynamicsSample(
        rmsLeft: rmsLeft,
        rmsRight: rmsRight,
        peakLeft: peakLeft ?? rmsLeft,
        peakRight: peakRight ?? rmsRight,
        clipLeft: clipLeft,
        clipRight: clipRight
    )
}

private func makeDynamicsSample(
    hostTime: UInt64,
    sampleTime: Int64,
    sampleRate: Double = 1,
    lane1: LaneDynamicsSample,
    lane2: LaneDynamicsSample = LaneDynamicsSample(
        rmsLeft: 0,
        rmsRight: 0,
        peakLeft: 0,
        peakRight: 0,
        clipLeft: false,
        clipRight: false
    ),
    lane3: LaneDynamicsSample = LaneDynamicsSample(
        rmsLeft: 0,
        rmsRight: 0,
        peakLeft: 0,
        peakRight: 0,
        clipLeft: false,
        clipRight: false
    ),
    lane4: LaneDynamicsSample = LaneDynamicsSample(
        rmsLeft: 0,
        rmsRight: 0,
        peakLeft: 0,
        peakRight: 0,
        clipLeft: false,
        clipRight: false
    )
) -> DynamicsSample {
    DynamicsSample(
        hostTime: hostTime,
        sampleTime: sampleTime,
        frameCount: 1,
        sampleRate: sampleRate,
        lane1: lane1,
        lane2: lane2,
        lane3: lane3,
        lane4: lane4
    )
}
