import Darwin
import Foundation

struct LevelTelemetrySourceState: Identifiable, Equatable, Sendable {
    let sourceSlot: Int
    var sourceName: String
    var rmsLeft: Float
    var rmsRight: Float
    var peakLeft: Float
    var peakRight: Float
    var isActive: Bool
    var hasConflict: Bool
    var lastReceivedAt: Date?
    var endpoint: String?

    var id: Int { sourceSlot }

    var displayName: String {
        let trimmedName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Source \(sourceSlot)"
        }

        return "Source \(sourceSlot) · \(trimmedName)"
    }

    var menuTitle: String {
        hasConflict ? "\(displayName) · Conflict" : displayName
    }
}

struct LevelTelemetrySnapshot: Equatable, Sendable {
    let isListening: Bool
    let port: UInt16
    let errorMessage: String?
    let sources: [LevelTelemetrySourceState]

    var activeSourceCount: Int {
        sources.filter(\.isActive).count
    }

    var conflictSourceSlots: [Int] {
        sources
            .filter(\.hasConflict)
            .map(\.sourceSlot)
    }

    var statusText: String {
        if let errorMessage {
            return errorMessage
        }

        guard isListening else {
            return "Receiver stopped."
        }

        if activeSourceCount == 0 {
            return "Waiting for Max for Live sources on UDP \(port)."
        }

        return "Receiving \(activeSourceCount) source\(activeSourceCount == 1 ? "" : "s") on UDP \(port)."
    }

    func source(for slot: Int?) -> LevelTelemetrySourceState? {
        guard let slot else {
            return nil
        }

        return sources.first { $0.sourceSlot == slot }
    }
}

@MainActor
final class LevelTelemetryReceiver {
    let port: UInt16

    private let staleInterval: TimeInterval
    private let socketQueue = DispatchQueue(label: "kairos.level.telemetry.socket", qos: .userInitiated)
    private var socketFD: Int32 = -1
    private var socketSource: DispatchSourceRead?
    private var errorMessage: String?
    private var sourceTargets: [Int: LevelTelemetryTarget] = [:]

    init(
        port: UInt16 = 51515,
        staleInterval: TimeInterval = 2
    ) {
        self.port = port
        self.staleInterval = staleInterval
    }

    var isListening: Bool {
        socketFD != -1
    }

    func start() {
        guard socketFD == -1 else {
            return
        }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            errorMessage = socketError("socket")
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            errorMessage = socketError("bind")
            close(fd)
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: socketQueue)
        source.setEventHandler(handler: Self.makeSocketEventHandler(receiver: self, fd: fd))
        source.setCancelHandler(handler: Self.makeSocketCancelHandler(fd: fd))
        source.resume()

        socketFD = fd
        socketSource = source
        errorMessage = nil
    }

    func stop() {
        socketSource?.cancel()
        socketSource = nil
        socketFD = -1
        sourceTargets.removeAll()
    }

    func snapshot(at date: Date) -> LevelTelemetrySnapshot {
        pruneStaleSources(at: date)

        let sources = sourceTargets.values
            .map { target in
                let freshSenderCount = target.senders.values.filter {
                    date.timeIntervalSince($0) <= staleInterval
                }.count

                return LevelTelemetrySourceState(
                    sourceSlot: target.sourceSlot,
                    sourceName: target.sourceName,
                    rmsLeft: target.rmsLeft,
                    rmsRight: target.rmsRight,
                    peakLeft: target.peakLeft,
                    peakRight: target.peakRight,
                    isActive: true,
                    hasConflict: freshSenderCount > 1,
                    lastReceivedAt: target.lastReceivedAt,
                    endpoint: target.endpoint
                )
            }
            .sorted { lhs, rhs in
                lhs.sourceSlot < rhs.sourceSlot
            }

        return LevelTelemetrySnapshot(
            isListening: isListening,
            port: port,
            errorMessage: errorMessage,
            sources: sources
        )
    }

    private nonisolated func drainSocket(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 2048)

        while true {
            var address = sockaddr_in()
            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)

            let count = withUnsafeMutablePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    recvfrom(fd, &buffer, buffer.count, 0, socketAddress, &addressLength)
                }
            }

            if count > 0 {
                let data = Data(buffer.prefix(count))
                let endpoint = endpointDescription(for: address)
                Task { @MainActor in
                    self.handlePacketData(data, endpoint: endpoint)
                }
                continue
            }

            if count == -1 && (errno == EWOULDBLOCK || errno == EAGAIN) {
                return
            }

            return
        }
    }

    private nonisolated func endpointDescription(for address: sockaddr_in) -> String {
        var mutableAddress = address.sin_addr
        var hostBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let host = inet_ntop(AF_INET, &mutableAddress, &hostBuffer, socklen_t(INET_ADDRSTRLEN))
            .map { String(cString: $0) } ?? "unknown"
        let port = UInt16(bigEndian: address.sin_port)
        return "\(host):\(port)"
    }

    private nonisolated static func makeSocketEventHandler(
        receiver: LevelTelemetryReceiver,
        fd: Int32
    ) -> @Sendable () -> Void {
        { [weak receiver] in
            receiver?.drainSocket(fd)
        }
    }

    private nonisolated static func makeSocketCancelHandler(
        fd: Int32
    ) -> @Sendable () -> Void {
        {
            Darwin.close(fd)
        }
    }

    private func socketError(_ operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }

    private func handlePacketData(_ data: Data, endpoint: String) {
        guard let packet = decodePacket(from: data) else {
            return
        }

        guard let sourceSlot = packet.resolvedSourceSlot, sourceSlot > 0 else {
            return
        }

        let now = Date()
        let senderIdentity = packet.senderId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSenderIdentity = senderIdentity?.isEmpty == false ? senderIdentity! : endpoint

        var target = sourceTargets[sourceSlot] ?? LevelTelemetryTarget(
            sourceSlot: sourceSlot,
            sourceName: packet.sourceName ?? "",
            rmsLeft: 0,
            rmsRight: 0,
            peakLeft: 0,
            peakRight: 0,
            endpoint: endpoint,
            lastReceivedAt: now,
            senders: [:]
        )

        target.sourceName = packet.sourceName ?? target.sourceName
        target.rmsLeft = packet.rmsLeft.clamped01
        target.rmsRight = packet.rmsRight.clamped01
        target.peakLeft = packet.peakLeft.clamped01
        target.peakRight = packet.peakRight.clamped01
        target.endpoint = endpoint
        target.lastReceivedAt = now
        target.senders[resolvedSenderIdentity] = now

        sourceTargets[sourceSlot] = target
        errorMessage = nil
    }

    private func pruneStaleSources(at date: Date) {
        sourceTargets = sourceTargets.reduce(into: [:]) { partialResult, entry in
            var target = entry.value
            target.senders = target.senders.filter { _, lastSeenAt in
                date.timeIntervalSince(lastSeenAt) <= staleInterval
            }

            guard date.timeIntervalSince(target.lastReceivedAt) <= staleInterval else {
                return
            }

            partialResult[entry.key] = target
        }
    }

    private func decodePacket(from data: Data) -> LevelTelemetryPacket? {
        let decoder = JSONDecoder()

        if let packet = try? decoder.decode(LevelTelemetryPacket.self, from: data) {
            return packet.isSupported ? packet : nil
        }

        guard var text = String(data: data, encoding: .utf8) else {
            return nil
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0;")))

        if let quotedData = text.data(using: .utf8),
           let unwrapped = try? decoder.decode(String.self, from: quotedData) {
            text = unwrapped
        }

        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }

        let candidate = String(text[start...end])
        let candidates = [
            candidate,
            candidate.replacingOccurrences(of: "\\\"", with: "\"")
        ]

        for candidate in candidates {
            guard let candidateData = candidate.data(using: .utf8),
                  let packet = try? decoder.decode(LevelTelemetryPacket.self, from: candidateData),
                  packet.isSupported else {
                continue
            }

            return packet
        }

        return nil
    }
}

private struct LevelTelemetryTarget {
    let sourceSlot: Int
    var sourceName: String
    var rmsLeft: Float
    var rmsRight: Float
    var peakLeft: Float
    var peakRight: Float
    var endpoint: String
    var lastReceivedAt: Date
    var senders: [String: Date]
}

private struct LevelTelemetryPacket: Decodable {
    let type: String
    let sourceSlot: Int?
    let slot: Int?
    let senderId: String?
    let sourceName: String?
    let rmsLeft: Float
    let rmsRight: Float
    let peakLeft: Float
    let peakRight: Float

    private enum CodingKeys: String, CodingKey {
        case type
        case sourceSlot
        case slot
        case senderId
        case sourceName
        case rmsLeft = "rmsL"
        case rmsRight = "rmsR"
        case peakLeft = "peakL"
        case peakRight = "peakR"
    }

    var resolvedSourceSlot: Int? {
        sourceSlot ?? slot
    }

    var isSupported: Bool {
        switch type {
        case "kairos.level.v1", "gridlink.rms.v1":
            return true
        default:
            return false
        }
    }
}

private extension Float {
    var clamped01: Float {
        min(max(self, 0), 1)
    }
}
