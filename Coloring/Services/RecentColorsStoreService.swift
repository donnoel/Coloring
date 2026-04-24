import Foundation

protocol RecentColorsStoreProviding: Actor {
    func loadRecentColorsByTemplateID() throws -> [String: [RecentColorToken]]
    func saveRecentColorsByTemplateID(_ colorsByTemplateID: [String: [RecentColorToken]]) throws
}

actor RecentColorsStoreService: RecentColorsStoreProviding {
    static let maxColorCount = 10

    private let fileManager: FileManager
    private let documentsDirectoryURLProvider: @Sendable () throws -> URL
    private var cachedColorsByTemplateID: [String: [RecentColorToken]]?

    init(
        fileManager: FileManager = .default,
        documentsDirectoryURLProvider: @escaping @Sendable () throws -> URL = {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            return documentsURL
        }
    ) {
        self.fileManager = fileManager
        self.documentsDirectoryURLProvider = documentsDirectoryURLProvider
    }

    func loadRecentColorsByTemplateID() throws -> [String: [RecentColorToken]] {
        if let cachedColorsByTemplateID {
            return cachedColorsByTemplateID
        }

        let fileURL = try recentColorsFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cachedColorsByTemplateID = [:]
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let colorsByTemplateID = try JSONDecoder().decode([String: [RecentColorToken]].self, from: data)
        let sanitizedColorsByTemplateID = Self.sanitized(colorsByTemplateID)
        cachedColorsByTemplateID = sanitizedColorsByTemplateID
        return sanitizedColorsByTemplateID
    }

    func saveRecentColorsByTemplateID(_ colorsByTemplateID: [String: [RecentColorToken]]) throws {
        let sanitizedColorsByTemplateID = Self.sanitized(colorsByTemplateID)
        let data = try JSONEncoder().encode(sanitizedColorsByTemplateID)
        try data.write(to: try recentColorsFileURL(), options: .atomic)
        cachedColorsByTemplateID = sanitizedColorsByTemplateID
    }

    nonisolated static func inserting(
        _ color: RecentColorToken,
        into colors: [RecentColorToken],
        maxCount: Int = maxColorCount
    ) -> [RecentColorToken] {
        let movedToFront = [color] + colors.filter { $0 != color }
        return Array(movedToFront.prefix(max(0, maxCount)))
    }

    nonisolated private static func sanitized(_ colors: [RecentColorToken]) -> [RecentColorToken] {
        colors.reduce(into: [RecentColorToken]()) { result, color in
            guard !result.contains(color), result.count < maxColorCount else {
                return
            }
            result.append(color)
        }
    }

    nonisolated private static func sanitized(
        _ colorsByTemplateID: [String: [RecentColorToken]]
    ) -> [String: [RecentColorToken]] {
        colorsByTemplateID.reduce(into: [String: [RecentColorToken]]()) { result, entry in
            let templateID = entry.key
            let colors = sanitized(entry.value)
            guard !templateID.isEmpty, !colors.isEmpty else {
                return
            }
            result[templateID] = colors
        }
    }

    private func recentColorsFileURL() throws -> URL {
        let documents = try documentsDirectoryURLProvider()
        let directory = documents.appendingPathComponent("RecentColors", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("recent_colors.json")
    }
}
