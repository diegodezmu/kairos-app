import Foundation
import KairosCore

enum SyncSource: String, CaseIterable, Sendable {
    case internalClock
    case usb
    case link

    var displayName: String {
        switch self {
        case .internalClock:
            return "Internal"
        case .usb:
            return "USB"
        case .link:
            return "Link"
        }
    }
}

struct USBMIDISourcePreference: Equatable, Sendable {
    var uniqueID: Int32?
    var displayName: String?

    static let none = USBMIDISourcePreference(
        uniqueID: nil,
        displayName: nil
    )
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
    case custom
}

enum GridStepDisplayMode: String, CaseIterable, Sendable {
    case block
    case border
    case line

    func cycled() -> GridStepDisplayMode {
        switch self {
        case .block:
            return .border
        case .border:
            return .line
        case .line:
            return .block
        }
    }
}

struct GridCycleSettings: Equatable, Sendable {
    var slot: CycleSlot
    var isEnabled: Bool
    var name: String
    var stepNumber: StepNumber
    var pulse: Pulse
    var visualMode: GridVisualMode
    var customStepModes: [GridStepDisplayMode]?

    var cycleConfig: CycleConfig {
        CycleConfig(
            slot: slot,
            stepNumber: stepNumber,
            pulse: pulse
        )
    }

    init(
        slot: CycleSlot,
        isEnabled: Bool,
        name: String,
        stepNumber: StepNumber,
        pulse: Pulse,
        visualMode: GridVisualMode,
        customStepModes: [GridStepDisplayMode]? = nil
    ) {
        self.slot = slot
        self.isEnabled = isEnabled
        self.name = name
        self.stepNumber = stepNumber
        self.pulse = pulse
        self.visualMode = visualMode
        self.customStepModes = SettingsDefaults.normalizedCustomStepModes(
            customStepModes,
            stepCount: stepNumber.rawValue,
            fallback: visualMode.uniformDisplayMode ?? .block
        )
    }
}

struct LevelLaneConfiguration: Equatable, Sendable {
    var lane: LaneID
    var isEnabled: Bool
    var name: String
    var targetLevelDB: Double
    var targetMarginDB: Double
    var historyRange: HistoryRange
    var preferredSourceSlot: Int?
    var preferredSourceName: String?

    init(
        lane: LaneID,
        isEnabled: Bool,
        name: String,
        targetLevelDB: Double,
        targetMarginDB: Double = 6,
        historyRange: HistoryRange
    ) {
        self.init(
            lane: lane,
            isEnabled: isEnabled,
            name: name,
            targetLevelDB: targetLevelDB,
            targetMarginDB: targetMarginDB,
            historyRange: historyRange,
            preferredSourceSlot: lane.rawValue,
            preferredSourceName: nil
        )
    }

    init(
        lane: LaneID,
        isEnabled: Bool,
        name: String,
        targetLevelDB: Double,
        targetMarginDB: Double = 6,
        historyRange: HistoryRange,
        preferredSourceSlot: Int?,
        preferredSourceName: String? = nil
    ) {
        self.lane = lane
        self.isEnabled = isEnabled
        self.name = name
        self.targetLevelDB = targetLevelDB
        self.targetMarginDB = SettingsDefaults.clampedTargetMarginDB(targetMarginDB)
        self.historyRange = historyRange
        self.preferredSourceSlot = preferredSourceSlot
        self.preferredSourceName = preferredSourceName
    }

    var preferredSourceLabel: String {
        guard let preferredSourceSlot else {
            return "Unassigned"
        }

        let trimmedName = preferredSourceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmedName, !trimmedName.isEmpty else {
            return "Source \(preferredSourceSlot)"
        }

        return "Source \(preferredSourceSlot) · \(trimmedName)"
    }
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
    var usbMIDISource: USBMIDISourcePreference
    var bpm: Int
    var isMetronomeEnabled: Bool
    var metronomePulse: Pulse
    var offset: Offset
    var isGridVisible: Bool
    var isLevelVisible: Bool
    var gridCycles: [GridCycleSettings]
    var levelLanes: [LevelLaneConfiguration]

    init(
        syncSource: SyncSource,
        usbMIDISource: USBMIDISourcePreference = .none,
        bpm: Int,
        isMetronomeEnabled: Bool,
        metronomePulse: Pulse,
        offset: Offset,
        isGridVisible: Bool,
        isLevelVisible: Bool,
        gridCycles: [GridCycleSettings],
        levelLanes: [LevelLaneConfiguration]
    ) {
        self.syncSource = syncSource
        self.usbMIDISource = usbMIDISource
        self.bpm = SettingsDefaults.clampedBPM(bpm)
        self.isMetronomeEnabled = isMetronomeEnabled
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
        isMetronomeEnabled: false,
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
    static let defaultTargetMarginDB = 6.0
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

    static func clampedTargetMarginDB(_ margin: Double) -> Double {
        min(max(margin, 1), 24)
    }

    static func defaultGridCycle(for slot: CycleSlot) -> GridCycleSettings {
        GridCycleSettings(
            slot: slot,
            isEnabled: false,
            name: "Cycle \(slot.rawValue)",
            stepNumber: .sixteen,
            pulse: .oneQuarter,
            visualMode: .block,
            customStepModes: nil
        )
    }

    static func defaultLevelLane(for lane: LaneID) -> LevelLaneConfiguration {
        LevelLaneConfiguration(
            lane: lane,
            isEnabled: false,
            name: "Source \(lane.rawValue)",
            targetLevelDB: defaultTargetLevelDB,
            targetMarginDB: defaultTargetMarginDB,
            historyRange: defaultHistoryRange
        )
    }

    static func normalizeGridCycles(_ gridCycles: [GridCycleSettings]) -> [GridCycleSettings] {
        let keyedBySlot = Dictionary(
            gridCycles.map { ($0.slot.rawValue, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        return CycleSlot.allCases.map { slot in
            var cycle = keyedBySlot[slot.rawValue] ?? defaultGridCycle(for: slot)
            cycle.customStepModes = normalizedCustomStepModes(
                cycle.customStepModes,
                stepCount: cycle.stepNumber.rawValue,
                fallback: cycle.visualMode.uniformDisplayMode ?? .block
            )

            if cycle.visualMode == .custom, cycle.customStepModes == nil {
                cycle.customStepModes = Array(
                    repeating: .block,
                    count: cycle.stepNumber.rawValue
                )
            }

            return cycle
        }
    }

    static func normalizedCustomStepModes(
        _ modes: [GridStepDisplayMode]?,
        stepCount: Int,
        fallback: GridStepDisplayMode
    ) -> [GridStepDisplayMode]? {
        guard let modes else {
            return nil
        }

        let clampedStepCount = max(stepCount, 0)
        guard clampedStepCount > 0 else {
            return []
        }

        var normalized = Array(modes.prefix(clampedStepCount))
        let fillMode = normalized.last ?? fallback

        if normalized.count < clampedStepCount {
            normalized.append(
                contentsOf: repeatElement(
                    fillMode,
                    count: clampedStepCount - normalized.count
                )
            )
        }

        return normalized
    }

    static func normalizeLevelLanes(_ levelLanes: [LevelLaneConfiguration]) -> [LevelLaneConfiguration] {
        let keyedByLane = Dictionary(
            levelLanes.map { ($0.lane.rawValue, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        return LaneID.allCases.map { lane in
            var levelLane = keyedByLane[lane.rawValue] ?? defaultLevelLane(for: lane)
            levelLane.targetMarginDB = clampedTargetMarginDB(levelLane.targetMarginDB)
            return levelLane
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

private extension GridVisualMode {
    var uniformDisplayMode: GridStepDisplayMode? {
        switch self {
        case .block:
            return .block
        case .border:
            return .border
        case .line:
            return .line
        case .custom:
            return nil
        }
    }
}
