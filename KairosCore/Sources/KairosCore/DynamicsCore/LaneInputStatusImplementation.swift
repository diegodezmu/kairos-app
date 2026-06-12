import Foundation

enum LaneSignalStateEvaluator {
    static func evaluate(
        lane: LaneID,
        previousState: LaneSignalState,
        laneEnabled: Bool,
        maxRMSAmplitude: Float,
        clipDetectedNow: Bool,
        millisecondsSinceLastAboveFloor: UInt64,
        millisecondsSinceLastClip: UInt64,
        channelLabel: String
    ) -> LaneInputStatus {
        let state = resolveState(
            previousState: previousState,
            laneEnabled: laneEnabled,
            maxRMSAmplitude: maxRMSAmplitude,
            clipDetectedNow: clipDetectedNow,
            millisecondsSinceLastAboveFloor: millisecondsSinceLastAboveFloor,
            millisecondsSinceLastClip: millisecondsSinceLastClip
        )

        return LaneInputStatus(
            lane: lane,
            state: state,
            channelLabel: channelLabel,
            displayLabel: displayLabel(for: state, channelLabel: channelLabel)
        )
    }

    private static func resolveState(
        previousState: LaneSignalState,
        laneEnabled: Bool,
        maxRMSAmplitude: Float,
        clipDetectedNow: Bool,
        millisecondsSinceLastAboveFloor: UInt64,
        millisecondsSinceLastClip: UInt64
    ) -> LaneSignalState {
        guard laneEnabled else {
            return .disabled
        }

        if clipDetectedNow || millisecondsSinceLastClip < dynamicsClipHoldDurationMilliseconds {
            return .clipping
        }

        if maxRMSAmplitude > laneSignalFloorAmplitude {
            return .receiving
        }

        if millisecondsSinceLastAboveFloor >= laneSignalDebounceMilliseconds {
            return .noSignal
        }

        switch previousState {
        case .disabled, .noSignal:
            return .noSignal
        case .receiving, .clipping:
            return .receiving
        }
    }

    private static func displayLabel(
        for state: LaneSignalState,
        channelLabel: String
    ) -> String {
        switch state {
        case .disabled:
            return ""
        case .noSignal:
            return "No signal"
        case .receiving:
            return channelLabel
        case .clipping:
            return "Clipping"
        }
    }
}

/// Stateful evaluator that applies the LaneInputStatus contract across samples.
public struct LaneInputStatusMachine: Sendable {
    private let lane: LaneID
    private let channelLabel: String
    public private(set) var laneEnabled: Bool
    public private(set) var currentStatus: LaneInputStatus
    private var lastAboveFloorMilliseconds: UInt64?
    private var lastClipMilliseconds: UInt64?

    public init(
        lane: LaneID,
        channelLabel: String,
        laneEnabled: Bool = false
    ) {
        self.lane = lane
        self.channelLabel = channelLabel
        self.laneEnabled = laneEnabled
        let initialState: LaneSignalState = laneEnabled ? .noSignal : .disabled
        self.currentStatus = LaneInputStatus(
            lane: lane,
            state: initialState,
            channelLabel: channelLabel,
            displayLabel: initialState == .receiving ? channelLabel : initialState == .disabled ? "" : "No signal"
        )
    }

    public mutating func setEnabled(_ enabled: Bool) {
        guard enabled != laneEnabled else {
            return
        }

        laneEnabled = enabled
        lastAboveFloorMilliseconds = nil
        lastClipMilliseconds = nil
        let state: LaneSignalState = enabled ? .noSignal : .disabled
        currentStatus = LaneSignalStateEvaluator.evaluate(
            lane: lane,
            previousState: state,
            laneEnabled: enabled,
            maxRMSAmplitude: 0,
            clipDetectedNow: false,
            millisecondsSinceLastAboveFloor: .max,
            millisecondsSinceLastClip: .max,
            channelLabel: channelLabel
        )
    }

    @discardableResult
    public mutating func consume(
        _ laneSample: LaneDynamicsSample,
        atMilliseconds currentMilliseconds: UInt64
    ) -> LaneInputStatus {
        if laneSample.maximumRMSAmplitude > laneSignalFloorAmplitude {
            lastAboveFloorMilliseconds = currentMilliseconds
        }

        if laneSample.clip {
            lastClipMilliseconds = currentMilliseconds
        }

        let millisecondsSinceLastAboveFloor = elapsedMilliseconds(
            since: lastAboveFloorMilliseconds,
            currentMilliseconds: currentMilliseconds
        )
        let millisecondsSinceLastClip = elapsedMilliseconds(
            since: lastClipMilliseconds,
            currentMilliseconds: currentMilliseconds
        )

        currentStatus = LaneSignalStateEvaluator.evaluate(
            lane: lane,
            previousState: currentStatus.state,
            laneEnabled: laneEnabled,
            maxRMSAmplitude: laneSample.maximumRMSAmplitude,
            clipDetectedNow: laneSample.clip,
            millisecondsSinceLastAboveFloor: millisecondsSinceLastAboveFloor,
            millisecondsSinceLastClip: millisecondsSinceLastClip,
            channelLabel: channelLabel
        )
        return currentStatus
    }

    @discardableResult
    public mutating func consume(_ sample: DynamicsSample) -> LaneInputStatus {
        consume(
            sample.lane(lane),
            atMilliseconds: dynamicsTimelineMilliseconds(
                sampleTime: sample.sampleTime,
                sampleRate: sample.sampleRate
            )
        )
    }

    private func elapsedMilliseconds(
        since previousMilliseconds: UInt64?,
        currentMilliseconds: UInt64
    ) -> UInt64 {
        guard let previousMilliseconds else {
            return .max
        }

        return currentMilliseconds >= previousMilliseconds
            ? currentMilliseconds - previousMilliseconds
            : 0
    }
}
