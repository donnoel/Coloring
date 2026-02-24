import Foundation

protocol BrushPresetStoreProviding {
    func loadUserPresets() async throws -> [BrushPreset]
    func saveUserPresets(_ presets: [BrushPreset]) async throws
}

actor BrushPresetStoreService: BrushPresetStoreProviding {
    private let fileManager = FileManager.default
    private var cachedPresets: [BrushPreset]?

    private var presetsFileURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent("BrushPresets", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("user_presets.json")
    }

    func loadUserPresets() throws -> [BrushPreset] {
        if let cached = cachedPresets {
            return cached
        }

        guard fileManager.fileExists(atPath: presetsFileURL.path) else {
            cachedPresets = []
            return []
        }

        let data = try Data(contentsOf: presetsFileURL)
        let presets = try JSONDecoder().decode([BrushPreset].self, from: data)
        cachedPresets = presets
        return presets
    }

    func saveUserPresets(_ presets: [BrushPreset]) throws {
        let data = try JSONEncoder().encode(presets)
        try data.write(to: presetsFileURL, options: .atomic)
        cachedPresets = presets
    }
}
