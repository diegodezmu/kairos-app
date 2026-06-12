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

    func testStepVisualStateHighlightsOnlyActiveStepWhenInsideAnticipationRange() {
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 13,
                activeStepIndex: 13,
                anticipationRange: 12..<16,
                resetMark: .none
            ),
            .anticipation
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 12,
                activeStepIndex: 13,
                anticipationRange: 12..<16,
                resetMark: .none
            ),
            .inactive
        )
        XCTAssertEqual(
            GridStepVisualState.resolve(
                stepIndex: 15,
                activeStepIndex: 13,
                anticipationRange: 12..<16,
                resetMark: .none
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
        XCTAssertEqual(contour[1].y, contour[2].y)
        XCTAssertGreaterThan(contour[1].x, meterRect.minX)
        XCTAssertEqual(contour[contour.count - 2].x, meterRect.maxX)
        XCTAssertEqual(contour.last?.x, meterRect.maxX)
        XCTAssertEqual(
            segments.first,
            [
                CGPoint(x: meterRect.minX, y: meterRect.maxY),
                contour[0],
                contour[1],
                CGPoint(x: contour[1].x, y: meterRect.maxY),
            ]
        )
        XCTAssertEqual(segments.last?.first?.x, meterRect.maxX)
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
        XCTAssertEqual(contour[contour.count - 2].x, meterRect.maxX)
        XCTAssertEqual(contour.last?.x, meterRect.maxX)
        XCTAssertGreaterThan(contour.last!.y, contour[contour.count - 2].y)
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

        _ = model.snapshot(at: renderedDate)

        clock.now = playDate
        model.togglePlay()

        let snapshot = model.snapshot(at: playDate)
        XCTAssertEqual(snapshot.gridFrame.cycles.first?.activeStepIndex, 0)
    }

    @MainActor
    func testDesktopShellModelResetPreviewReturnsGridToStepZeroWhilePlaying() {
        let startDate = Date(timeIntervalSinceReferenceDate: 200)
        let advancedDate = startDate.addingTimeInterval(1.0)
        let clock = MutableDateClock(now: startDate)
        let model = makeModel(clock: clock)

        model.togglePlay()

        let advancedSnapshot = model.snapshot(at: advancedDate)
        XCTAssertEqual(advancedSnapshot.gridFrame.cycles.first?.activeStepIndex, 2)

        clock.now = advancedDate
        model.resetPreview()

        let resetSnapshot = model.snapshot(at: advancedDate)
        XCTAssertEqual(resetSnapshot.gridFrame.cycles.first?.activeStepIndex, 0)

        let resumedDate = advancedDate.addingTimeInterval(0.5)
        let resumedSnapshot = model.snapshot(at: resumedDate)
        XCTAssertEqual(resumedSnapshot.gridFrame.cycles.first?.activeStepIndex, 1)
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
                    targetDB: -12,
                    historyRange: .thirtySeconds,
                    latestHostTime: latestHostTime,
                    left: leftChannel,
                    right: rightChannel
                ),
            ],
            generalResetMarks: []
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
        let contentRect = canvasRect.insetBy(
            dx: min(16, canvasRect.width / 4),
            dy: min(16, canvasRect.height / 4)
        )
        let meterX = contentRect.minX + 32 + 24
        return CGRect(
            x: meterX,
            y: contentRect.minY,
            width: contentRect.width - (32 + 24),
            height: contentRect.height
        )
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

}

private final class MutableDateClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
