import CoreAudio
import Foundation

public struct AudioInputDeviceDescriptor: Sendable {
    public var id: AudioDeviceID
    public var name: String
    public var uid: String
    public var inputChannels: Int
    public var nominalSampleRate: Double
}

public struct AudioHardwareError: Error, CustomStringConvertible {
    public var operation: String
    public var status: OSStatus

    public var description: String {
        "\(operation) failed with OSStatus \(status)"
    }
}

public enum AudioDeviceCatalog {
    public static func inputDevices() throws -> [AudioInputDeviceDescriptor] {
        let deviceIDs = try readDeviceIDs()

        return try deviceIDs.compactMap { deviceID in
            let inputChannels = try inputChannelCount(for: deviceID)
            guard inputChannels > 0 else {
                return nil
            }

            return AudioInputDeviceDescriptor(
                id: deviceID,
                name: try readStringProperty(
                    objectID: deviceID,
                    selector: kAudioObjectPropertyName,
                    scope: kAudioObjectPropertyScopeGlobal
                ),
                uid: try readStringProperty(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID,
                    scope: kAudioObjectPropertyScopeGlobal
                ),
                inputChannels: inputChannels,
                nominalSampleRate: try readFloat64Property(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyNominalSampleRate,
                    scope: kAudioObjectPropertyScopeGlobal
                )
            )
        }
    }

    public static func blackHole16chInput() throws -> AudioInputDeviceDescriptor? {
        try inputDevices().first { $0.name == "BlackHole 16ch" }
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr else {
            throw AudioHardwareError(operation: "AudioObjectGetPropertyDataSize(streamConfiguration)", status: sizeStatus)
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            rawBuffer.deallocate()
        }

        let bufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList)
        guard dataStatus == noErr else {
            throw AudioHardwareError(operation: "AudioObjectGetPropertyData(streamConfiguration)", status: dataStatus)
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    private static func readStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.stride)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
        }

        guard status == noErr else {
            throw AudioHardwareError(operation: "AudioObjectGetPropertyData(string)", status: status)
        }

        return (value ?? "" as CFString) as String
    }

    private static func readDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        let sizeStatus = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr else {
            throw AudioHardwareError(operation: "AudioObjectGetPropertyDataSize(array)", status: sizeStatus)
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        var values = Array(repeating: AudioDeviceID(0), count: count)
        let dataStatus = values.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                systemObjectID,
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }
        guard dataStatus == noErr else {
            throw AudioHardwareError(operation: "AudioObjectGetPropertyData(devices)", status: dataStatus)
        }

        return values
    }

    private static func readFloat64Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> Float64 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.stride)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else {
            throw AudioHardwareError(operation: "AudioObjectGetPropertyData(float64)", status: status)
        }

        return value
    }
}
