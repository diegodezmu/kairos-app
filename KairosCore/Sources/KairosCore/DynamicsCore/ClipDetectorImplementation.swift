import Foundation

final class DefaultClipDetector: ClipDetector, @unchecked Sendable {
    private let holdDurationMilliseconds: UInt64
    private let nowMilliseconds: @Sendable () -> UInt64
    private var leftLastClipMilliseconds: UInt64?
    private var rightLastClipMilliseconds: UInt64?

    init(
        holdDurationMilliseconds: UInt64 = dynamicsClipHoldDurationMilliseconds,
        nowMilliseconds: @escaping @Sendable () -> UInt64 = DefaultClipDetector.systemNowMilliseconds
    ) {
        self.holdDurationMilliseconds = holdDurationMilliseconds
        self.nowMilliseconds = nowMilliseconds
    }

    func isClipping(peakAmplitude: Float) -> Bool {
        peakAmplitude > dynamicsClipThresholdAmplitude
    }

    func detectClipping(
        leftPeak: Float,
        rightPeak: Float
    ) -> (left: Bool, right: Bool) {
        detectClipping(
            leftPeak: leftPeak,
            rightPeak: rightPeak,
            atMilliseconds: nowMilliseconds()
        )
    }

    func detectClipping(
        leftPeak: Float,
        rightPeak: Float,
        atMilliseconds currentMilliseconds: UInt64
    ) -> (left: Bool, right: Bool) {
        if isClipping(peakAmplitude: leftPeak) {
            leftLastClipMilliseconds = currentMilliseconds
        }

        if isClipping(peakAmplitude: rightPeak) {
            rightLastClipMilliseconds = currentMilliseconds
        }

        return (
            left: isTailActive(lastClipMilliseconds: leftLastClipMilliseconds, currentMilliseconds: currentMilliseconds),
            right: isTailActive(lastClipMilliseconds: rightLastClipMilliseconds, currentMilliseconds: currentMilliseconds)
        )
    }

    func tailProgress(atMilliseconds currentMilliseconds: UInt64) -> (left: Float, right: Float) {
        (
            left: tailProgress(
                lastClipMilliseconds: leftLastClipMilliseconds,
                currentMilliseconds: currentMilliseconds
            ),
            right: tailProgress(
                lastClipMilliseconds: rightLastClipMilliseconds,
                currentMilliseconds: currentMilliseconds
            )
        )
    }

    func reset() {
        leftLastClipMilliseconds = nil
        rightLastClipMilliseconds = nil
    }

    private func isTailActive(
        lastClipMilliseconds: UInt64?,
        currentMilliseconds: UInt64
    ) -> Bool {
        tailProgress(
            lastClipMilliseconds: lastClipMilliseconds,
            currentMilliseconds: currentMilliseconds
        ) > 0
    }

    private func tailProgress(
        lastClipMilliseconds: UInt64?,
        currentMilliseconds: UInt64
    ) -> Float {
        guard let lastClipMilliseconds else {
            return 0
        }

        let elapsedMilliseconds = currentMilliseconds >= lastClipMilliseconds
            ? currentMilliseconds - lastClipMilliseconds
            : 0
        guard elapsedMilliseconds < holdDurationMilliseconds else {
            return 0
        }

        let progress = 1 - (Float(elapsedMilliseconds) / Float(holdDurationMilliseconds))
        return max(progress, 0)
    }

    private static func systemNowMilliseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }
}
