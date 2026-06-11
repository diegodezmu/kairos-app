import Foundation

final class DefaultDynamicsPublisher: DynamicsPublisher, Sendable {
    let localConsumer: (any LocalConsumer)?
    let networkBroadcaster: (any NetworkBroadcaster)?

    init(
        localConsumer: (any LocalConsumer)? = nil,
        networkBroadcaster: (any NetworkBroadcaster)? = nil
    ) {
        self.localConsumer = localConsumer
        self.networkBroadcaster = networkBroadcaster
    }

    func publish(_ sample: DynamicsSample) {
        localConsumer?.consume(sample)
        networkBroadcaster?.consume(sample)
    }
}
