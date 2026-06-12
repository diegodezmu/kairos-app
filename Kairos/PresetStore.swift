import Foundation

enum PresetStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidPresetCount(actual: Int)
    case duplicatePresetSlot
}

actor PresetStore {
    private static let applicationSupportDirectoryName = "Kairos"
    private static let presetsFileName = "presets.json"

    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) throws {
        self.fileManager = fileManager
        self.directoryURL = try Self.resolveDirectoryURL(
            fileManager: fileManager,
            overrideDirectoryURL: directoryURL
        )
        fileURL = self.directoryURL.appendingPathComponent(Self.presetsFileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func loadPresets() throws -> PresetLibrary {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .factoryDefault
        }

        let data = try Data(contentsOf: fileURL)
        let dto = try decoder.decode(PresetLibraryDTO.self, from: data)
        return try dto.domainModel()
    }

    func savePresets(_ library: PresetLibrary) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let dto = PresetLibraryDTO(library: library)
        let data = try encoder.encode(dto)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func resolveDirectoryURL(
        fileManager: FileManager,
        overrideDirectoryURL: URL?
    ) throws -> URL {
        if let overrideDirectoryURL {
            return overrideDirectoryURL
        }

        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupportURL
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
    }
}
