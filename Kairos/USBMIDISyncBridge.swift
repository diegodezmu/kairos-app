import CoreAudio
import CoreMIDI
import Foundation

struct USBMIDISourceDescriptor: Identifiable, Equatable, Sendable {
    let uniqueID: Int32
    let displayName: String

    var id: Int32 {
        uniqueID
    }
}

struct USBMIDISyncSnapshot: Equatable, Sendable {
    let tempoBPM: Double
    let beat: Double
    let isPlaying: Bool
    let isBridgeAvailable: Bool
    let hasSelection: Bool
    let isSelectedSourceAvailable: Bool
    let hasReceivedMessages: Bool
    let selectedSourceName: String?

    var elapsedSeconds: TimeInterval {
        guard tempoBPM > 0 else {
            return 0
        }

        return beat / (tempoBPM / 60.0)
    }
}

enum USBMIDISystemMessage: Equatable, Sendable {
    case timingClock
    case start
    case continuePlayback
    case stop
    case songPositionPointer(UInt16)
}

struct USBMIDISyncTrackerSnapshot {
    let tempoBPM: Double
    let beat: Double
    let isPlaying: Bool
    let hasReceivedMessages: Bool
}

struct USBMIDIRawMessageParser {
    private var isAwaitingSongPosition = false
    private var songPositionData: [UInt8] = []

    mutating func reset() {
        isAwaitingSongPosition = false
        songPositionData.removeAll(keepingCapacity: true)
    }

    mutating func parse<S: Sequence>(
        bytes: S,
        emit: (USBMIDISystemMessage) -> Void
    ) where S.Element == UInt8 {
        for byte in bytes {
            parse(byte: byte, emit: emit)
        }
    }

    private mutating func parse(
        byte: UInt8,
        emit: (USBMIDISystemMessage) -> Void
    ) {
        switch byte {
        case 0xF8:
            emit(.timingClock)
        case 0xFA:
            emit(.start)
        case 0xFB:
            emit(.continuePlayback)
        case 0xFC:
            emit(.stop)
        case 0xF2:
            isAwaitingSongPosition = true
            songPositionData.removeAll(keepingCapacity: true)
        case 0x80 ... 0xF7:
            isAwaitingSongPosition = false
            songPositionData.removeAll(keepingCapacity: true)
        default:
            guard isAwaitingSongPosition else {
                return
            }

            songPositionData.append(byte & 0x7F)
            guard songPositionData.count == 2 else {
                return
            }

            let position = UInt16(songPositionData[0])
                | (UInt16(songPositionData[1]) << 7)
            isAwaitingSongPosition = false
            songPositionData.removeAll(keepingCapacity: true)
            emit(.songPositionPointer(position))
        }
    }
}

struct USBMIDISyncTracker {
    private static let clocksPerQuarterNote = 24.0
    private static let songPositionUnitsPerQuarterNote = 4.0
    private static let intervalWindowSize = 12

    private var tempoBPM = 0.0
    private var isPlaying = false
    private var anchorBeat = 0.0
    private var anchorHostTime: UInt64 = 0
    private var originHostTime: UInt64?
    private var hasOrigin = false
    private var hasReceivedMessages = false
    private var lastTickHostTime: UInt64?
    private var lastTickBeat: Double?
    private var tickIntervals: [Double] = []

    mutating func reset() {
        self = USBMIDISyncTracker()
    }

    mutating func process(
        _ message: USBMIDISystemMessage,
        at hostTime: UInt64
    ) {
        hasReceivedMessages = true

        switch message {
        case .timingClock:
            handleTimingClock(at: hostTime)
        case .start:
            tickIntervals.removeAll(keepingCapacity: true)
            lastTickHostTime = nil
            lastTickBeat = nil
            setBeat(0, at: hostTime)
            isPlaying = true
            originHostTime = hostTime
            hasOrigin = true
        case .continuePlayback:
            tickIntervals.removeAll(keepingCapacity: true)
            lastTickHostTime = nil
            lastTickBeat = nil
            let resumedBeat = beat(at: hostTime)
            setBeat(resumedBeat, at: hostTime)
            isPlaying = true
            if !hasOrigin {
                originHostTime = hostTime
                hasOrigin = true
            }
        case .stop:
            let frozenBeat = beat(at: hostTime)
            lastTickBeat = nil
            setBeat(frozenBeat, at: hostTime)
            isPlaying = false
        case let .songPositionPointer(position):
            let beatPosition = Double(position) / Self.songPositionUnitsPerQuarterNote
            lastTickBeat = nil
            setBeat(beatPosition, at: hostTime)
        }
    }

    func snapshot(at hostTime: UInt64) -> USBMIDISyncTrackerSnapshot {
        USBMIDISyncTrackerSnapshot(
            tempoBPM: tempoBPM,
            beat: beat(at: hostTime),
            isPlaying: isPlaying,
            hasReceivedMessages: hasReceivedMessages
        )
    }

    private mutating func handleTimingClock(at hostTime: UInt64) {
        let nextBeat = (lastTickBeat ?? beat(at: hostTime)) + (1.0 / Self.clocksPerQuarterNote)

        if let lastTickHostTime {
            let deltaSeconds = Self.deltaSeconds(
                from: lastTickHostTime,
                to: hostTime
            )

            if deltaSeconds > 0 {
                tickIntervals.append(deltaSeconds)
                if tickIntervals.count > Self.intervalWindowSize {
                    tickIntervals.removeFirst(
                        tickIntervals.count - Self.intervalWindowSize
                    )
                }

                let meanTickInterval = tickIntervals.reduce(0, +) / Double(tickIntervals.count)
                let nextTempo = 60.0 / (meanTickInterval * Self.clocksPerQuarterNote)
                updateTempoPreservingContinuity(nextTempo, at: hostTime)
            }
        }

        lastTickHostTime = hostTime

        guard isPlaying else {
            return
        }

        lastTickBeat = nextBeat
        setBeat(nextBeat, at: hostTime)
    }

    private mutating func updateTempoPreservingContinuity(
        _ nextTempo: Double,
        at hostTime: UInt64
    ) {
        guard nextTempo > 0 else {
            return
        }

        let continuousBeat = beat(at: hostTime)
        anchorBeat = continuousBeat
        anchorHostTime = hostTime
        tempoBPM = nextTempo
    }

    private mutating func setBeat(
        _ beat: Double,
        at hostTime: UInt64
    ) {
        anchorBeat = beat
        anchorHostTime = hostTime
    }

    private func beat(at hostTime: UInt64) -> Double {
        guard isPlaying, tempoBPM > 0 else {
            return anchorBeat
        }

        let deltaSeconds = Self.deltaSeconds(
            from: anchorHostTime,
            to: hostTime
        )
        let deltaBeats = deltaSeconds * (tempoBPM / 60.0)
        return anchorBeat + deltaBeats
    }

    private static func deltaSeconds(
        from startHostTime: UInt64,
        to endHostTime: UInt64
    ) -> Double {
        if endHostTime >= startHostTime {
            let delta = endHostTime - startHostTime
            return Double(AudioConvertHostTimeToNanos(delta)) / 1_000_000_000.0
        }

        let delta = startHostTime - endHostTime
        return -Double(AudioConvertHostTimeToNanos(delta)) / 1_000_000_000.0
    }
}

private struct USBMIDISourceRecord {
    let descriptor: USBMIDISourceDescriptor
    let endpoint: MIDIEndpointRef
}

private final class USBMIDISyncBridgeReference {
    weak var bridge: USBMIDISyncBridge?
}

final class USBMIDISyncBridge {
    private let lock = NSLock()
    private let client: MIDIClientRef
    private let inputPort: MIDIPortRef
    private let isBridgeAvailable: Bool
    private let bridgeReference: USBMIDISyncBridgeReference

    private var tracker = USBMIDISyncTracker()
    private var rawMessageParser = USBMIDIRawMessageParser()
    private var selectedSource = USBMIDISourcePreference.none
    private var cachedSources: [USBMIDISourceRecord] = []
    private var connectedSourceUniqueID: Int32?
    private var connectedEndpoint: MIDIEndpointRef = 0

    init() {
        let bridgeReference = USBMIDISyncBridgeReference()
        var nextClient = MIDIClientRef()
        var nextInputPort = MIDIPortRef()
        let clientStatus = MIDIClientCreateWithBlock(
            "Kairos USB Sync" as CFString,
            &nextClient
        ) { _ in }

        let portStatus: OSStatus
        if clientStatus == noErr {
            portStatus = MIDIInputPortCreateWithBlock(
                nextClient,
                "Kairos USB Sync Input" as CFString,
                &nextInputPort
            ) { packetList, _ in
                guard let bridge = bridgeReference.bridge else {
                    return
                }

                for packet in packetList.unsafeSequence() {
                    bridge.handle(
                        packetBytes: packet.bytes(),
                        hostTime: UInt64(packet.pointee.timeStamp)
                    )
                }
            }
        } else {
            portStatus = clientStatus
        }

        client = nextClient
        inputPort = nextInputPort
        isBridgeAvailable = clientStatus == noErr && portStatus == noErr
        self.bridgeReference = bridgeReference
        bridgeReference.bridge = self
    }

    deinit {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }

        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    func refreshSources() -> [USBMIDISourceDescriptor] {
        guard isBridgeAvailable else {
            return []
        }

        return withLock {
            refreshAvailableSourcesLocked()
            reconnectSelectedSourceLocked()
            return cachedSources.map(\.descriptor)
        }
    }

    func setSelectedSource(_ preference: USBMIDISourcePreference) {
        guard isBridgeAvailable else {
            return
        }

        withLock {
            selectedSource = preference
            refreshAvailableSourcesLocked()
            reconnectSelectedSourceLocked(forceReset: true)
        }
    }

    func captureSnapshot() -> USBMIDISyncSnapshot {
        let hostTime = UInt64(AudioGetCurrentHostTime())

        return withLock {
            let selectedRecord = cachedSources.first {
                $0.descriptor.uniqueID == selectedSource.uniqueID
            }
            let runtimeSnapshot = tracker.snapshot(at: hostTime)
            let isSelectedSourceAvailable = connectedEndpoint != 0
                && connectedSourceUniqueID == selectedSource.uniqueID

            return USBMIDISyncSnapshot(
                tempoBPM: runtimeSnapshot.tempoBPM,
                beat: runtimeSnapshot.beat,
                isPlaying: runtimeSnapshot.isPlaying,
                isBridgeAvailable: isBridgeAvailable,
                hasSelection: selectedSource.uniqueID != nil,
                isSelectedSourceAvailable: isSelectedSourceAvailable,
                hasReceivedMessages: runtimeSnapshot.hasReceivedMessages,
                selectedSourceName: selectedSource.displayName ?? selectedRecord?.descriptor.displayName
            )
        }
    }

    fileprivate func handle<S: Sequence>(
        packetBytes: S,
        hostTime: UInt64
    ) where S.Element == UInt8 {
        let normalizedHostTime = hostTime == 0
            ? UInt64(AudioGetCurrentHostTime())
            : hostTime

        withLock {
            rawMessageParser.parse(bytes: packetBytes) { systemMessage in
                tracker.process(systemMessage, at: normalizedHostTime)
            }
        }
    }

    private func refreshAvailableSourcesLocked() {
        cachedSources = enumerateHardwareSourcesLocked()
            .sorted { lhs, rhs in
                lhs.descriptor.displayName.localizedCaseInsensitiveCompare(rhs.descriptor.displayName) == .orderedAscending
            }
    }

    private func enumerateHardwareSourcesLocked() -> [USBMIDISourceRecord] {
        let sourceCount = Int(MIDIGetNumberOfSources())
        var results: [USBMIDISourceRecord] = []
        results.reserveCapacity(sourceCount)

        for sourceIndex in 0 ..< sourceCount {
            let endpoint = MIDIGetSource(sourceIndex)
            guard endpoint != 0 else {
                continue
            }

            var entity = MIDIEntityRef()
            guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0 else {
                continue
            }

            var device = MIDIDeviceRef()
            guard MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else {
                continue
            }

            guard !isOffline(endpoint: endpoint, device: device) else {
                continue
            }

            guard let uniqueID = integerProperty(
                endpoint,
                property: kMIDIPropertyUniqueID
            ) else {
                continue
            }

            let displayName = sourceDisplayName(
                endpoint: endpoint,
                entity: entity,
                device: device
            )
            results.append(
                USBMIDISourceRecord(
                    descriptor: USBMIDISourceDescriptor(
                        uniqueID: uniqueID,
                        displayName: displayName
                    ),
                    endpoint: endpoint
                )
            )
        }

        return results
    }

    private func reconnectSelectedSourceLocked(forceReset: Bool = false) {
        let selectedUniqueID = selectedSource.uniqueID
        let selectedRecord = cachedSources.first {
            $0.descriptor.uniqueID == selectedUniqueID
        }

        let targetEndpoint = selectedRecord?.endpoint ?? 0
        let shouldDisconnect = connectedEndpoint != 0 && (
            forceReset
                || targetEndpoint == 0
                || connectedSourceUniqueID != selectedUniqueID
                || connectedEndpoint != targetEndpoint
        )

        if shouldDisconnect {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
            connectedEndpoint = 0
            connectedSourceUniqueID = nil
            tracker.reset()
            rawMessageParser.reset()
        }

        guard let selectedRecord else {
            return
        }

        guard
            connectedSourceUniqueID != selectedRecord.descriptor.uniqueID
                || connectedEndpoint != selectedRecord.endpoint
        else {
            return
        }

        let status = MIDIPortConnectSource(
            inputPort,
            selectedRecord.endpoint,
            nil
        )

        guard status == noErr else {
            return
        }

        connectedEndpoint = selectedRecord.endpoint
        connectedSourceUniqueID = selectedRecord.descriptor.uniqueID
        tracker.reset()
        rawMessageParser.reset()
    }

    private func isOffline(
        endpoint: MIDIEndpointRef,
        device: MIDIDeviceRef
    ) -> Bool {
        if let endpointOffline = integerProperty(
            endpoint,
            property: kMIDIPropertyOffline
        ), endpointOffline != 0 {
            return true
        }

        if let deviceOffline = integerProperty(
            device,
            property: kMIDIPropertyOffline
        ), deviceOffline != 0 {
            return true
        }

        return false
    }

    private func sourceDisplayName(
        endpoint: MIDIEndpointRef,
        entity: MIDIEntityRef,
        device: MIDIDeviceRef
    ) -> String {
        if let endpointDisplayName = stringProperty(
            endpoint,
            property: kMIDIPropertyDisplayName
        ), !endpointDisplayName.isEmpty {
            return endpointDisplayName
        }

        if let endpointName = stringProperty(
            endpoint,
            property: kMIDIPropertyName
        ), !endpointName.isEmpty {
            return endpointName
        }

        if let entityDisplayName = stringProperty(
            entity,
            property: kMIDIPropertyDisplayName
        ), !entityDisplayName.isEmpty {
            return entityDisplayName
        }

        if let deviceDisplayName = stringProperty(
            device,
            property: kMIDIPropertyDisplayName
        ), !deviceDisplayName.isEmpty {
            return deviceDisplayName
        }

        if let deviceName = stringProperty(
            device,
            property: kMIDIPropertyName
        ), !deviceName.isEmpty {
            return deviceName
        }

        return "USB MIDI Device"
    }

    private func integerProperty(
        _ object: MIDIObjectRef,
        property: CFString
    ) -> Int32? {
        var value: Int32 = 0
        guard MIDIObjectGetIntegerProperty(object, property, &value) == noErr else {
            return nil
        }

        return value
    }

    private func stringProperty(
        _ object: MIDIObjectRef,
        property: CFString
    ) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr else {
            return nil
        }

        guard let value else {
            return nil
        }

        return value.takeRetainedValue() as String
    }

    private func withLock<Result>(
        _ body: () -> Result
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
