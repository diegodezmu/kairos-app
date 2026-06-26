import CoreAudio
import SwiftUI
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
            presets: makeStoredPresets(count: 5) { index in
                makePreset(seed: index)
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

    func testStepVisualStateHighlightsOnlyActiveStepWhenInsideAnticipationRange() {
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 13,
                stepCount: 16,
                activeStepIndex: 13,
                anticipationRange: 12..<16,
                resetMark: .none,
                mode: .block
            ),
            .anticipation
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 14,
                stepCount: 16,
                activeStepIndex: 13,
                anticipationRange: 12..<16,
                resetMark: .none,
                mode: .block
            ),
            .inactive
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 15,
                stepCount: 16,
                activeStepIndex: 13,
                anticipationRange: 12..<16,
                resetMark: .none,
                mode: .block
            ),
            .inactive
        )
    }

    func testStepVisualStateAppliesFigmaInactiveCheckpointRulesByLengthAndMode() {
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 2,
                stepCount: 4,
                activeStepIndex: nil,
                anticipationRange: nil,
                resetMark: .none,
                mode: .border
            ),
            .inactiveCheckpoint
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 2,
                stepCount: 4,
                activeStepIndex: nil,
                anticipationRange: nil,
                resetMark: .none,
                mode: .block
            ),
            .inactive
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 48,
                stepCount: 64,
                activeStepIndex: nil,
                anticipationRange: nil,
                resetMark: .none,
                mode: .lineSM
            ),
            .inactiveCheckpoint
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 112,
                stepCount: 128,
                activeStepIndex: nil,
                anticipationRange: nil,
                resetMark: .none,
                mode: .lineSM
            ),
            .inactiveCheckpoint
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 49,
                stepCount: 64,
                activeStepIndex: nil,
                anticipationRange: nil,
                resetMark: .none,
                mode: .lineSM
            ),
            .inactive
        )
    }

    func testGridPreviewDriverSixteenStepQuarterPulseTakesSixteenBeats() {
        let driver = GridPreviewDriver()
        let settings = [makeEnabledCycle()]
        let checkpoints: [(elapsedSeconds: TimeInterval, expectedStep: Int)] = [
            (0.0, 0),
            (0.5, 1),
            (1.0, 2),
            (4.0, 8),
            (7.5, 15),
            (8.0, 0),
        ]

        for checkpoint in checkpoints {
            let frame = driver.makeFrame(
                settings: settings,
                bpm: 120,
                offset: Offset(milliseconds: 0),
                elapsedSeconds: checkpoint.elapsedSeconds
            )

            XCTAssertEqual(
                frame.cycles.first?.activeStepIndex,
                checkpoint.expectedStep,
                "elapsed=\(checkpoint.elapsedSeconds)"
            )
        }
    }

    func testGridPreviewDriverCombinedResetPersistsForEntireStepZero() {
        let driver = GridPreviewDriver()
        let settings = [
            makeEnabledCycle(slot: .one, stepNumber: .sixteen),
            makeEnabledCycle(slot: .two, stepNumber: .eight),
            makeEnabledCycle(slot: .three, stepNumber: .thirtyTwo),
        ]

        _ = driver.makeFrame(
            settings: settings,
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 7.5
        )

        let resetFrame = driver.makeFrame(
            settings: settings,
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 8.0
        )
        XCTAssertEqual(
            resetMarks(in: resetFrame),
            [
                .one: .combined,
                .two: .combined,
                .three: .none,
            ]
        )

        let heldFrame = driver.makeFrame(
            settings: settings,
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 8.49
        )
        XCTAssertEqual(
            resetMarks(in: heldFrame),
            [
                .one: .combined,
                .two: .combined,
                .three: .none,
            ]
        )

        let releasedFrame = driver.makeFrame(
            settings: settings,
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 8.5
        )
        XCTAssertEqual(
            resetMarks(in: releasedFrame),
            [
                .one: .none,
                .two: .none,
                .three: .none,
            ]
        )
    }

    func testGridPreviewDriverGeneralResetPersistsForEntireStepZero() {
        let driver = GridPreviewDriver()
        let settings = [
            makeEnabledCycle(slot: .one, stepNumber: .two),
            makeEnabledCycle(slot: .two, stepNumber: .four),
            makeEnabledCycle(slot: .three, stepNumber: .eight),
            makeEnabledCycle(slot: .four, stepNumber: .sixteen),
        ]

        _ = driver.makeFrame(
            settings: settings,
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 7.5
        )

        let resetFrame = driver.makeFrame(
            settings: settings,
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 8.0
        )
        XCTAssertEqual(
            resetMarks(in: resetFrame),
            [
                .one: .general,
                .two: .general,
                .three: .general,
                .four: .general,
            ]
        )

        let heldFrame = driver.makeFrame(
            settings: settings,
            bpm: 120,
            offset: Offset(milliseconds: 0),
            elapsedSeconds: 8.49
        )
        XCTAssertEqual(
            resetMarks(in: heldFrame),
            [
                .one: .general,
                .two: .general,
                .three: .general,
                .four: .general,
            ]
        )
    }

    func testLevelMassFillSegmentsCoverFullWidthWithEmptyHistory() {
        let meterRect = CGRect(x: 24, y: 16, width: 240, height: 120)
        let latestHostTime: UInt64 = 30_000
        let contour = LevelMassGeometry.contourPoints(
            for: [],
            currentDB: -12,
            latestHostTime: latestHostTime,
            historyRange: .thirtySeconds,
            in: meterRect,
            value: \.meanDB
        )
        let segments = LevelMassGeometry.fillSegments(
            contourPoints: contour,
            meterRect: meterRect
        )

        XCTAssertEqual(
            contour,
            [
                CGPoint(x: meterRect.minX, y: contour[0].y),
                CGPoint(x: meterRect.maxX, y: contour[0].y),
            ]
        )
        XCTAssertEqual(
            segments,
            [
                [
                    CGPoint(x: meterRect.minX, y: meterRect.maxY),
                    CGPoint(x: meterRect.minX, y: contour[0].y),
                    CGPoint(x: meterRect.maxX, y: contour[0].y),
                    CGPoint(x: meterRect.maxX, y: meterRect.maxY),
                ],
            ]
        )
    }

    func testLevelMassFillSegmentsKeepVerticalEdgesForSingleValueHistory() {
        let meterRect = CGRect(x: 24, y: 16, width: 240, height: 120)
        let latestHostTime: UInt64 = 30_000
        let contour = LevelMassGeometry.contourPoints(
            for: [
                makeLevelColumn(
                    startHostTime: 28_800,
                    endHostTime: 29_400,
                    minimumDB: -24,
                    maximumDB: -6,
                    meanDB: -18
                ),
            ],
            currentDB: -9,
            latestHostTime: latestHostTime,
            historyRange: .thirtySeconds,
            in: meterRect,
            value: \.meanDB
        )
        let segments = LevelMassGeometry.fillSegments(
            contourPoints: contour,
            meterRect: meterRect
        )

        XCTAssertEqual(contour.first?.x, meterRect.minX)
        XCTAssertEqual(contour[0].y, contour[1].y)
        XCTAssertGreaterThan(contour[1].x, meterRect.minX)
        XCTAssertEqual(contour.last?.x, meterRect.maxX)
        XCTAssertEqual(
            contour.last?.y,
            contourYPosition(for: -9, in: meterRect)
        )
        XCTAssertEqual(
            segments.first,
            [
                CGPoint(x: meterRect.minX, y: meterRect.maxY),
                contour[0],
                contour[1],
                CGPoint(x: contour[1].x, y: meterRect.maxY),
            ]
        )
        XCTAssertEqual(segments.last?[1].x, contour[1].x)
        XCTAssertEqual(segments.last?[2].x, meterRect.maxX)
        XCTAssertEqual(segments.last?.last?.x, meterRect.maxX)
    }

    func testLevelMassFillSegmentsKeepVerticalEdgesForPartialHistory() {
        let meterRect = CGRect(x: 24, y: 16, width: 240, height: 120)
        let latestHostTime: UInt64 = 30_000
        let contour = LevelMassGeometry.contourPoints(
            for: [
                makeLevelColumn(
                    startHostTime: 23_000,
                    endHostTime: 24_000,
                    minimumDB: -40,
                    maximumDB: -20,
                    meanDB: -30
                ),
                makeLevelColumn(
                    startHostTime: 26_000,
                    endHostTime: 27_000,
                    minimumDB: -28,
                    maximumDB: -10,
                    meanDB: -18
                ),
                makeLevelColumn(
                    startHostTime: 28_000,
                    endHostTime: 29_000,
                    minimumDB: -18,
                    maximumDB: -3,
                    meanDB: -8
                ),
            ],
            currentDB: -22,
            latestHostTime: latestHostTime,
            historyRange: .thirtySeconds,
            in: meterRect,
            value: \.meanDB
        )
        let segments = LevelMassGeometry.fillSegments(
            contourPoints: contour,
            meterRect: meterRect
        )

        XCTAssertEqual(contour.first?.x, meterRect.minX)
        XCTAssertEqual(contour[0].y, contour[1].y)
        XCTAssertGreaterThan(contour[1].x, meterRect.minX)
        XCTAssertEqual(contour.last?.x, meterRect.maxX)
        XCTAssertEqual(
            contour.last?.y,
            contourYPosition(for: -22, in: meterRect)
        )
        XCTAssertEqual(segments.first?.first, CGPoint(x: meterRect.minX, y: meterRect.maxY))
        XCTAssertEqual(segments.last?.last, CGPoint(x: meterRect.maxX, y: meterRect.maxY))
        XCTAssertTrue(
            segments.allSatisfy { segment in
                segment.count == 4 &&
                segment[0].x == segment[1].x &&
                segment[2].x == segment[3].x
            }
        )
    }

    func testLevelMassContourUsesCurrentPointAtRightEdgeWithoutVerticalSpike() {
        let meterRect = CGRect(x: 24, y: 16, width: 240, height: 120)
        let latestHostTime: UInt64 = 30_000
        let contour = LevelMassGeometry.contourPoints(
            for: [
                makeLevelColumn(
                    startHostTime: 28_900,
                    endHostTime: latestHostTime,
                    minimumDB: -18,
                    maximumDB: -18,
                    meanDB: -18
                ),
            ],
            currentDB: -50,
            latestHostTime: latestHostTime,
            historyRange: .thirtySeconds,
            in: meterRect,
            value: \.meanDB
        )

        XCTAssertEqual(contour.last?.x, meterRect.maxX)
        XCTAssertEqual(contour.last?.y, contourYPosition(for: -50, in: meterRect))
        XCTAssertEqual(
            contour.filter { abs($0.x - meterRect.maxX) < 0.5 }.count,
            1,
            "The live edge should be represented by a single point at maxX."
        )
    }

    @MainActor
    func testLevelRendererEmptyHistoryFillsAcrossEntireWidth() throws {
        let width: CGFloat = 1_000
        let height = LevelRenderer.idealHeight(for: .singleExpanded)
        let latestHostTime: UInt64 = 30_000
        let frame = makeLevelFrameForRenderCheck(
            currentDB: -12,
            latestHostTime: latestHostTime,
            columns: []
        )
        let renderedImage = try renderLevelFrame(frame, width: width)
        let meterRect = expectedMeterRect(
            width: width,
            height: height
        )
        let contour = LevelMassGeometry.contourPoints(
            for: [],
            currentDB: -12,
            latestHostTime: latestHostTime,
            historyRange: .thirtySeconds,
            in: meterRect,
            value: \.meanDB
        )

        assertBaseFillVisible(
            in: renderedImage,
            renderedSize: CGSize(width: width, height: height),
            meterRect: meterRect,
            xFractions: [0.12, 0.5, 0.88]
        )
        assertBackgroundVisible(
            in: renderedImage,
            renderedSize: CGSize(width: width, height: height),
            meterRect: meterRect,
            contour: contour,
            xFractions: [0.12, 0.5, 0.88]
        )
    }

    @MainActor
    func testLevelRendererPartialHistoryKeepsFullBaseWithoutDiagonalGap() throws {
        let width: CGFloat = 1_000
        let height = LevelRenderer.idealHeight(for: .singleExpanded)
        let latestHostTime: UInt64 = 30_000
        let columns = [
            makeLevelColumn(
                startHostTime: 23_000,
                endHostTime: 24_000,
                minimumDB: -30,
                maximumDB: -30,
                meanDB: -30
            ),
            makeLevelColumn(
                startHostTime: 26_000,
                endHostTime: 27_000,
                minimumDB: -18,
                maximumDB: -18,
                meanDB: -18
            ),
            makeLevelColumn(
                startHostTime: 28_000,
                endHostTime: 29_000,
                minimumDB: -8,
                maximumDB: -8,
                meanDB: -8
            ),
        ]
        let frame = makeLevelFrameForRenderCheck(
            currentDB: -22,
            latestHostTime: latestHostTime,
            columns: columns
        )
        let renderedImage = try renderLevelFrame(frame, width: width)
        let meterRect = expectedMeterRect(
            width: width,
            height: height
        )
        let contour = LevelMassGeometry.contourPoints(
            for: columns,
            currentDB: -22,
            latestHostTime: latestHostTime,
            historyRange: .thirtySeconds,
            in: meterRect,
            value: \.meanDB
        )

        assertBaseFillVisible(
            in: renderedImage,
            renderedSize: CGSize(width: width, height: height),
            meterRect: meterRect,
            xFractions: [0.08, 0.32, 0.68, 0.92]
        )
        assertBackgroundVisible(
            in: renderedImage,
            renderedSize: CGSize(width: width, height: height),
            meterRect: meterRect,
            contour: contour,
            xFractions: [0.08, 0.32, 0.68, 0.92]
        )
    }

    @MainActor
    func testDesktopShellModelPlayStartsFromCurrentClockTime() {
        let renderedDate = Date(timeIntervalSinceReferenceDate: 100)
        let playDate = renderedDate.addingTimeInterval(1.5)
        let clock = MutableDateClock(now: renderedDate)
        let model = makeModel(clock: clock)

        _ = model.workspaceSnapshot(at: renderedDate)

        clock.now = playDate
        model.togglePlay()

        let snapshot = model.workspaceSnapshot(at: playDate)
        XCTAssertEqual(snapshot.gridFrame.cycles.first?.activeStepIndex, 0)
    }

    @MainActor
    func testDesktopShellModelResetPreviewReturnsGridToStepZeroWhilePlaying() {
        let startDate = Date(timeIntervalSinceReferenceDate: 200)
        let advancedDate = startDate.addingTimeInterval(1.0)
        let clock = MutableDateClock(now: startDate)
        let model = makeModel(clock: clock)

        model.togglePlay()

        let advancedSnapshot = model.workspaceSnapshot(at: advancedDate)
        XCTAssertEqual(advancedSnapshot.gridFrame.cycles.first?.activeStepIndex, 2)

        clock.now = advancedDate
        model.resetPreview()

        let resetSnapshot = model.workspaceSnapshot(at: advancedDate)
        XCTAssertEqual(resetSnapshot.gridFrame.cycles.first?.activeStepIndex, 0)

        let resumedDate = advancedDate.addingTimeInterval(0.5)
        let resumedSnapshot = model.workspaceSnapshot(at: resumedDate)
        XCTAssertEqual(resumedSnapshot.gridFrame.cycles.first?.activeStepIndex, 1)
    }

    private func makePreset(seed: Int) -> SettingsPreset {
        let syncSources: [SyncSource] = [
            .internalClock,
            .link,
            .usb,
            .link,
            .internalClock,
        ]
        let usbMIDISources: [USBMIDISourcePreference] = [
            .none,
            .none,
            USBMIDISourcePreference(
                uniqueID: 7302,
                displayName: "USB Clock Device"
            ),
            .none,
            USBMIDISourcePreference(
                uniqueID: 8821,
                displayName: "Rack Sync"
            ),
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
            usbMIDISource: usbMIDISources[seed],
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
                    targetMarginDB: Double(2 + ((seed + laneIndex) % 23)),
                    historyRange: historyRanges[(seed + laneIndex) % historyRanges.count]
                )
            }
        )
    }

    private func makeStoredPresets(
        count: Int,
        settings: (Int) -> SettingsPreset
    ) -> [StoredPreset] {
        (0 ..< count).map { index in
            StoredPreset(
                id: index == 0 ? StoredPreset.defaultID : "preset-\(index)",
                name: index == 0 ? StoredPreset.defaultName : "preset \(index)",
                settings: settings(index)
            )
        }
    }

    func testLegacyPresetPayloadDefaultsMetronomeToggleToOff() throws {
        let seededLibrary = PresetLibrary(
            presets: makeStoredPresets(count: 5) { _ in
                SettingsPreset(
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

    func testLegacyMidiSyncSourceDecodesAsInternalClock() throws {
        let data = Data(#""midiClock""#.utf8)
        let decoded = try JSONDecoder().decode(SyncSourceDTO.self, from: data)

        XCTAssertEqual(decoded, .internalClock)
        XCTAssertEqual(decoded.domainModel, .internalClock)
    }

    func testUSBSyncSourceDecodesAndMapsBackToDomain() throws {
        let data = Data(#""usb""#.utf8)
        let decoded = try JSONDecoder().decode(SyncSourceDTO.self, from: data)

        XCTAssertEqual(decoded, .usb)
        XCTAssertEqual(decoded.domainModel, .usb)
    }

    func testLegacyPresetPayloadDefaultsUSBMIDISourceToNone() throws {
        let seededLibrary = PresetLibrary(
            presets: makeStoredPresets(count: 5) { _ in
                SettingsPreset(
                    syncSource: .usb,
                    usbMIDISource: USBMIDISourcePreference(
                        uniqueID: 99,
                        displayName: "Master Clock"
                    ),
                    bpm: 120,
                    isMetronomeEnabled: false,
                    metronomePulse: .oneQuarter,
                    offset: Offset(milliseconds: 0),
                    isGridVisible: true,
                    isLevelVisible: true,
                    gridCycles: CycleSlot.allCases.map { SettingsDefaults.defaultGridCycle(for: $0) },
                    levelLanes: LaneID.allCases.map { SettingsDefaults.defaultLevelLane(for: $0) }
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
            settings.removeValue(forKey: "usbMIDISource")
            preset["settings"] = settings
            presets[index] = preset
        }

        jsonObject["presets"] = presets
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)
        let dto = try JSONDecoder().decode(PresetLibraryDTO.self, from: legacyData)
        let library = try dto.domainModel()

        XCTAssertTrue(
            library.presets.allSatisfy { $0.settings.usbMIDISource == .none }
        )
    }

    func testLegacyPresetSlotsMigrateToDynamicPresetIDs() throws {
        let seededLibrary = PresetLibrary(
            presets: makeStoredPresets(count: 5) { index in
                makePreset(seed: index)
            }
        )
        let data = try JSONEncoder().encode(PresetLibraryDTO(library: seededLibrary))
        var jsonObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var presets = try XCTUnwrap(jsonObject["presets"] as? [[String: Any]])
        let legacySlots = [
            "defaultPreset",
            "custom1",
            "custom2",
            "custom3",
            "custom4",
        ]

        for index in presets.indices {
            presets[index]["slot"] = legacySlots[index]
            presets[index].removeValue(forKey: "id")
            presets[index].removeValue(forKey: "name")
        }

        jsonObject["schemaVersion"] = 1
        jsonObject["presets"] = presets

        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)
        let dto = try JSONDecoder().decode(PresetLibraryDTO.self, from: legacyData)
        let library = try dto.domainModel()

        XCTAssertEqual(
            library.presets.map(\.id),
            [
                StoredPreset.defaultID,
                "starter-practice-grid",
                "starter-level-monitor",
                "starter-link-performance",
            ]
        )
        XCTAssertEqual(
            library.presets.map(\.name),
            [
                StoredPreset.defaultName,
                "practice grid",
                "level monitor",
                "link performance",
            ]
        )
    }

    func testPresetLibraryNormalizationInsertsDefaultAndRepairsBlankCustomNames() {
        let library = PresetLibrary(
            presets: [
                StoredPreset(
                    id: "custom-preset",
                    name: "   ",
                    settings: makePreset(seed: 1)
                )
            ]
        )

        XCTAssertEqual(library.presets.count, 2)
        XCTAssertEqual(library.presets.first?.id, StoredPreset.defaultID)
        XCTAssertEqual(library.presets.first?.name, StoredPreset.defaultName)
        XCTAssertEqual(library.presets.last?.id, "custom-preset")
        XCTAssertEqual(library.presets.last?.name, "preset")
    }

    func testFactoryPresetLibraryIncludesDefaultAndThreeStarterPresets() {
        XCTAssertEqual(
            PresetLibrary.factoryDefault.presets.map(\.id),
            [
                StoredPreset.defaultID,
                "starter-practice-grid",
                "starter-level-monitor",
                "starter-link-performance",
            ]
        )
        XCTAssertEqual(
            PresetLibrary.factoryDefault.presets.map(\.name),
            [
                StoredPreset.defaultName,
                "practice grid",
                "level monitor",
                "link performance",
            ]
        )
    }

    func testUSBMIDISyncTrackerFollowsStartClockAndStop() {
        var tracker = USBMIDISyncTracker()
        let tickIntervalNanos: UInt64 = 20_833_333

        tracker.process(.start, at: hostTime(nanoseconds: 0))
        for tickIndex in 1 ... 24 {
            tracker.process(
                .timingClock,
                at: hostTime(
                    nanoseconds: UInt64(tickIndex) * tickIntervalNanos
                )
            )
        }

        let playingSnapshot = tracker.snapshot(
            at: hostTime(nanoseconds: tickIntervalNanos * 24)
        )
        XCTAssertTrue(playingSnapshot.isPlaying)
        XCTAssertEqual(playingSnapshot.tempoBPM, 120, accuracy: 0.6)
        XCTAssertEqual(playingSnapshot.beat, 1, accuracy: 0.08)

        tracker.process(
            .stop,
            at: hostTime(nanoseconds: tickIntervalNanos * 24)
        )

        let stoppedSnapshot = tracker.snapshot(
            at: hostTime(nanoseconds: 2_000_000_000)
        )
        XCTAssertFalse(stoppedSnapshot.isPlaying)
        XCTAssertEqual(stoppedSnapshot.beat, 1, accuracy: 0.08)
    }

    func testUSBMIDISyncTrackerResumesFromSongPositionPointer() {
        var tracker = USBMIDISyncTracker()
        let baseNanos: UInt64 = 1_000_000_000
        let tickIntervalNanos: UInt64 = 20_833_333

        tracker.process(
            .songPositionPointer(32),
            at: hostTime(nanoseconds: baseNanos)
        )
        tracker.process(
            .continuePlayback,
            at: hostTime(nanoseconds: baseNanos)
        )

        for tickIndex in 1 ... 12 {
            tracker.process(
                .timingClock,
                at: hostTime(
                    nanoseconds: baseNanos + (UInt64(tickIndex) * tickIntervalNanos)
                )
            )
        }

        let snapshot = tracker.snapshot(
            at: hostTime(nanoseconds: baseNanos + (12 * tickIntervalNanos))
        )
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertTrue(snapshot.hasReceivedMessages)
        XCTAssertEqual(snapshot.tempoBPM, 120, accuracy: 0.6)
        XCTAssertEqual(snapshot.beat, 8.5, accuracy: 0.08)
    }

    func testUSBMIDIRawMessageParserParsesTransportMessages() {
        var parser = USBMIDIRawMessageParser()
        var messages: [USBMIDISystemMessage] = []

        parser.parse(bytes: [0xFA, 0xF8, 0xFC]) { message in
            messages.append(message)
        }

        XCTAssertEqual(
            messages,
            [.start, .timingClock, .stop]
        )
    }

    func testUSBMIDIRawMessageParserKeepsSongPositionAcrossRealtimeBytes() {
        var parser = USBMIDIRawMessageParser()
        var messages: [USBMIDISystemMessage] = []

        parser.parse(bytes: [0xF2, 0x20, 0xF8, 0x00, 0xFB]) { message in
            messages.append(message)
        }

        XCTAssertEqual(
            messages,
            [.timingClock, .songPositionPointer(32), .continuePlayback]
        )
    }

    @MainActor
    private func makeModel(clock: MutableDateClock) -> DesktopShellModel {
        let settings = SettingsModel()
        settings.updateGridCycle(slot: .one) { cycle in
            cycle.isEnabled = true
            cycle.stepNumber = .sixteen
            cycle.pulse = .oneQuarter
        }

        return DesktopShellModel(
            settings: settings,
            presetStore: nil,
            currentDate: { clock.now }
        )
    }

    private func makeEnabledCycle(
        slot: CycleSlot = .one,
        stepNumber: StepNumber = .sixteen,
        pulse: Pulse = .oneQuarter,
        visualMode: GridVisualMode = .block
    ) -> GridCycleSettings {
        GridCycleSettings(
            slot: slot,
            isEnabled: true,
            name: "Cycle \(slot.rawValue)",
            stepNumber: stepNumber,
            pulse: pulse,
            visualMode: visualMode
        )
    }

    private func resetMarks(in frame: GridRenderFrame) -> [CycleSlot: GridResetMark] {
        Dictionary(
            uniqueKeysWithValues: frame.cycles.map { cycle in
                (cycle.slot, cycle.resetMark)
            }
        )
    }

    private func hostTime(nanoseconds: UInt64) -> UInt64 {
        AudioConvertNanosToHostTime(nanoseconds)
    }

    @MainActor
    private func renderLevelFrame(
        _ frame: LevelRenderFrame,
        width: CGFloat
    ) throws -> CGImage {
        let height = LevelRenderer.idealHeight(for: .singleExpanded)
        let renderer = ImageRenderer(
            content: LevelRenderer(frame: frame)
                .frame(width: width, height: height)
        )
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "PresetStoreTests", code: 1)
        }

        return cgImage
    }

    private func makeLevelFrameForRenderCheck(
        currentDB: CGFloat,
        latestHostTime: UInt64,
        columns: [LevelRenderFrame.Lane.Column]
    ) -> LevelRenderFrame {
        let visibleFill = LevelResolvedColor(red: 32, green: 220, blue: 120)
        let hiddenColor = LevelResolvedColor(red: 0, green: 0, blue: 0, opacity: 0)
        let leftChannel = LevelRenderFrame.Lane.Channel(
            currentDB: currentDB,
            borderColor: hiddenColor,
            fillColor: visibleFill,
            columns: columns
        )
        let rightChannel = LevelRenderFrame.Lane.Channel(
            currentDB: -60,
            borderColor: hiddenColor,
            fillColor: hiddenColor,
            columns: []
        )

        return LevelRenderFrame(
            layout: .singleExpanded,
            lanes: [
                LevelRenderFrame.Lane(
                    lane: .one,
                    name: "Canta",
                    targetDB: -12,
                    historyRange: .thirtySeconds,
                    latestHostTime: latestHostTime,
                    left: leftChannel,
                    right: rightChannel
                ),
            ]
        )
    }

    private func makeLevelColumn(
        startHostTime: UInt64,
        endHostTime: UInt64,
        minimumDB: CGFloat,
        maximumDB: CGFloat,
        meanDB: CGFloat
    ) -> LevelRenderFrame.Lane.Column {
        LevelRenderFrame.Lane.Column(
            startHostTime: startHostTime,
            endHostTime: endHostTime,
            minimumDB: minimumDB,
            maximumDB: maximumDB,
            meanDB: meanDB
        )
    }

    private func expectedMeterRect(
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        let horizontalInset = min(16, canvasRect.width / 4)
        let topInset = min(36, canvasRect.height / 3)
        let bottomInset = min(16, canvasRect.height / 4)
        let contentRect = CGRect(
            x: canvasRect.minX + horizontalInset,
            y: canvasRect.minY + topInset,
            width: canvasRect.width - (horizontalInset * 2),
            height: canvasRect.height - topInset - bottomInset
        )
        let meterX = contentRect.minX + 32 + 24
        return CGRect(
            x: meterX,
            y: contentRect.minY,
            width: contentRect.width - (32 + 24),
            height: contentRect.height
        )
    }

    private func contourYPosition(
        for db: CGFloat,
        in rect: CGRect
    ) -> CGFloat {
        let clamped = min(max(db, -60), 0)
        let progress = (0 - clamped) / 60
        return rect.minY + (progress * rect.height)
    }

    private func assertBaseFillVisible(
        in image: CGImage,
        renderedSize: CGSize,
        meterRect: CGRect,
        xFractions: [CGFloat]
    ) {
        for xFraction in xFractions {
            let x = meterRect.minX + (meterRect.width * xFraction)
            let y = meterRect.maxY - 24
            let pixel = pixelColor(
                in: image,
                at: CGPoint(x: x, y: y),
                logicalSize: renderedSize
            )

            XCTAssertGreaterThan(
                pixel.green,
                0.45,
                "Expected fill at xFraction=\(xFraction), sample=\(pixel)"
            )
            XCTAssertLessThan(
                pixel.red,
                0.35,
                "Unexpected warm background at xFraction=\(xFraction), sample=\(pixel)"
            )
        }
    }

    private func assertBackgroundVisible(
        in image: CGImage,
        renderedSize: CGSize,
        meterRect: CGRect,
        contour: [CGPoint],
        xFractions: [CGFloat]
    ) {
        for xFraction in xFractions {
            let x = meterRect.minX + (meterRect.width * xFraction)
            let contourY = interpolatedContourY(at: x, contour: contour)
            let y = max(meterRect.minY + 12, contourY - 28)
            let pixel = pixelColor(
                in: image,
                at: CGPoint(x: x, y: y),
                logicalSize: renderedSize
            )

            XCTAssertLessThan(
                pixel.green,
                0.25,
                "Expected meter background above contour at xFraction=\(xFraction), sample=\(pixel)"
            )
        }
    }

    private func interpolatedContourY(
        at x: CGFloat,
        contour: [CGPoint]
    ) -> CGFloat {
        for (start, end) in zip(contour, contour.dropFirst()) {
            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)

            guard x >= minX, x <= maxX else {
                continue
            }

            guard start.x != end.x else {
                return min(start.y, end.y)
            }

            let progress = (x - start.x) / (end.x - start.x)
            return start.y + ((end.y - start.y) * progress)
        }

        return contour.last?.y ?? 0
    }

    private func pixelColor(
        in image: CGImage,
        at point: CGPoint,
        logicalSize: CGSize
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let scaleX = CGFloat(image.width) / logicalSize.width
        let scaleY = CGFloat(image.height) / logicalSize.height
        let pixelX = min(max(Int((point.x * scaleX).rounded()), 0), image.width - 1)
        let pixelY = min(max(Int((point.y * scaleY).rounded()), 0), image.height - 1)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bytesPerRow = image.width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        var bytes = [UInt8](repeating: 0, count: image.height * bytesPerRow)

        guard
            let context = CGContext(
                data: &bytes,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            XCTFail("Could not create bitmap context")
            return (0, 0, 0, 0)
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let offset = (pixelY * bytesPerRow) + (pixelX * 4)
        return (
            red: CGFloat(bytes[offset]) / 255.0,
            green: CGFloat(bytes[offset + 1]) / 255.0,
            blue: CGFloat(bytes[offset + 2]) / 255.0,
            alpha: CGFloat(bytes[offset + 3]) / 255.0
        )
    }

    func testMetronomeTickSchedulerDelaysQuarterClickWhenOffsetIsPositive() {
        let context = MetronomeScheduleContext(
            currentBeat: 0,
            tempoBPM: 120,
            pulse: .oneQuarter,
            offset: Offset(milliseconds: 125)
        )

        let ticks = MetronomeTickScheduler.ticksToSchedule(
            context: context,
            horizonSeconds: 0.5,
            lastScheduledTick: nil
        )

        guard let firstTick = ticks.first else {
            return XCTFail("Expected at least one scheduled click")
        }

        XCTAssertEqual(firstTick.tickIndex, 1)
        XCTAssertEqual(firstTick.delaySeconds, 0.375, accuracy: 0.000_1)
    }

    func testMetronomeTickSchedulerAdvancesQuarterClickWhenOffsetIsNegative() {
        let context = MetronomeScheduleContext(
            currentBeat: 0,
            tempoBPM: 120,
            pulse: .oneQuarter,
            offset: Offset(milliseconds: -125)
        )

        let ticks = MetronomeTickScheduler.ticksToSchedule(
            context: context,
            horizonSeconds: 0.5,
            lastScheduledTick: nil
        )

        guard let firstTick = ticks.first else {
            return XCTFail("Expected at least one scheduled click")
        }

        XCTAssertEqual(firstTick.tickIndex, 0)
        XCTAssertEqual(firstTick.delaySeconds, 0.125, accuracy: 0.000_1)
    }

    func testMetronomeTickSchedulerContinuesFromLastScheduledEighthTick() {
        let context = MetronomeScheduleContext(
            currentBeat: 4,
            tempoBPM: 120,
            pulse: .oneEighth,
            offset: Offset(milliseconds: 0)
        )

        let ticks = MetronomeTickScheduler.ticksToSchedule(
            context: context,
            horizonSeconds: 0.6,
            lastScheduledTick: 8
        )

        XCTAssertEqual(ticks.map(\.tickIndex), [9, 10])
        XCTAssertEqual(ticks.count, 2)
        XCTAssertEqual(ticks[0].delaySeconds, 0.25, accuracy: 0.000_1)
        XCTAssertEqual(ticks[1].delaySeconds, 0.5, accuracy: 0.000_1)
    }

    func testTransportBeatResolverUsesProvidedTempoForBeatProgress() throws {
        let context = try XCTUnwrap(
            TransportBeatResolver.resolve(
                elapsedSeconds: 2.0 / 3.0,
                tempoBPM: 90,
                offset: Offset(milliseconds: 100)
            )
        )

        XCTAssertEqual(context.elapsedSeconds, 2.0 / 3.0, accuracy: 0.000_1)
        XCTAssertEqual(context.tempoBPM, 90, accuracy: 0.000_1)
        XCTAssertEqual(context.beat, 1, accuracy: 0.000_1)
        XCTAssertEqual(context.effectiveBeat, 1.15, accuracy: 0.000_1)
    }

    func testTransportBeatResolverAdjustsExternalElapsedSecondsFromLocalReset() {
        let playingElapsed = TransportBeatResolver.adjustedExternalElapsedSeconds(
            rawElapsedSeconds: 6.5,
            resetOriginSeconds: 6.0,
            heldElapsedSeconds: 0.125,
            isPlaying: true
        )
        let heldElapsed = TransportBeatResolver.adjustedExternalElapsedSeconds(
            rawElapsedSeconds: 7.25,
            resetOriginSeconds: 6.0,
            heldElapsedSeconds: 0.5,
            isPlaying: false
        )

        XCTAssertEqual(playingElapsed, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(heldElapsed, 0.5, accuracy: 0.000_1)
    }

    func testGridPreviewDriverBeatBasedFrameUsesResolvedBeatDirectly() {
        let driver = GridPreviewDriver()
        let frame = driver.makeFrame(
            settings: [makeEnabledCycle()],
            beat: 1
        )

        XCTAssertEqual(frame.cycles.first?.activeStepIndex, 1)
    }

}

private final class MutableDateClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
