import XCTest
@testable import KairosCore

final class DynamicsCoreRuntimeTests: XCTestCase {
    func testClipDetectorKeepsPerChannelTailForTwoSeconds() {
        let clock = TestMillisecondsClock()
        let detector = DefaultClipDetector(nowMilliseconds: { clock.now })

        let initial = detector.detectClipping(leftPeak: 0.5, rightPeak: 1.01)
        XCTAssertFalse(initial.left)
        XCTAssertTrue(initial.right)

        clock.now = 1_000
        let held = detector.detectClipping(leftPeak: 0.1, rightPeak: 0.1)
        XCTAssertFalse(held.left)
        XCTAssertTrue(held.right)
        XCTAssertEqual(detector.tailProgress(atMilliseconds: clock.now).right, 0.5, accuracy: 0.000_1)

        clock.now = 2_000
        let expired = detector.detectClipping(leftPeak: 0.1, rightPeak: 0.1)
        XCTAssertFalse(expired.left)
        XCTAssertFalse(expired.right)
        XCTAssertEqual(detector.tailProgress(atMilliseconds: clock.now).right, 0, accuracy: 0.000_1)
    }

    func testHistoryBufferAggregatesMinMaxMeanByColumn() {
        let buffer = DefaultHistoryBuffer()
        let points: [(UInt64, Int64, Float, Float)] = [
            (0, 0, 0.1, 0.6),
            (2_000, 2, 0.2, 0.5),
            (4_000, 4, 0.3, 0.4),
            (6_000, 6, 0.4, 0.3),
            (8_000, 8, 0.5, 0.2),
            (10_000, 10, 0.6, 0.1),
        ]

        for point in points {
            buffer.append(
                makeDynamicsSample(
                    hostTime: point.0,
                    sampleTime: point.1,
                    lane1: makeLaneSample(rmsLeft: point.2, rmsRight: point.3)
                )
            )
        }

        let snapshot = buffer.snapshot(for: .one, range: .tenSeconds, columnCount: 2)
        XCTAssertEqual(snapshot.buckets.count, 2)

        let firstBucket = snapshot.buckets[0]
        XCTAssertEqual(firstBucket.startHostTime, 0)
        XCTAssertEqual(firstBucket.endHostTime, 4_000)
        XCTAssertEqual(firstBucket.minimumRMSLeft, 0.1, accuracy: 0.000_1)
        XCTAssertEqual(firstBucket.maximumRMSLeft, 0.3, accuracy: 0.000_1)
        XCTAssertEqual(firstBucket.meanRMSLeft, 0.2, accuracy: 0.000_1)
        XCTAssertEqual(firstBucket.minimumRMSRight, 0.4, accuracy: 0.000_1)
        XCTAssertEqual(firstBucket.maximumRMSRight, 0.6, accuracy: 0.000_1)
        XCTAssertEqual(firstBucket.meanRMSRight, 0.5, accuracy: 0.000_1)

        let secondBucket = snapshot.buckets[1]
        XCTAssertEqual(secondBucket.startHostTime, 6_000)
        XCTAssertEqual(secondBucket.endHostTime, 10_000)
        XCTAssertEqual(secondBucket.minimumRMSLeft, 0.4, accuracy: 0.000_1)
        XCTAssertEqual(secondBucket.maximumRMSLeft, 0.6, accuracy: 0.000_1)
        XCTAssertEqual(secondBucket.meanRMSLeft, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(secondBucket.minimumRMSRight, 0.1, accuracy: 0.000_1)
        XCTAssertEqual(secondBucket.maximumRMSRight, 0.3, accuracy: 0.000_1)
        XCTAssertEqual(secondBucket.meanRMSRight, 0.2, accuracy: 0.000_1)
    }

    func testHistoryBufferKeepsClosedBucketsStableWhileHistoryScrolls() {
        let buffer = DefaultHistoryBuffer()

        for second in 0...10 {
            buffer.append(
                makeDynamicsSample(
                    hostTime: UInt64(second * 1_000),
                    sampleTime: Int64(second),
                    lane1: makeLaneSample(
                        rmsLeft: second <= 5 ? 0.1 : 0.9,
                        rmsRight: 0.2
                    )
                )
            )
        }

        let initialSnapshot = buffer.snapshot(for: .one, range: .tenSeconds, columnCount: 2)
        XCTAssertEqual(initialSnapshot.buckets.count, 2)
        XCTAssertEqual(initialSnapshot.buckets[0].meanRMSLeft, 0.1, accuracy: 0.000_1)
        XCTAssertEqual(initialSnapshot.buckets[1].meanRMSLeft, 0.9, accuracy: 0.000_1)

        for second in 11...12 {
            buffer.append(
                makeDynamicsSample(
                    hostTime: UInt64(second * 1_000),
                    sampleTime: Int64(second),
                    lane1: makeLaneSample(rmsLeft: 0.9, rmsRight: 0.2)
                )
            )
        }

        let scrolledSnapshot = buffer.snapshot(for: .one, range: .tenSeconds, columnCount: 2)
        XCTAssertEqual(scrolledSnapshot.buckets.count, 3)
        XCTAssertEqual(scrolledSnapshot.buckets[0].startHostTime, 0)
        XCTAssertEqual(scrolledSnapshot.buckets[0].endHostTime, 5_000)
        XCTAssertEqual(scrolledSnapshot.buckets[0].meanRMSLeft, 0.1, accuracy: 0.000_1)
        XCTAssertEqual(scrolledSnapshot.buckets[1].meanRMSLeft, 0.9, accuracy: 0.000_1)
        XCTAssertEqual(scrolledSnapshot.buckets[2].meanRMSLeft, 0.9, accuracy: 0.000_1)
    }

    func testHistoryBufferRespectsAllContractRanges() {
        let buffer = DefaultHistoryBuffer()

        for second in stride(from: 0, through: 120, by: 10) {
            buffer.append(
                makeDynamicsSample(
                    hostTime: UInt64(second * 1_000),
                    sampleTime: Int64(second),
                    lane1: makeLaneSample(rmsLeft: Float(second) / 100, rmsRight: Float(second) / 200)
                )
            )
        }

        XCTAssertEqual(
            buffer.snapshot(for: .one, range: .tenSeconds, columnCount: 200).buckets.map(\.startHostTime),
            [110_000, 120_000]
        )
        XCTAssertEqual(
            buffer.snapshot(for: .one, range: .thirtySeconds, columnCount: 200).buckets.map(\.startHostTime),
            [90_000, 100_000, 110_000, 120_000]
        )
        XCTAssertEqual(
            buffer.snapshot(for: .one, range: .oneMinute, columnCount: 200).buckets.map(\.startHostTime),
            [60_000, 70_000, 80_000, 90_000, 100_000, 110_000, 120_000]
        )
        XCTAssertEqual(
            buffer.snapshot(for: .one, range: .twoMinutes, columnCount: 400).buckets.map(\.startHostTime),
            [0, 10_000, 20_000, 30_000, 40_000, 50_000, 60_000, 70_000, 80_000, 90_000, 100_000, 110_000, 120_000]
        )
    }

    func testLaneInputStatusMachineBootstrapDebounceAndClipPrecedence() {
        var machine = LaneInputStatusMachine(lane: .one, channelLabel: "Source 1")

        XCTAssertEqual(machine.currentStatus.state, .disabled)
        XCTAssertEqual(machine.currentStatus.displayLabel, "")

        machine.setEnabled(true)
        XCTAssertEqual(machine.currentStatus.state, .noSignal)
        XCTAssertEqual(machine.currentStatus.displayLabel, "No signal")

        XCTAssertEqual(
            machine.consume(makeLaneSample(rmsLeft: 0.01, rmsRight: 0.004), atMilliseconds: 0).state,
            .receiving
        )
        XCTAssertEqual(
            machine.consume(makeLaneSample(rmsLeft: 0.000_3, rmsRight: 0.000_3), atMilliseconds: 1_999).state,
            .receiving
        )

        let noSignal = machine.consume(
            makeLaneSample(rmsLeft: 0.000_3, rmsRight: 0.000_3),
            atMilliseconds: 2_000
        )
        XCTAssertEqual(noSignal.state, .noSignal)
        XCTAssertEqual(noSignal.displayLabel, "No signal")

        let clipping = machine.consume(
            makeLaneSample(rmsLeft: 0.02, rmsRight: 0.03, clipRight: true),
            atMilliseconds: 3_000
        )
        XCTAssertEqual(clipping.state, .clipping)
        XCTAssertEqual(clipping.displayLabel, "Clipping")

        XCTAssertEqual(
            machine.consume(makeLaneSample(rmsLeft: 0.02, rmsRight: 0.03), atMilliseconds: 4_999).state,
            .clipping
        )

        let receiving = machine.consume(
            makeLaneSample(rmsLeft: 0.02, rmsRight: 0.03),
            atMilliseconds: 5_000
        )
        XCTAssertEqual(receiving.state, .receiving)
        XCTAssertEqual(receiving.displayLabel, "Source 1")

        machine.setEnabled(false)
        XCTAssertEqual(machine.currentStatus.state, .disabled)

        machine.setEnabled(true)
        XCTAssertEqual(machine.currentStatus.state, .noSignal)
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
    lane2: LaneDynamicsSample = .zero,
    lane3: LaneDynamicsSample = .zero,
    lane4: LaneDynamicsSample = .zero
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

private final class TestMillisecondsClock: @unchecked Sendable {
    var now: UInt64 = 0
}
