import Foundation

/// Audio-to-data seam owner. Implementations must publish through `DynamicsPublisher`.
public protocol AudioEngine: Sendable {
    var publisher: any DynamicsPublisher { get }
}
