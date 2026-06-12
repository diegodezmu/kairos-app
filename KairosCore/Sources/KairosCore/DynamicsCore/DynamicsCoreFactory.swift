import Foundation

/// Public construction namespace for DynamicsCore contract components.
public enum DynamicsCoreFactory {
    public static func makeHistoryBuffer(
        maximumRange: HistoryRange = .twoMinutes
    ) -> any HistoryBuffer {
        DefaultHistoryBuffer(maximumRange: maximumRange)
    }

    public static func makeLaneInputStatusMachine(
        lane: LaneID,
        channelLabel: String,
        laneEnabled: Bool = false
    ) -> LaneInputStatusMachine {
        LaneInputStatusMachine(
            lane: lane,
            channelLabel: channelLabel,
            laneEnabled: laneEnabled
        )
    }

    public static func makeDynamicsPublisher(
        localConsumer: (any LocalConsumer)? = nil,
        networkBroadcaster: (any NetworkBroadcaster)? = nil
    ) -> any DynamicsPublisher {
        DefaultDynamicsPublisher(
            localConsumer: localConsumer,
            networkBroadcaster: networkBroadcaster
        )
    }

    public static func makeClipDetector() -> any ClipDetector {
        DefaultClipDetector()
    }

    public static func makeRMSPeakMeter() -> any RMSPeakMeasuring {
        DefaultRMSPeakMeter()
    }

    public static func makeDynamicsMeter() -> DynamicsMeter {
        DynamicsMeter()
    }
}
