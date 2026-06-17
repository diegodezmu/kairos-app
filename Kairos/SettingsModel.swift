import Foundation
import Observation
import KairosCore

@MainActor
@Observable
final class SettingsModel {
    var activePresetSlot: PresetSlot
    var syncSource: SyncSource
    var usbMIDISource: USBMIDISourcePreference
    var linkStatus: LinkStatus
    var bpm: Int {
        didSet {
            let clampedValue = SettingsDefaults.clampedBPM(bpm)
            if bpm != clampedValue {
                bpm = clampedValue
            }
        }
    }
    var isMetronomeEnabled: Bool
    var metronomePulse: Pulse
    var offset: Offset {
        didSet {
            let clampedValue = SettingsDefaults.clampedOffset(offset)
            if offset != clampedValue {
                offset = clampedValue
            }
        }
    }
    var isGridVisible: Bool
    var isLevelVisible: Bool
    var gridCycles: [GridCycleSettings] {
        didSet {
            let normalizedValue = SettingsDefaults.normalizeGridCycles(gridCycles)
            if gridCycles != normalizedValue {
                gridCycles = normalizedValue
            }
        }
    }
    var levelLanes: [LevelLaneConfiguration] {
        didSet {
            let normalizedValue = SettingsDefaults.normalizeLevelLanes(levelLanes)
            if levelLanes != normalizedValue {
                levelLanes = normalizedValue
            }
        }
    }

    init(
        activePresetSlot: PresetSlot = .defaultPreset,
        preset: SettingsPreset = .factoryDefault,
        linkStatus: LinkStatus = .off
    ) {
        self.activePresetSlot = activePresetSlot
        self.syncSource = preset.syncSource
        self.usbMIDISource = preset.usbMIDISource
        self.linkStatus = linkStatus
        self.bpm = preset.bpm
        self.isMetronomeEnabled = preset.isMetronomeEnabled
        self.metronomePulse = preset.metronomePulse
        self.offset = preset.offset
        self.isGridVisible = preset.isGridVisible
        self.isLevelVisible = preset.isLevelVisible
        self.gridCycles = preset.gridCycles
        self.levelLanes = preset.levelLanes
    }

    var preset: SettingsPreset {
        SettingsPreset(
            syncSource: syncSource,
            usbMIDISource: usbMIDISource,
            bpm: bpm,
            isMetronomeEnabled: isMetronomeEnabled,
            metronomePulse: metronomePulse,
            offset: offset,
            isGridVisible: isGridVisible,
            isLevelVisible: isLevelVisible,
            gridCycles: gridCycles,
            levelLanes: levelLanes
        )
    }

    func apply(
        _ preset: SettingsPreset,
        activating slot: PresetSlot? = nil
    ) {
        if let slot {
            activePresetSlot = slot
        }

        syncSource = preset.syncSource
        usbMIDISource = preset.usbMIDISource
        bpm = preset.bpm
        isMetronomeEnabled = preset.isMetronomeEnabled
        metronomePulse = preset.metronomePulse
        offset = preset.offset
        isGridVisible = preset.isGridVisible
        isLevelVisible = preset.isLevelVisible
        gridCycles = preset.gridCycles
        levelLanes = preset.levelLanes
    }

    func makeStoredPreset(for slot: PresetSlot? = nil) -> StoredPreset {
        StoredPreset(
            slot: slot ?? activePresetSlot,
            settings: preset
        )
    }

    func updateGridCycle(
        slot: CycleSlot,
        _ update: (inout GridCycleSettings) -> Void
    ) {
        guard let index = gridCycles.firstIndex(where: { $0.slot == slot }) else {
            return
        }

        var cycle = gridCycles[index]
        update(&cycle)
        gridCycles[index] = cycle
    }

    func updateLevelLane(
        lane: LaneID,
        _ update: (inout LevelLaneConfiguration) -> Void
    ) {
        guard let index = levelLanes.firstIndex(where: { $0.lane == lane }) else {
            return
        }

        var levelLane = levelLanes[index]
        update(&levelLane)
        levelLanes[index] = levelLane
    }
}
