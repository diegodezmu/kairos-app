import XCTest
import KairosCore
@testable import Kairos

final class PresetStoreTests: XCTestCase {
    func testRoundTripPersistsFivePresetsIncludingRenames() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let store = try PresetStore(directoryURL: temporaryDirectory)
        let expectedLibrary = PresetLibrary(
            presets: PresetSlot.allCases.enumerated().map { index, slot in
                StoredPreset(
                    slot: slot,
                    settings: makePreset(seed: index)
                )
            }
        )

        try await store.savePresets(expectedLibrary)
        let loadedLibrary = try await store.loadPresets()

        XCTAssertEqual(loadedLibrary, expectedLibrary)
        XCTAssertEqual(loadedLibrary.presets.count, 5)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory
                    .appendingPathComponent("presets.json")
                    .path
            )
        )
    }

    func testGridPreviewDriverMapsPerCycleModesAndSkipsDisabledCycles() {
        let driver = GridPreviewDriver()
        let frame = driver.makeFrame(
            settings: [
                GridCycleSettings(
                    slot: .one,
                    isEnabled: true,
                    name: "Cycle 1",
                    stepNumber: .sixteen,
                    pulse: .oneQuarter,
                    visualMode: .block
                ),
                GridCycleSettings(
                    slot: .two,
                    isEnabled: false,
                    name: "Cycle 2",
                    stepNumber: .thirtyTwo,
                    pulse: .oneQuarter,
                    visualMode: .border
                ),
                GridCycleSettings(
                    slot: .three,
                    isEnabled: true,
                    name: "Cycle 3",
                    stepNumber: .sixtyFour,
                    pulse: .oneQuarter,
                    visualMode: .line
                ),
                GridCycleSettings(
                    slot: .four,
                    isEnabled: true,
                    name: "Cycle 4",
                    stepNumber: .sixteen,
                    pulse: .oneQuarter,
                    visualMode: .line
                ),
            ],
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 1
        )

        XCTAssertEqual(frame.cycles.map(\.slot), [.one, .three, .four])
        XCTAssertEqual(frame.cycles.map(\.mode), [.block, .lineSM, .lineMD])
    }

    func testLevelPreviewDriverReturnsExpandedFrameAndLaneStatuses() {
        let driver = LevelPreviewDriver()
        let snapshot = driver.snapshot(
            at: 1_000,
            timestamp: 1,
            laneConfigurations: [
                LevelLaneConfiguration(
                    lane: .one,
                    isEnabled: true,
                    name: "Drums",
                    targetLevelDB: -12,
                    historyRange: .tenSeconds
                ),
                LevelLaneConfiguration(
                    lane: .two,
                    isEnabled: false,
                    name: "FX",
                    targetLevelDB: -18,
                    historyRange: .thirtySeconds
                ),
                LevelLaneConfiguration(
                    lane: .three,
                    isEnabled: false,
                    name: "Synth",
                    targetLevelDB: -9,
                    historyRange: .oneMinute
                ),
                LevelLaneConfiguration(
                    lane: .four,
                    isEnabled: false,
                    name: "Bass",
                    targetLevelDB: -24,
                    historyRange: .twoMinutes
                ),
            ]
        )

        XCTAssertEqual(snapshot.expandedFrame.lanes.count, 1)
        XCTAssertEqual(snapshot.splitFrame.lanes.count, 1)
        XCTAssertEqual(snapshot.statuses[.one]?.lane, .one)
        XCTAssertEqual(snapshot.statuses[.two]?.state, .disabled)
        XCTAssertFalse(snapshot.statuses[.one]?.displayLabel.isEmpty ?? true)
    }

    private func makePreset(seed: Int) -> SettingsPreset {
        let syncSources: [SyncSource] = [
            .internalClock,
            .midiClock,
            .link,
            .internalClock,
            .link,
        ]
        let metronomePulses: [Pulse] = [
            .oneSixteenth,
            .oneEighth,
            .oneQuarter,
            .oneHalf,
            .one,
        ]
        let stepNumbers = StepNumber.allCases
        let cyclePulses = Pulse.allCases
        let visualModes = GridVisualMode.allCases
        let historyRanges = HistoryRange.allCases

        return SettingsPreset(
            syncSource: syncSources[seed],
            bpm: 92 + (seed * 47),
            isMetronomeEnabled: seed.isMultiple(of: 2),
            metronomePulse: metronomePulses[seed],
            offset: Offset(milliseconds: Double(-160 + (seed * 80))),
            isGridVisible: seed.isMultiple(of: 2),
            isLevelVisible: !seed.isMultiple(of: 2),
            gridCycles: CycleSlot.allCases.enumerated().map { cycleIndex, slot in
                GridCycleSettings(
                    slot: slot,
                    isEnabled: (seed + cycleIndex).isMultiple(of: 2),
                    name: "Preset \(seed) Cycle \(slot.rawValue)",
                    stepNumber: stepNumbers[(seed + cycleIndex) % stepNumbers.count],
                    pulse: cyclePulses[(seed + cycleIndex) % cyclePulses.count],
                    visualMode: visualModes[(seed + cycleIndex) % visualModes.count]
                )
            },
            levelLanes: LaneID.allCases.enumerated().map { laneIndex, lane in
                LevelLaneConfiguration(
                    lane: lane,
                    isEnabled: !(seed + laneIndex).isMultiple(of: 2),
                    name: "Preset \(seed) Source \(lane.rawValue)",
                    targetLevelDB: Double(-12 - (seed * 2) - laneIndex),
                    historyRange: historyRanges[(seed + laneIndex) % historyRanges.count]
                )
            }
        )
    }

    func testLegacyPresetPayloadDefaultsMetronomeToggleToOff() throws {
        let seededLibrary = PresetLibrary(
            presets: PresetSlot.allCases.map { slot in
                StoredPreset(
                    slot: slot,
                    settings: SettingsPreset(
                        syncSource: .internalClock,
                        bpm: 120,
                        isMetronomeEnabled: true,
                        metronomePulse: .oneQuarter,
                        offset: Offset(milliseconds: 0),
                        isGridVisible: true,
                        isLevelVisible: true,
                        gridCycles: CycleSlot.allCases.map { SettingsDefaults.defaultGridCycle(for: $0) },
                        levelLanes: LaneID.allCases.map { SettingsDefaults.defaultLevelLane(for: $0) }
                    )
                )
            }
        )
        let data = try JSONEncoder().encode(PresetLibraryDTO(library: seededLibrary))
        var jsonObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var presets = try XCTUnwrap(jsonObject["presets"] as? [[String: Any]])

        for index in presets.indices {
            var preset = presets[index]
            var settings = try XCTUnwrap(preset["settings"] as? [String: Any])
            settings.removeValue(forKey: "isMetronomeEnabled")
            preset["settings"] = settings
            presets[index] = preset
        }

        jsonObject["presets"] = presets
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)
        let dto = try JSONDecoder().decode(PresetLibraryDTO.self, from: legacyData)
        let library = try dto.domainModel()

        XCTAssertTrue(library.presets.allSatisfy { $0.settings.isMetronomeEnabled == false })
    }
}
