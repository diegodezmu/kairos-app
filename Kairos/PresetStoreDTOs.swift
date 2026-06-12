import Foundation
import KairosCore

struct PresetLibraryDTO: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var presets: [StoredPresetDTO]

    init(library: PresetLibrary) {
        schemaVersion = Self.currentSchemaVersion
        presets = library.presets.map(StoredPresetDTO.init)
    }

    func domainModel() throws -> PresetLibrary {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PresetStoreError.unsupportedSchemaVersion(schemaVersion)
        }

        guard presets.count == PresetSlot.allCases.count else {
            throw PresetStoreError.invalidPresetCount(actual: presets.count)
        }

        let domainPresets = presets.map(\.domainModel)
        let uniqueSlots = Set(domainPresets.map(\.slot))

        guard uniqueSlots.count == PresetSlot.allCases.count else {
            throw PresetStoreError.duplicatePresetSlot
        }

        return PresetLibrary(presets: domainPresets)
    }
}

struct StoredPresetDTO: Codable, Equatable {
    var slot: PresetSlotDTO
    var settings: SettingsPresetDTO

    init(_ preset: StoredPreset) {
        slot = PresetSlotDTO(preset.slot)
        settings = SettingsPresetDTO(preset.settings)
    }

    var domainModel: StoredPreset {
        StoredPreset(
            slot: slot.domainModel,
            settings: settings.domainModel
        )
    }
}

struct SettingsPresetDTO: Codable, Equatable {
    var syncSource: SyncSourceDTO
    var bpm: Int
    var isMetronomeEnabled: Bool
    var metronomePulse: PulseDTO
    var offsetMilliseconds: Double
    var isGridVisible: Bool
    var isLevelVisible: Bool
    var gridCycles: [GridCycleSettingsDTO]
    var levelLanes: [LevelLaneConfigurationDTO]

    init(_ preset: SettingsPreset) {
        syncSource = SyncSourceDTO(preset.syncSource)
        bpm = preset.bpm
        isMetronomeEnabled = preset.isMetronomeEnabled
        metronomePulse = PulseDTO(preset.metronomePulse)
        offsetMilliseconds = preset.offset.milliseconds
        isGridVisible = preset.isGridVisible
        isLevelVisible = preset.isLevelVisible
        gridCycles = preset.gridCycles.map(GridCycleSettingsDTO.init)
        levelLanes = preset.levelLanes.map(LevelLaneConfigurationDTO.init)
    }

    private enum CodingKeys: String, CodingKey {
        case syncSource
        case bpm
        case isMetronomeEnabled
        case metronomePulse
        case offsetMilliseconds
        case isGridVisible
        case isLevelVisible
        case gridCycles
        case levelLanes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncSource = try container.decode(SyncSourceDTO.self, forKey: .syncSource)
        bpm = try container.decode(Int.self, forKey: .bpm)
        isMetronomeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMetronomeEnabled) ?? false
        metronomePulse = try container.decode(PulseDTO.self, forKey: .metronomePulse)
        offsetMilliseconds = try container.decode(Double.self, forKey: .offsetMilliseconds)
        isGridVisible = try container.decode(Bool.self, forKey: .isGridVisible)
        isLevelVisible = try container.decode(Bool.self, forKey: .isLevelVisible)
        gridCycles = try container.decode([GridCycleSettingsDTO].self, forKey: .gridCycles)
        levelLanes = try container.decode([LevelLaneConfigurationDTO].self, forKey: .levelLanes)
    }

    var domainModel: SettingsPreset {
        SettingsPreset(
            syncSource: syncSource.domainModel,
            bpm: bpm,
            isMetronomeEnabled: isMetronomeEnabled,
            metronomePulse: metronomePulse.domainModel,
            offset: Offset(milliseconds: offsetMilliseconds),
            isGridVisible: isGridVisible,
            isLevelVisible: isLevelVisible,
            gridCycles: gridCycles.map(\.domainModel),
            levelLanes: levelLanes.map(\.domainModel)
        )
    }
}

struct GridCycleSettingsDTO: Codable, Equatable {
    var slot: CycleSlotDTO
    var isEnabled: Bool
    var name: String
    var stepNumber: StepNumberDTO
    var pulse: PulseDTO
    var visualMode: GridVisualModeDTO

    init(_ cycle: GridCycleSettings) {
        slot = CycleSlotDTO(cycle.slot)
        isEnabled = cycle.isEnabled
        name = cycle.name
        stepNumber = StepNumberDTO(cycle.stepNumber)
        pulse = PulseDTO(cycle.pulse)
        visualMode = GridVisualModeDTO(cycle.visualMode)
    }

    var domainModel: GridCycleSettings {
        GridCycleSettings(
            slot: slot.domainModel,
            isEnabled: isEnabled,
            name: name,
            stepNumber: stepNumber.domainModel,
            pulse: pulse.domainModel,
            visualMode: visualMode.domainModel
        )
    }
}

struct LevelLaneConfigurationDTO: Codable, Equatable {
    var lane: LaneIDDTO
    var isEnabled: Bool
    var name: String
    var targetLevelDB: Double
    var historyRange: HistoryRangeDTO

    init(_ lane: LevelLaneConfiguration) {
        self.lane = LaneIDDTO(lane.lane)
        isEnabled = lane.isEnabled
        name = lane.name
        targetLevelDB = lane.targetLevelDB
        self.historyRange = HistoryRangeDTO(lane.historyRange)
    }

    var domainModel: LevelLaneConfiguration {
        LevelLaneConfiguration(
            lane: lane.domainModel,
            isEnabled: isEnabled,
            name: name,
            targetLevelDB: targetLevelDB,
            historyRange: historyRange.domainModel
        )
    }
}

enum PresetSlotDTO: String, Codable, Equatable {
    case defaultPreset
    case custom1
    case custom2
    case custom3
    case custom4

    init(_ slot: PresetSlot) {
        switch slot {
        case .defaultPreset:
            self = .defaultPreset
        case .custom1:
            self = .custom1
        case .custom2:
            self = .custom2
        case .custom3:
            self = .custom3
        case .custom4:
            self = .custom4
        }
    }

    var domainModel: PresetSlot {
        switch self {
        case .defaultPreset:
            return .defaultPreset
        case .custom1:
            return .custom1
        case .custom2:
            return .custom2
        case .custom3:
            return .custom3
        case .custom4:
            return .custom4
        }
    }
}

enum SyncSourceDTO: String, Codable, Equatable {
    case internalClock
    case midiClock
    case link

    init(_ source: SyncSource) {
        switch source {
        case .internalClock:
            self = .internalClock
        case .midiClock:
            self = .midiClock
        case .link:
            self = .link
        }
    }

    var domainModel: SyncSource {
        switch self {
        case .internalClock:
            return .internalClock
        case .midiClock:
            return .midiClock
        case .link:
            return .link
        }
    }
}

enum GridVisualModeDTO: String, Codable, Equatable {
    case block
    case border
    case line

    init(_ mode: GridVisualMode) {
        switch mode {
        case .block:
            self = .block
        case .border:
            self = .border
        case .line:
            self = .line
        }
    }

    var domainModel: GridVisualMode {
        switch self {
        case .block:
            return .block
        case .border:
            return .border
        case .line:
            return .line
        }
    }
}

enum CycleSlotDTO: Int, Codable, Equatable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    init(_ slot: CycleSlot) {
        switch slot {
        case .one:
            self = .one
        case .two:
            self = .two
        case .three:
            self = .three
        case .four:
            self = .four
        }
    }

    var domainModel: CycleSlot {
        switch self {
        case .one:
            return .one
        case .two:
            return .two
        case .three:
            return .three
        case .four:
            return .four
        }
    }
}

enum StepNumberDTO: Int, Codable, Equatable {
    case one = 1
    case two = 2
    case four = 4
    case eight = 8
    case sixteen = 16
    case thirtyTwo = 32
    case sixtyFour = 64
    case oneHundredTwentyEight = 128

    init(_ stepNumber: StepNumber) {
        switch stepNumber {
        case .one:
            self = .one
        case .two:
            self = .two
        case .four:
            self = .four
        case .eight:
            self = .eight
        case .sixteen:
            self = .sixteen
        case .thirtyTwo:
            self = .thirtyTwo
        case .sixtyFour:
            self = .sixtyFour
        case .oneHundredTwentyEight:
            self = .oneHundredTwentyEight
        }
    }

    var domainModel: StepNumber {
        switch self {
        case .one:
            return .one
        case .two:
            return .two
        case .four:
            return .four
        case .eight:
            return .eight
        case .sixteen:
            return .sixteen
        case .thirtyTwo:
            return .thirtyTwo
        case .sixtyFour:
            return .sixtyFour
        case .oneHundredTwentyEight:
            return .oneHundredTwentyEight
        }
    }
}

enum PulseDTO: Double, Codable, Equatable {
    case oneSixteenth = 0.0625
    case oneEighth = 0.125
    case oneQuarter = 0.25
    case oneHalf = 0.5
    case one = 1
    case two = 2
    case four = 4
    case eight = 8
    case sixteen = 16
    case thirtyTwo = 32
    case sixtyFour = 64

    init(_ pulse: Pulse) {
        switch pulse {
        case .oneSixteenth:
            self = .oneSixteenth
        case .oneEighth:
            self = .oneEighth
        case .oneQuarter:
            self = .oneQuarter
        case .oneHalf:
            self = .oneHalf
        case .one:
            self = .one
        case .two:
            self = .two
        case .four:
            self = .four
        case .eight:
            self = .eight
        case .sixteen:
            self = .sixteen
        case .thirtyTwo:
            self = .thirtyTwo
        case .sixtyFour:
            self = .sixtyFour
        }
    }

    var domainModel: Pulse {
        switch self {
        case .oneSixteenth:
            return .oneSixteenth
        case .oneEighth:
            return .oneEighth
        case .oneQuarter:
            return .oneQuarter
        case .oneHalf:
            return .oneHalf
        case .one:
            return .one
        case .two:
            return .two
        case .four:
            return .four
        case .eight:
            return .eight
        case .sixteen:
            return .sixteen
        case .thirtyTwo:
            return .thirtyTwo
        case .sixtyFour:
            return .sixtyFour
        }
    }
}

enum LaneIDDTO: Int, Codable, Equatable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    init(_ lane: LaneID) {
        switch lane {
        case .one:
            self = .one
        case .two:
            self = .two
        case .three:
            self = .three
        case .four:
            self = .four
        }
    }

    var domainModel: LaneID {
        switch self {
        case .one:
            return .one
        case .two:
            return .two
        case .three:
            return .three
        case .four:
            return .four
        }
    }
}

enum HistoryRangeDTO: Double, Codable, Equatable {
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120

    init(_ historyRange: HistoryRange) {
        switch historyRange {
        case .tenSeconds:
            self = .tenSeconds
        case .thirtySeconds:
            self = .thirtySeconds
        case .oneMinute:
            self = .oneMinute
        case .twoMinutes:
            self = .twoMinutes
        }
    }

    var domainModel: HistoryRange {
        switch self {
        case .tenSeconds:
            return .tenSeconds
        case .thirtySeconds:
            return .thirtySeconds
        case .oneMinute:
            return .oneMinute
        case .twoMinutes:
            return .twoMinutes
        }
    }
}
