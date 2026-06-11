import Foundation

private struct TimedDynamicsSample {
    var sample: DynamicsSample
    var timelineSeconds: Double
}

final class DefaultHistoryBuffer: HistoryBuffer, @unchecked Sendable {
    private let maximumRangeSeconds: Double
    private var samples: [TimedDynamicsSample] = []

    init(maximumRange: HistoryRange = .twoMinutes) {
        self.maximumRangeSeconds = maximumRange.rawValue
    }

    func append(_ sample: DynamicsSample) {
        samples.append(
            TimedDynamicsSample(
                sample: sample,
                timelineSeconds: dynamicsTimelineSeconds(for: sample)
            )
        )
        pruneIfNeeded()
    }

    func snapshot(
        for lane: LaneID,
        range: HistoryRange,
        columnCount: Int
    ) -> LaneHistorySnapshot {
        guard columnCount > 0, let latest = samples.last else {
            return LaneHistorySnapshot(lane: lane, range: range, buckets: [])
        }

        let oldestIncludedSecond = latest.timelineSeconds - range.rawValue
        let selectedSamples = samples.filter {
            $0.timelineSeconds >= oldestIncludedSecond && $0.timelineSeconds <= latest.timelineSeconds
        }

        guard !selectedSamples.isEmpty else {
            return LaneHistorySnapshot(lane: lane, range: range, buckets: [])
        }

        let bucketWidthSeconds = range.rawValue / Double(columnCount)
        var columns = Array(repeating: [TimedDynamicsSample](), count: columnCount)

        for entry in selectedSamples {
            let offsetSeconds = entry.timelineSeconds - oldestIncludedSecond
            let normalizedOffset = bucketWidthSeconds > 0 ? offsetSeconds / bucketWidthSeconds : 0
            let rawIndex = Int(normalizedOffset)
            let clampedIndex = min(max(rawIndex, 0), columnCount - 1)
            columns[clampedIndex].append(entry)
        }

        let buckets = columns.compactMap { entries in
            aggregate(entries: entries, lane: lane)
        }

        return LaneHistorySnapshot(
            lane: lane,
            range: range,
            buckets: buckets
        )
    }

    private func aggregate(
        entries: [TimedDynamicsSample],
        lane: LaneID
    ) -> LaneHistoryBucket? {
        guard let first = entries.first, let last = entries.last else {
            return nil
        }

        var minimumLeft = Float.greatestFiniteMagnitude
        var maximumLeft = -Float.greatestFiniteMagnitude
        var sumLeft: Float = 0
        var minimumRight = Float.greatestFiniteMagnitude
        var maximumRight = -Float.greatestFiniteMagnitude
        var sumRight: Float = 0

        for entry in entries {
            let laneSample = entry.sample.lane(lane)
            minimumLeft = min(minimumLeft, laneSample.rmsLeft)
            maximumLeft = max(maximumLeft, laneSample.rmsLeft)
            sumLeft += laneSample.rmsLeft
            minimumRight = min(minimumRight, laneSample.rmsRight)
            maximumRight = max(maximumRight, laneSample.rmsRight)
            sumRight += laneSample.rmsRight
        }

        let count = Float(entries.count)
        return LaneHistoryBucket(
            startHostTime: first.sample.hostTime,
            endHostTime: last.sample.hostTime,
            minimumRMSLeft: minimumLeft,
            maximumRMSLeft: maximumLeft,
            meanRMSLeft: sumLeft / count,
            minimumRMSRight: minimumRight,
            maximumRMSRight: maximumRight,
            meanRMSRight: sumRight / count
        )
    }

    private func pruneIfNeeded() {
        guard let latest = samples.last else {
            return
        }

        let oldestRetainedSecond = latest.timelineSeconds - maximumRangeSeconds
        let firstRetainedIndex = samples.firstIndex { $0.timelineSeconds >= oldestRetainedSecond } ?? samples.endIndex
        guard firstRetainedIndex > 0, firstRetainedIndex <= samples.count else {
            return
        }

        samples.removeFirst(firstRetainedIndex)
    }
}
