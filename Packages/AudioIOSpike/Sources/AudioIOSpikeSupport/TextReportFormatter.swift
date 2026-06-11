import Foundation

public enum TextReportFormatter {
    public static func render(_ report: AudioIOSpikeReport) -> String {
        var lines: [String] = []
        lines.append("AUDIO_IO_SPIKE_RESULT_BEGIN")

        let partA = report.partA
        lines.append("part_a.status=\(partA.passed ? "passed" : "failed")")
        lines.append(String(format: "part_a.sample_rate=%.0f", partA.sampleRate))
        lines.append(String(format: "part_a.window_ms=%.1f", partA.windowMs))
        lines.append("part_a.frame_count=\(partA.frameCount)")

        for lane in partA.laneMeasurements {
            lines.append(String(format: "part_a.lane%d.target_rms_left_dbfs=%.3f", lane.laneNumber, lane.targetRMSLeftDBFS))
            lines.append(String(format: "part_a.lane%d.target_rms_right_dbfs=%.3f", lane.laneNumber, lane.targetRMSRightDBFS))
            lines.append(String(format: "part_a.lane%d.measured_rms_left_dbfs=%.3f", lane.laneNumber, lane.measuredRMSLeftDBFS))
            lines.append(String(format: "part_a.lane%d.measured_rms_right_dbfs=%.3f", lane.laneNumber, lane.measuredRMSRightDBFS))
            lines.append(String(format: "part_a.lane%d.delta_left_db=%.3f", lane.laneNumber, lane.deltaLeftDB))
            lines.append(String(format: "part_a.lane%d.delta_right_db=%.3f", lane.laneNumber, lane.deltaRightDB))
        }

        lines.append("part_a.clip_test_lane=\(partA.clipTestLane)")
        lines.append(String(format: "part_a.clip_test_injected_peak=%.3f", partA.clipTestInjectedPeak))
        lines.append("part_a.clip_test_right_triggered=\(partA.clipTestRightChannelTriggered)")
        lines.append("part_a.clip_test_left_stayed_clear=\(partA.clipTestLeftChannelStayedClear)")

        let partB = report.partB
        lines.append("part_b.status=\(partB.status.rawValue)")
        lines.append("part_b.reason=\(partB.reason)")
        lines.append("part_b.device_name=\(partB.deviceName ?? "n/a")")
        lines.append("part_b.device_uid=\(partB.deviceUID ?? "n/a")")
        lines.append("part_b.input_channels=\(partB.inputChannels.map(String.init) ?? "n/a")")
        lines.append("part_b.tap_channels=\(partB.tapChannelCount.map(String.init) ?? "n/a")")
        lines.append("part_b.measured_channels=\(partB.measuredChannels.map(String.init) ?? "n/a")")
        lines.append("part_b.requested_frame_count=\(partB.requestedFrameCount.map(String.init) ?? "n/a")")
        lines.append("part_b.observed_frame_count=\(partB.observedFrameCount.map(String.init) ?? "n/a")")
        lines.append("part_b.callback_count=\(partB.callbackCount)")
        lines.append("part_b.published_sample_count=\(partB.publishedSampleCount)")
        lines.append("part_b.dropped_sample_count=\(partB.droppedSampleCount)")

        if let firstSample = partB.firstSample {
            append(sample: firstSample, prefix: "part_b.first_sample", lines: &lines)
        }
        if let lastSample = partB.lastSample {
            append(sample: lastSample, prefix: "part_b.last_sample", lines: &lines)
        }

        lines.append("AUDIO_IO_SPIKE_RESULT_END")
        return lines.joined(separator: "\n")
    }

    private static func append(
        sample: DynamicsSample,
        prefix: String,
        lines: inout [String]
    ) {
        lines.append("\(prefix).host_time=\(sample.hostTime)")
        lines.append("\(prefix).sample_time=\(sample.sampleTime)")
        lines.append("\(prefix).frame_count=\(sample.frameCount)")
        lines.append(String(format: "\(prefix).sample_rate=%.0f", sample.sampleRate))

        for laneIndex in 0..<audioIOSpikeLaneCount {
            let lane = sample.lane(laneIndex)
            let laneNumber = laneIndex + 1
            lines.append(String(format: "\(prefix).lane%d.rms_left=%.6f", laneNumber, lane.rmsLeft))
            lines.append(String(format: "\(prefix).lane%d.rms_right=%.6f", laneNumber, lane.rmsRight))
            lines.append(String(format: "\(prefix).lane%d.peak_left=%.6f", laneNumber, lane.peakLeft))
            lines.append(String(format: "\(prefix).lane%d.peak_right=%.6f", laneNumber, lane.peakRight))
            lines.append("\(prefix).lane\(laneNumber).clip_left=\(lane.clipLeft)")
            lines.append("\(prefix).lane\(laneNumber).clip_right=\(lane.clipRight)")
        }
    }
}
