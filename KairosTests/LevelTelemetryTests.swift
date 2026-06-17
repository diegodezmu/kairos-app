import CoreGraphics
import XCTest
import KairosCore
@testable import Kairos

final class LevelTelemetryTests: XCTestCase {
    func testLegacyLevelLaneDTOFallsBackToLaneNumberWhenSourceSlotIsMissing() throws {
        let payload = """
        {
          "lane": 3,
          "isEnabled": true,
          "name": "Synth",
          "targetLevelDB": -9,
          "historyRange": 60
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(LevelLaneConfigurationDTO.self, from: payload)

        XCTAssertEqual(decoded.domainModel.preferredSourceSlot, 3)
        XCTAssertNil(decoded.domainModel.preferredSourceName)
        XCTAssertEqual(
            decoded.domainModel.targetMarginDB,
            SettingsDefaults.defaultTargetMarginDB
        )
    }

    func testLevelRuntimeDriverRoutesSelectedSourceIntoEnabledLane() {
        let driver = LevelRuntimeDriver()
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let telemetry = LevelTelemetrySnapshot(
            isListening: true,
            port: 51515,
            errorMessage: nil,
            sources: [
                makeSourceState(
                    slot: 4,
                    name: "Perc",
                    rmsLeft: 0.5,
                    rmsRight: 0.25,
                    peakLeft: 0.92,
                    peakRight: 0.81
                )
            ]
        )

        let snapshot = driver.snapshot(
            now: now,
            elapsedMilliseconds: 0,
            laneConfigurations: [
                LevelLaneConfiguration(
                    lane: .one,
                    isEnabled: true,
                    name: "Source 1",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 4,
                    preferredSourceName: "Perc"
                ),
                LevelLaneConfiguration(
                    lane: .two,
                    isEnabled: false,
                    name: "Source 2",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 2
                ),
                LevelLaneConfiguration(
                    lane: .three,
                    isEnabled: false,
                    name: "Source 3",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 3
                ),
                LevelLaneConfiguration(
                    lane: .four,
                    isEnabled: false,
                    name: "Source 4",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 4
                ),
            ],
            telemetry: telemetry
        )

        XCTAssertEqual(snapshot.expandedFrame.lanes.count, 1)
        XCTAssertEqual(snapshot.expandedFrame.lanes.first?.lane, .one)
        XCTAssertEqual(snapshot.statuses[.one]?.state, .receiving)
        XCTAssertEqual(snapshot.statuses[.one]?.displayLabel, "Source 4 · Perc")
        XCTAssertEqual(snapshot.statuses[.two]?.state, .disabled)
        XCTAssertEqual(snapshot.splitFrame.lanes.first?.left.currentDB.rounded(), CGFloat(-6))
    }

    func testLevelRuntimeDriverShowsNoSignalWhenMappedSourceIsOffline() {
        let driver = LevelRuntimeDriver()
        let now = Date(timeIntervalSinceReferenceDate: 200)
        let telemetry = LevelTelemetrySnapshot(
            isListening: true,
            port: 51515,
            errorMessage: nil,
            sources: []
        )

        let snapshot = driver.snapshot(
            now: now,
            elapsedMilliseconds: 0,
            laneConfigurations: [
                LevelLaneConfiguration(
                    lane: .one,
                    isEnabled: true,
                    name: "Source 1",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 2,
                    preferredSourceName: "Bass"
                ),
                LevelLaneConfiguration(
                    lane: .two,
                    isEnabled: false,
                    name: "Source 2",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 2
                ),
                LevelLaneConfiguration(
                    lane: .three,
                    isEnabled: false,
                    name: "Source 3",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 3
                ),
                LevelLaneConfiguration(
                    lane: .four,
                    isEnabled: false,
                    name: "Source 4",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 4
                ),
            ],
            telemetry: telemetry
        )

        XCTAssertEqual(snapshot.statuses[.one]?.state, .noSignal)
        XCTAssertEqual(snapshot.statuses[.one]?.displayLabel, "No signal")
        XCTAssertEqual(snapshot.expandedFrame.lanes.first?.left.currentDB, CGFloat(-60))
    }

    func testLevelRuntimeDriverUsesPeakForClipColorWhileKeepingRMSForBody() throws {
        let driver = LevelRuntimeDriver()
        let now = Date(timeIntervalSinceReferenceDate: 250)
        let telemetry = LevelTelemetrySnapshot(
            isListening: true,
            port: 51515,
            errorMessage: nil,
            sources: [
                makeSourceState(
                    slot: 1,
                    name: "Drums",
                    rmsLeft: 0.35,
                    rmsRight: 0.34,
                    peakLeft: 1.0,
                    peakRight: 0.92
                )
            ]
        )

        let snapshot = driver.snapshot(
            now: now,
            elapsedMilliseconds: 0,
            laneConfigurations: [
                LevelLaneConfiguration(
                    lane: .one,
                    isEnabled: true,
                    name: "Source 1",
                    targetLevelDB: -12,
                    historyRange: .thirtySeconds,
                    preferredSourceSlot: 1,
                    preferredSourceName: "Drums"
                ),
            ],
            telemetry: telemetry
        )

        let lane = try XCTUnwrap(snapshot.splitFrame.lanes.first)
        XCTAssertEqual(lane.left.currentDB.rounded(), CGFloat(-9))
        XCTAssertEqual(
            lane.left.fillColor,
            LevelResolvedColor(red: 54, green: 23, blue: 24)
        )
    }

    @MainActor
    func testDesktopShellModelEnablingLevelLaneProducesRenderableSnapshot() {
        let model = DesktopShellModel(
            settings: SettingsModel(),
            presetStore: nil,
            currentDate: { Date(timeIntervalSinceReferenceDate: 300) }
        )

        model.setLaneEnabled(true, lane: .one)
        let snapshot = model.workspaceSnapshot(
            at: Date(timeIntervalSinceReferenceDate: 300)
        )

        XCTAssertEqual(snapshot.levelSplitFrame.lanes.count, 1)
        XCTAssertEqual(snapshot.levelSplitFrame.lanes.first?.lane, .one)
        XCTAssertEqual(model.laneStatuses[.one]?.state, .waiting)
        XCTAssertEqual(model.laneStatuses[.one]?.displayLabel, "Waiting for Max4live Slot 1")
    }

    private func makeSourceState(
        slot: Int,
        name: String,
        rmsLeft: Float,
        rmsRight: Float,
        peakLeft: Float,
        peakRight: Float
    ) -> LevelTelemetrySourceState {
        LevelTelemetrySourceState(
            sourceSlot: slot,
            sourceName: name,
            rmsLeft: rmsLeft,
            rmsRight: rmsRight,
            peakLeft: peakLeft,
            peakRight: peakRight,
            isActive: true,
            hasConflict: false,
            lastReceivedAt: Date(),
            endpoint: "127.0.0.1:51515"
        )
    }
}
