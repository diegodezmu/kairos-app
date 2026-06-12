import Foundation

/// Public construction namespace for TimeDomain contract components.
public enum TimeDomainFactory {
    public static func makeCycleEngine() -> any CycleEngine {
        DefaultCycleEngine()
    }

    public static func makeResetDetector() -> any ResetDetector {
        DefaultResetDetector()
    }

    public static func makeOffset(milliseconds: Double = 0.0) -> Offset {
        Offset(milliseconds: milliseconds)
    }

    public static func makeOriginLatch(frozenOriginBeat: Double? = nil) -> OriginLatch {
        OriginLatch(frozenOriginBeat: frozenOriginBeat)
    }

    public static func makeInternalClock(
        tempo: Double = 120.0,
        quantum: Double = 4.0,
        hostTimeUnitsPerSecond: Double = 1_000_000_000.0
    ) -> InternalClock {
        InternalClock(
            tempo: tempo,
            quantum: quantum,
            hostTimeUnitsPerSecond: hostTimeUnitsPerSecond
        )
    }

    public static func makeMIDIClock(
        tempo: Double = 120.0,
        beat: Double = 0.0,
        isPlaying: Bool = false,
        quantum: Double = 4.0,
        originHostTime: UInt64? = nil,
        hasOrigin: Bool = false,
        hostTime: UInt64 = 0,
        hostTimeUnitsPerSecond: Double = 1_000_000_000.0
    ) -> MIDIClock {
        MIDIClock(
            snapshot: makeExternalClockSnapshot(
                tempo: tempo,
                beat: beat,
                isPlaying: isPlaying,
                quantum: quantum,
                originHostTime: originHostTime,
                hasOrigin: hasOrigin,
                hostTime: hostTime
            ),
            hostTimeUnitsPerSecond: hostTimeUnitsPerSecond
        )
    }

    public static func makeAbletonLinkClock(
        tempo: Double = 120.0,
        beat: Double = 0.0,
        isPlaying: Bool = false,
        quantum: Double = 4.0,
        originHostTime: UInt64? = nil,
        hasOrigin: Bool = false,
        hostTime: UInt64 = 0,
        hostTimeUnitsPerSecond: Double = 1_000_000_000.0
    ) -> AbletonLinkClock {
        AbletonLinkClock(
            snapshot: makeExternalClockSnapshot(
                tempo: tempo,
                beat: beat,
                isPlaying: isPlaying,
                quantum: quantum,
                originHostTime: originHostTime,
                hasOrigin: hasOrigin,
                hostTime: hostTime
            ),
            hostTimeUnitsPerSecond: hostTimeUnitsPerSecond
        )
    }

    private static func makeExternalClockSnapshot(
        tempo: Double,
        beat: Double,
        isPlaying: Bool,
        quantum: Double,
        originHostTime: UInt64?,
        hasOrigin: Bool,
        hostTime: UInt64
    ) -> ExternalClockSnapshot {
        ExternalClockSnapshot(
            tempo: tempo,
            beat: beat,
            isPlaying: isPlaying,
            quantum: quantum,
            originHostTime: originHostTime,
            hasOrigin: hasOrigin,
            hostTime: hostTime
        )
    }
}
