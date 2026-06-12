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

    func testOffsetAndOriginLatchAreConstructibleViaFactory() throws {
        let offset = TimeDomainFactory.makeOffset(milliseconds: 125.0)
        var latch = TimeDomainFactory.makeOriginLatch()
        let clock = TimeDomainFactory.makeMIDIClock(
            tempo: 120.0,
            beat: 20.0,
            isPlaying: true,
            quantum: 4.0,
            originHostTime: 1_000,
            hasOrigin: true,
            hostTime: 2_000,
            hostTimeUnitsPerSecond: 1_000.0
        )

        XCTAssertEqual(offset.beats(atTempo: 120.0), 0.25, accuracy: 0.000_000_1)
        let frozenOriginBeat = try XCTUnwrap(latch.observe(clock: clock))
        XCTAssertEqual(frozenOriginBeat, 18.0, accuracy: 0.000_000_1)
        XCTAssertEqual(try XCTUnwrap(latch.frozenOriginBeat), 18.0, accuracy: 0.000_000_1)

        latch.reset()
        XCTAssertNil(latch.frozenOriginBeat)
    }

    func testClocksAreConstructibleViaFactory() {
        let internalClock = TimeDomainFactory.makeInternalClock(
            tempo: 98.0,
            quantum: 8.0,
            hostTimeUnitsPerSecond: 1_000.0
        )
        let midiClock = TimeDomainFactory.makeMIDIClock(
            tempo: 120.0,
            beat: 8.0,
            isPlaying: true,
            quantum: 4.0,
            originHostTime: 500,
            hasOrigin: true,
            hostTime: 1_000,
            hostTimeUnitsPerSecond: 1_000.0
        )
        let linkClock = TimeDomainFactory.makeAbletonLinkClock(
            tempo: 90.0,
            beat: 4.0,
            isPlaying: true,
            quantum: 8.0,
            originHostTime: nil,
            hasOrigin: false,
            hostTime: 2_000,
            hostTimeUnitsPerSecond: 1_000.0
        )

        XCTAssertEqual(internalClock.tempo, 98.0, accuracy: 0.000_000_1)
        XCTAssertEqual(internalClock.quantum, 8.0, accuracy: 0.000_000_1)
        XCTAssertFalse(internalClock.hasOrigin)

        XCTAssertEqual(midiClock.beat(atHostTime: 2_000), 10.0, accuracy: 0.000_000_1)
        XCTAssertEqual(midiClock.originHostTime, 500)
        XCTAssertTrue(midiClock.hasOrigin)

        XCTAssertNil(linkClock.originHostTime)
        XCTAssertFalse(linkClock.hasOrigin)
        XCTAssertEqual(linkClock.beat(atHostTime: 4_000), 7.0, accuracy: 0.000_000_1)
    }
}
