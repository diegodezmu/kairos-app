import Foundation
import KairosCore

enum SyncSource: String, CaseIterable, Sendable {
    case internalClock
    case midiClock
    case link

    var displayName: String {
        switch self {
        case .internalClock:
            return "Internal"
        case .midiClock:
            return "MIDI Clock"
        case .link:
            return "Link"
        }
    }
}

enum MIDIClockStatus: String, Sendable {
    case idle
    case receiving
    case disconnected
}

struct MIDIPortOption: Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
}

struct LinkStatus: Equatable, Sendable {
    var isEnabled: Bool
    var peerCount: Int
    var tempoBPM: Double?

    static let off = LinkStatus(
        isEnabled: false,
        peerCount: 0,
        tempoBPM: nil
    )
}

enum GridVisualMode: String, CaseIterable, Sendable {
    case block
    case border
    case line
}

struct GridCycleSettings: Equatable, Sendable {
    var slot: CycleSlot
    var isEnabled: Bool
    var name: String
    var stepNumber: StepNumber
    var pulse: Pulse
    var visualMode: GridVisualMode

    var cycleConfig: CycleConfig {
        CycleConfig(
            slot: slot,
            stepNumber: stepNumber,
            pulse: pulse
        )
    }
}

struct LevelLaneConfiguration: Equatable, Sendable {
    var lane: LaneID
    var isEnabled: Bool
    var name: String
    var targetLevelDB: Double
    var historyRange: HistoryRange
}

enum PresetSlot: Int, CaseIterable, Hashable, Sendable {
    case defaultPreset
    case custom1
    case custom2
    case custom3
    case custom4

    var displayName: String {
        switch self {
        case .defaultPreset:
            return "Default"
        case .custom1:
            return "Preset 1"
        case .custom2:
            return "Preset 2"
        case .custom3:
            return "Preset 3"
        case .custom4:
            return "Preset 4"
        }
    }

    var isCustomizable: Bool {
        self != .defaultPreset
    }
}

struct SettingsPreset: Equatable, Sendable {
    var syncSource: SyncSource
    var bpm: Int
    var metronomePulse: Pulse
    var offset: Offset
    var isGridVisible: Bool
    var isLevelVisible: Bool
    var gridCycles: [GridCycleSettings]
    var levelLanes: [LevelLaneConfiguration]

    init(
        syncSource: SyncSource,
        bpm: Int,
        metronomePulse: Pulse,
        offset: Offset,
        isGridVisible: Bool,
        isLevelVisible: Bool,
        gridCycles: [GridCycleSettings],
        levelLanes: [LevelLaneConfiguration]
    ) {
        self.syncSource = syncSource
        self.bpm = SettingsDefaults.clampedBPM(bpm)
        self.metronomePulse = metronomePulse
        self.offset = SettingsDefaults.clampedOffset(offset)
        self.isGridVisible = isGridVisible
        self.isLevelVisible = isLevelVisible
        self.gridCycles = SettingsDefaults.normalizeGridCycles(gridCycles)
        self.levelLanes = SettingsDefaults.normalizeLevelLanes(levelLanes)
    }

    static let factoryDefault = SettingsPreset(
        syncSource: .internalClock,
        bpm: SettingsDefaults.defaultBPM,
        metronomePulse: SettingsDefaults.defaultMetronomePulse,
        offset: SettingsDefaults.defaultOffset,
        isGridVisible: true,
        isLevelVisible: true,
        gridCycles: CycleSlot.allCases.map { SettingsDefaults.defaultGridCycle(for: $0) },
        levelLanes: LaneID.allCases.map { SettingsDefaults.defaultLevelLane(for: $0) }
    )
}

struct StoredPreset: Equatable, Sendable {
    var slot: PresetSlot
    var settings: SettingsPreset

    init(
        slot: PresetSlot,
        settings: SettingsPreset = .factoryDefault
    ) {
        self.slot = slot
        self.settings = settings
    }
}

struct PresetLibrary: Equatable, Sendable {
    var presets: [StoredPreset]

    init(presets: [StoredPreset] = PresetLibrary.factoryDefault.presets) {
        self.presets = SettingsDefaults.normalizeStoredPresets(presets)
    }

    static let factoryDefault = PresetLibrary(
        presets: PresetSlot.allCases.map { slot in
            StoredPreset(slot: slot, settings: .factoryDefault)
        }
    )
}

enum SettingsDefaults {
    static let defaultBPM = 120
    static let defaultMetronomePulse: Pulse = .oneQuarter
    static let defaultOffset = Offset(milliseconds: 0)
    static let defaultTargetLevelDB = -12.0
    static let defaultHistoryRange: HistoryRange = .thirtySeconds

    static func clampedBPM(_ bpm: Int) -> Int {
        min(max(bpm, 1), 999)
    }

    static func clampedOffset(_ offset: Offset) -> Offset {
        Offset(
            milliseconds: min(
                max(offset.milliseconds, Offset.minimumMilliseconds),
                Offset.maximumMilliseconds
            )
        )
    }

    static func defaultGridCycle(for slot: CycleSlot) -> GridCycleSettings {
        GridCycleSettings(
            slot: slot,
            isEnabled: false,
            name: "Cycle \(slot.rawValue)",
            stepNumber: .sixteen,
            pulse: .oneQuarter,
            visualMode: .block
        )
    }

    static func defaultLevelLane(for lane: LaneID) -> LevelLaneConfiguration {
        LevelLaneConfiguration(
            lane: lane,
            isEnabled: false,
            name: "Source \(lane.rawValue)",
            targetLevelDB: defaultTargetLevelDB,
            historyRange: defaultHistoryRange
        )
    }

    static func normalizeGridCycles(_ gridCycles: [GridCycleSettings]) -> [GridCycleSettings] {
        let keyedBySlot = Dictionary(
            gridCycles.map { ($0.slot.rawValue, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        return CycleSlot.allCases.map { slot in
            keyedBySlot[slot.rawValue] ?? defaultGridCycle(for: slot)
        }
    }

    static func normalizeLevelLanes(_ levelLanes: [LevelLaneConfiguration]) -> [LevelLaneConfiguration] {
        let keyedByLane = Dictionary(
            levelLanes.map { ($0.lane.rawValue, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        return LaneID.allCases.map { lane in
            keyedByLane[lane.rawValue] ?? defaultLevelLane(for: lane)
        }
    }

    static func normalizeStoredPresets(_ presets: [StoredPreset]) -> [StoredPreset] {
        let keyedBySlot = Dictionary(
            presets.map { ($0.slot, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        return PresetSlot.allCases.map { slot in
            keyedBySlot[slot] ?? StoredPreset(slot: slot, settings: .factoryDefault)
        }
    }
}
