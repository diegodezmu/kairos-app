import Foundation

private struct TimedDynamicsSample {
    var sample: DynamicsSample
    var timelineMilliseconds: UInt64
}

final class DefaultHistoryBuffer: HistoryBuffer, @unchecked Sendable {
    private let maximumRangeMilliseconds: UInt64
    private var samples: [TimedDynamicsSample] = []

    init(maximumRange: HistoryRange = .twoMinutes) {
        self.maximumRangeMilliseconds = UInt64(maximumRange.rawValue * 1_000.0)
    }

    func append(_ sample: DynamicsSample) {
        samples.append(
            TimedDynamicsSample(
                sample: sample,
                timelineMilliseconds: dynamicsTimelineMilliseconds(for: sample)
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

        let rangeMilliseconds = UInt64(range.rawValue * 1_000.0)
        let oldestIncludedMilliseconds = latest.timelineMilliseconds > rangeMilliseconds
            ? latest.timelineMilliseconds - rangeMilliseconds
            : 0

        let bucketWidthMilliseconds = Double(rangeMilliseconds) / Double(columnCount)
        guard bucketWidthMilliseconds > 0 else {
            return LaneHistorySnapshot(lane: lane, range: range, buckets: [])
        }

        // Group by an absolute time grid so a closed bucket keeps its recorded
        // shape while it scrolls left across the panel.
        var columns: [Int: [TimedDynamicsSample]] = [:]

        for entry in samples {
            let index = bucketIndex(
                for: entry.timelineMilliseconds,
                bucketWidthMilliseconds: bucketWidthMilliseconds
            )
            columns[index, default: []].append(entry)
        }

        let buckets: [LaneHistoryBucket] = columns.keys.sorted().compactMap { index -> LaneHistoryBucket? in
            guard bucketIntersectsVisibleWindow(
                index: index,
                oldestIncludedMilliseconds: oldestIncludedMilliseconds,
                latestMilliseconds: latest.timelineMilliseconds,
                bucketWidthMilliseconds: bucketWidthMilliseconds
            ), let entries = columns[index] else {
                return nil
            }

            return aggregate(entries: entries, lane: lane)
        }

        return LaneHistorySnapshot(
            lane: lane,
            range: range,
            buckets: buckets
        )
    }

    private func bucketIndex(
        for timelineMilliseconds: UInt64,
        bucketWidthMilliseconds: Double
    ) -> Int {
        let adjustedMilliseconds = timelineMilliseconds == 0
            ? 0
            : timelineMilliseconds - 1
        return Int(floor(Double(adjustedMilliseconds) / bucketWidthMilliseconds))
    }

    private func bucketIntersectsVisibleWindow(
        index: Int,
        oldestIncludedMilliseconds: UInt64,
        latestMilliseconds: UInt64,
        bucketWidthMilliseconds: Double
    ) -> Bool {
        let bucketStartMilliseconds = Double(index) * bucketWidthMilliseconds
        let bucketEndMilliseconds = bucketStartMilliseconds + bucketWidthMilliseconds

        return bucketEndMilliseconds >= Double(oldestIncludedMilliseconds)
            && bucketStartMilliseconds <= Double(latestMilliseconds)
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

        let oldestRetainedMilliseconds = latest.timelineMilliseconds > maximumRangeMilliseconds
            ? latest.timelineMilliseconds - maximumRangeMilliseconds
            : 0
        let firstRetainedIndex = samples.firstIndex {
            $0.timelineMilliseconds >= oldestRetainedMilliseconds
        } ?? samples.endIndex
        guard firstRetainedIndex > 0, firstRetainedIndex <= samples.count else {
            return
        }

        samples.removeFirst(firstRetainedIndex)
    }
}
