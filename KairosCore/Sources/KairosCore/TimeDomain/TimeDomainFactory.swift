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
}
