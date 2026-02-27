import Foundation

protocol BrushPresetStoreProviding {
    func loadUserPresets() async throws -> [BrushPreset]
    func saveUserPresets(_ presets: [BrushPreset]) async throws
}

actor BrushPresetStoreService: BrushPresetStoreProviding {
    nonisolated private let documentsDirectoryURLProvider: @Sendable () throws -> URL
    private var cachedPresets: [BrushPreset]?

    init(
        documentsDirectoryURLProvider: @escaping @Sendable () throws -> URL = {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            return documentsURL
        }
    ) {
        self.documentsDirectoryURLProvider = documentsDirectoryURLProvider
    }

    private func presetsFileURL() throws -> URL {
        let fileManager = FileManager.default
        let documents = try documentsDirectoryURLProvider()
        let directory = documents.appendingPathComponent("BrushPresets", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("user_presets.json")
    }

    func loadUserPresets() throws -> [BrushPreset] {
        if let cached = cachedPresets {
            return cached
        }

        let fileManager = FileManager.default
        let fileURL = try presetsFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cachedPresets = []
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let presets = try JSONDecoder().decode([BrushPreset].self, from: data)
        cachedPresets = presets
        return presets
    }

    func saveUserPresets(_ presets: [BrushPreset]) throws {
        let fileURL = try presetsFileURL()
        let data = try JSONEncoder().encode(presets)
        try data.write(to: fileURL, options: .atomic)
        cachedPresets = presets
    }
}
