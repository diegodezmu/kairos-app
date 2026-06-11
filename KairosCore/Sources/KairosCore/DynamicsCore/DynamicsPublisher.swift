import Foundation

/// Common consumer interface for published dynamics snapshots.
public protocol DynamicsConsumer: Sendable {
    func consume(_ sample: DynamicsSample)
}

/// Fan-out seam between audio measurement and its downstream consumers.
public protocol DynamicsPublisher: Sendable {
    /// v1 local render/UI consumer.
    var localConsumer: (any LocalConsumer)? { get }

    /// Phase 2 remote broadcast seam.
    var networkBroadcaster: (any NetworkBroadcaster)? { get }

    func publish(_ sample: DynamicsSample)
}
