import XCTest
@testable import KairosCore

final class TimeDomainRuntimeTests: XCTestCase {
    func testOriginLatchFreezesOriginBeatAcrossTempoChange() {
        let engine = DefaultCycleEngine()
        var latch = OriginLatch()
        let clock = TestClock(
            tempo: 120.0,
            beatResolver: { hostTime in
                switch hostTime {
                case 1_000:
                    return 100.0
                case 2_500:
                    return 133.5
                default:
                    return 0
                }
            },
            isPlaying: true,
            quantum: 4.0,
            originHostTime: 1_000,
            hasOrigin: true
        )

        let initialOriginBeat = latch.observe(clock: clock)
        let preTempoState = engine.resolveState(
            for: CycleConfig(slot: .one, stepNumber: .oneHundredTwentyEight, pulse: .oneQuarter),
            beat: clock.beat(atHostTime: 2_500),
            frozenOriginBeat: initialOriginBeat
        )

        XCTAssertEqual(initialOriginBeat, 100.0)
        XCTAssertEqual(preTempoState.currentStep, 6)
        XCTAssertEqual(preTempoState.cycleIteration, 1)

        clock.tempo = 90.0
        clock.beatResolver = { hostTime in
            switch hostTime {
            case 1_000:
                return 108.376_395
            case 3_500:
                return 139.665_991
            default:
                return 0
            }
        }

        let postTempoOriginBeat = latch.observe(clock: clock)
        let postTempoState = engine.resolveState(
            for: CycleConfig(slot: .one, stepNumber: .oneHundredTwentyEight, pulse: .oneQuarter),
            beat: clock.beat(atHostTime: 3_500),
            frozenOriginBeat: postTempoOriginBeat
        )
        let regressedState = engine.resolveState(
            for: CycleConfig(slot: .one, stepNumber: .oneHundredTwentyEight, pulse: .oneQuarter),
            beat: clock.beat(atHostTime: 3_500),
            frozenOriginBeat: clock.beat(atHostTime: 1_000)
        )

        XCTAssertEqual(postTempoOriginBeat, 100.0)
        XCTAssertEqual(postTempoState.currentStep, 30)
        XCTAssertEqual(postTempoState.cycleIteration, 1)
        XCTAssertEqual(regressedState.currentStep, 125)
        XCTAssertEqual(regressedState.cycleIteration, 0)
    }

    func testInternalClockPlaySetsOriginAndTempoChangeStaysContinuous() {
        let clock = InternalClock(tempo: 120.0, quantum: 4.0, hostTimeUnitsPerSecond: 1_000.0)

        XCTAssertFalse(clock.hasOrigin)
        XCTAssertFalse(clock.isPlaying)
        XCTAssertNil(clock.originHostTime)

        clock.play(atHostTime: 1_000)

        XCTAssertTrue(clock.hasOrigin)
        XCTAssertTrue(clock.isPlaying)
        XCTAssertEqual(clock.originHostTime, 1_000)
        XCTAssertEqual(clock.beat(atHostTime: 1_000), 0.0, accuracy: 0.000_000_1)
        XCTAssertEqual(clock.beat(atHostTime: 2_500), 3.0, accuracy: 0.000_000_1)

        clock.setTempo(90.0, atHostTime: 2_500)

        XCTAssertEqual(clock.tempo, 90.0)
        XCTAssertEqual(clock.beat(atHostTime: 2_500), 3.0, accuracy: 0.000_000_1)
        XCTAssertEqual(clock.beat(atHostTime: 3_500), 4.5, accuracy: 0.000_000_1)

        clock.stop(atHostTime: 3_500)

        XCTAssertFalse(clock.isPlaying)
        XCTAssertEqual(clock.beat(atHostTime: 4_500), 4.5, accuracy: 0.000_000_1)

        clock.reset(atHostTime: 5_000)

        XCTAssertEqual(clock.originHostTime, 5_000)
        XCTAssertEqual(clock.beat(atHostTime: 5_000), 0.0, accuracy: 0.000_000_1)
    }

    func testMIDIClockAcceptsInjectedSnapshots() {
        let clock = MIDIClock(
            snapshot: ExternalClockSnapshot(
                tempo: 120.0,
                beat: 20.0,
                isPlaying: true,
                quantum: 4.0,
                originHostTime: 1_000,
                hasOrigin: true,
                hostTime: 2_000
            ),
            hostTimeUnitsPerSecond: 1_000.0
        )

        XCTAssertEqual(clock.beat(atHostTime: 2_500), 21.0, accuracy: 0.000_000_1)
        XCTAssertEqual(clock.originHostTime, 1_000)
        XCTAssertTrue(clock.hasOrigin)

        clock.update(
            with: ExternalClockSnapshot(
                tempo: 90.0,
                beat: 23.0,
                isPlaying: true,
                quantum: 4.0,
                originHostTime: 1_000,
                hasOrigin: true,
                hostTime: 4_000
            )
        )

        XCTAssertEqual(clock.beat(atHostTime: 5_000), 24.5, accuracy: 0.000_000_1)
    }

    func testAbletonLinkClockCanAdoptSharedOrigin() {
        let clock = AbletonLinkClock(
            snapshot: ExternalClockSnapshot(
                tempo: 120.0,
                beat: 8.5,
                isPlaying: true,
                quantum: 4.0,
                originHostTime: nil,
                hasOrigin: false,
                hostTime: 2_000
            ),
            hostTimeUnitsPerSecond: 1_000.0
        )

        XCTAssertNil(clock.originHostTime)
        XCTAssertFalse(clock.hasOrigin)

        clock.adoptSharedOrigin(hostTime: 500)

        XCTAssertEqual(clock.originHostTime, 500)
        XCTAssertTrue(clock.hasOrigin)
        XCTAssertEqual(clock.beat(atHostTime: 2_500), 9.5, accuracy: 0.000_000_1)
    }
}

private final class TestClock: ClockSource, @unchecked Sendable {
    var tempo: Double
    var beatResolver: (UInt64) -> Double
    var isPlaying: Bool
    var quantum: Double
    var originHostTime: UInt64?
    var hasOrigin: Bool

    init(
        tempo: Double,
        beatResolver: @escaping (UInt64) -> Double,
        isPlaying: Bool,
        quantum: Double,
        originHostTime: UInt64?,
        hasOrigin: Bool
    ) {
        self.tempo = tempo
        self.beatResolver = beatResolver
        self.isPlaying = isPlaying
        self.quantum = quantum
        self.originHostTime = originHostTime
        self.hasOrigin = hasOrigin
    }

    func beat(atHostTime hostTime: UInt64) -> Double {
        beatResolver(hostTime)
    }

    func adoptSharedOrigin(hostTime: UInt64) {
        originHostTime = hostTime
        hasOrigin = true
    }
}
