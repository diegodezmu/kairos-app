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
}
