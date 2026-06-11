import AudioIOSpikeSupport
import Testing

@Test
func syntheticValidationStaysWithinToleranceAndDetectsClip() throws {
    let report = try SyntheticValidationRunner.run()

    #expect(report.passed)
    #expect(report.laneMeasurements.count == 4)

    for lane in report.laneMeasurements {
        #expect(abs(lane.deltaLeftDB) <= 0.5)
        #expect(abs(lane.deltaRightDB) <= 0.5)
    }

    #expect(report.clipTestLane == 3)
    #expect(report.clipTestRightChannelTriggered)
    #expect(report.clipTestLeftChannelStayedClear)
}

@Test
func ringBufferPreservesFIFOOrder() {
    let ringBuffer = DynamicsSampleRingBuffer(capacity: 8)
    let first = DynamicsSample(
        hostTime: 1,
        sampleTime: 1,
        frameCount: 128,
        sampleRate: 48_000,
        lane1: .zero,
        lane2: .zero,
        lane3: .zero,
        lane4: .zero
    )
    let second = DynamicsSample(
        hostTime: 2,
        sampleTime: 2,
        frameCount: 256,
        sampleRate: 48_000,
        lane1: .zero,
        lane2: .zero,
        lane3: .zero,
        lane4: .zero
    )

    #expect(ringBuffer.push(first))
    #expect(ringBuffer.push(second))
    #expect(ringBuffer.pop() == first)
    #expect(ringBuffer.pop() == second)
    #expect(ringBuffer.pop() == nil)
}
