import CoreGraphics
import Foundation
import KairosCore

final class LevelRuntimeDriver {
    private struct LaneBindingState: Equatable {
        let preferredSourceSlot: Int?
        let preferredSourceName: String?
    }

    private let presentationPipeline = LevelPresentationPipeline()
    private let splitColumnCount = 56
    private let expandedColumnCount = 240
    private let maximumHistoryRange: HistoryRange = .twoMinutes

    private var historyBuffers: [LaneID: any HistoryBuffer]
    private var clipDetectors: [LaneID: any ClipDetector]
    private var statusMachines: [LaneID: LaneInputStatusMachine]
    private var laneBindings: [LaneID: LaneBindingState] = [:]
    private var lastAppendedMilliseconds: [LaneID: UInt64] = [:]

    init() {
        historyBuffers = Self.makeHistoryBuffers()
        clipDetectors = Self.makeClipDetectors()
        statusMachines = Self.makeStatusMachines()
    }

    func reset() {
        historyBuffers = Self.makeHistoryBuffers()
        clipDetectors = Self.makeClipDetectors()
        statusMachines = Self.makeStatusMachines()
        laneBindings.removeAll()
        lastAppendedMilliseconds.removeAll()
    }

    func snapshot(
        now: Date,
        elapsedMilliseconds _: UInt64,
        laneConfigurations: [LevelLaneConfiguration],
        telemetry: LevelTelemetrySnapshot
    ) -> LevelPreviewSnapshot {
        let currentMilliseconds = UInt64(
            max((now.timeIntervalSinceReferenceDate * 1_000.0).rounded(), 0)
        )
        let timestamp = now.timeIntervalSinceReferenceDate

        let configurationsByLane = Dictionary(
            uniqueKeysWithValues: laneConfigurations.map { ($0.lane, $0) }
        )

        var statuses: [LaneID: LaneInputStatus] = [:]
        var laneSamples: [LaneID: LaneDynamicsSample] = [:]
        var splitInputs: [LevelLaneInput] = []
        var expandedInput: LevelLaneInput?

        let enabledLanes = laneConfigurations
            .filter(\.isEnabled)
            .sorted { $0.lane.rawValue < $1.lane.rawValue }

        for lane in LaneID.allCases {
            let configuration = configurationsByLane[lane]
                ?? LevelLaneConfiguration(
                    lane: lane,
                    isEnabled: false,
                    name: "",
                    targetLevelDB: SettingsDefaults.defaultTargetLevelDB,
                    historyRange: SettingsDefaults.defaultHistoryRange
                )
            let selectedSource = telemetry.source(for: configuration.preferredSourceSlot)

            reconfigureLaneIfNeeded(for: configuration)
            let laneSample = makeLaneSample(
                lane: lane,
                source: selectedSource
            )
            laneSamples[lane] = laneSample
            appendHistorySampleIfNeeded(
                lane: lane,
                sample: laneSample,
                atMilliseconds: currentMilliseconds
            )

            var machine = statusMachines[lane]
                ?? DynamicsCoreFactory.makeLaneInputStatusMachine(
                    lane: lane,
                    channelLabel: configuration.preferredSourceLabel,
                    laneEnabled: configuration.isEnabled
                )
            machine.setEnabled(configuration.isEnabled)
            statuses[lane] = machine.consume(
                laneSample,
                atMilliseconds: currentMilliseconds
            )
            statusMachines[lane] = machine
        }

        for configuration in enabledLanes {
            let input = makeInput(
                for: configuration,
                atMilliseconds: currentMilliseconds,
                columnCount: splitColumnCount,
                sample: laneSamples[configuration.lane] ?? Self.emptyLaneSample
            )
            splitInputs.append(input)

            if expandedInput == nil {
                expandedInput = makeInput(
                    for: configuration,
                    atMilliseconds: currentMilliseconds,
                    columnCount: expandedColumnCount,
                    sample: laneSamples[configuration.lane] ?? Self.emptyLaneSample
                )
            }
        }

        return LevelPreviewSnapshot(
            expandedFrame: presentationPipeline.makeFrame(
                layout: .singleExpanded,
                inputs: expandedInput.map { [$0] } ?? [],
                timestamp: timestamp
            ),
            splitFrame: presentationPipeline.makeFrame(
                layout: .fourWindows,
                inputs: splitInputs,
                timestamp: timestamp
            ),
            statuses: statuses
        )
    }

    private func reconfigureLaneIfNeeded(for configuration: LevelLaneConfiguration) {
        let nextBinding = LaneBindingState(
            preferredSourceSlot: configuration.preferredSourceSlot,
            preferredSourceName: configuration.preferredSourceName
        )

        guard laneBindings[configuration.lane] != nextBinding else {
            return
        }

        historyBuffers[configuration.lane] = DynamicsCoreFactory.makeHistoryBuffer(
            maximumRange: maximumHistoryRange
        )
        clipDetectors[configuration.lane] = DynamicsCoreFactory.makeClipDetector()
        statusMachines[configuration.lane] = DynamicsCoreFactory.makeLaneInputStatusMachine(
            lane: configuration.lane,
            channelLabel: configuration.preferredSourceLabel,
            laneEnabled: configuration.isEnabled
        )
        lastAppendedMilliseconds[configuration.lane] = nil
        laneBindings[configuration.lane] = nextBinding
    }

    private func appendHistorySampleIfNeeded(
        lane: LaneID,
        sample: LaneDynamicsSample,
        atMilliseconds currentMilliseconds: UInt64
    ) {
        guard lastAppendedMilliseconds[lane] != currentMilliseconds else {
            return
        }

        historyBuffers[lane]?.append(
            dynamicsSample(
                lane: lane,
                sample: sample,
                atMilliseconds: currentMilliseconds
            )
        )
        lastAppendedMilliseconds[lane] = currentMilliseconds
    }

    private func makeInput(
        for configuration: LevelLaneConfiguration,
        atMilliseconds currentMilliseconds: UInt64,
        columnCount: Int,
        sample: LaneDynamicsSample
    ) -> LevelLaneInput {
        let lane = configuration.lane

        return LevelLaneInput(
            lane: lane,
            name: configuration.name,
            targetDB: CGFloat(configuration.targetLevelDB),
            targetMarginDB: CGFloat(configuration.targetMarginDB),
            currentSample: sample,
            history: historyBuffers[lane]?.snapshot(
                for: lane,
                range: configuration.historyRange,
                columnCount: columnCount
            ) ?? LaneHistorySnapshot(
                lane: lane,
                range: configuration.historyRange,
                buckets: []
            ),
            latestHostTime: currentMilliseconds
        )
    }

    private func makeLaneSample(
        lane: LaneID,
        source: LevelTelemetrySourceState?
    ) -> LaneDynamicsSample {
        guard let source, source.isActive else {
            return Self.emptyLaneSample
        }

        let detector = clipDetectors[lane]
            ?? DynamicsCoreFactory.makeClipDetector()
        let clipState = detector.detectClipping(
            leftPeak: source.peakLeft,
            rightPeak: source.peakRight
        )
        clipDetectors[lane] = detector

        return LaneDynamicsSample(
            rmsLeft: source.rmsLeft,
            rmsRight: source.rmsRight,
            peakLeft: source.peakLeft,
            peakRight: source.peakRight,
            clipLeft: clipState.left,
            clipRight: clipState.right
        )
    }

    private func dynamicsSample(
        lane: LaneID,
        sample: LaneDynamicsSample,
        atMilliseconds milliseconds: UInt64
    ) -> DynamicsSample {
        DynamicsSample(
            hostTime: milliseconds,
            sampleTime: Int64(milliseconds),
            frameCount: 1,
            sampleRate: 1_000,
            lane1: lane == .one ? sample : Self.emptyLaneSample,
            lane2: lane == .two ? sample : Self.emptyLaneSample,
            lane3: lane == .three ? sample : Self.emptyLaneSample,
            lane4: lane == .four ? sample : Self.emptyLaneSample
        )
    }

    private static func makeHistoryBuffers() -> [LaneID: any HistoryBuffer] {
        Dictionary(
            uniqueKeysWithValues: LaneID.allCases.map { lane in
                (
                    lane,
                    DynamicsCoreFactory.makeHistoryBuffer(
                        maximumRange: .twoMinutes
                    )
                )
            }
        )
    }

    private static func makeClipDetectors() -> [LaneID: any ClipDetector] {
        Dictionary(
            uniqueKeysWithValues: LaneID.allCases.map { lane in
                (lane, DynamicsCoreFactory.makeClipDetector())
            }
        )
    }

    private static func makeStatusMachines() -> [LaneID: LaneInputStatusMachine] {
        Dictionary(
            uniqueKeysWithValues: LaneID.allCases.map { lane in
                (
                    lane,
                    DynamicsCoreFactory.makeLaneInputStatusMachine(
                        lane: lane,
                        channelLabel: "Source \(lane.rawValue)"
                    )
                )
            }
        )
    }

    private static let emptyLaneSample = LaneDynamicsSample(
        rmsLeft: 0,
        rmsRight: 0,
        peakLeft: 0,
        peakRight: 0,
        clipLeft: false,
        clipRight: false
    )
}
