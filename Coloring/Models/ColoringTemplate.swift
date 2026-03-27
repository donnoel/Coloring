import Foundation

struct ColoringTemplate: Identifiable, Hashable, Sendable {
    enum Source: String, Hashable, Sendable {
        case builtIn
        case imported
    }

    enum CanvasOrientation: String, Codable, Hashable, Sendable {
        case any
        case landscape
        case portrait
    }

    let id: String
    let title: String
    let category: String
    let source: Source
    let filePath: String
    let canvasOrientation: CanvasOrientation
    let shelfCategory: String?
    let complexity: String?
    let mood: [String]?
    let session: String?
    let lineWeight: String?
    let featured: Bool?

    nonisolated init(
        id: String,
        title: String,
        category: String,
        source: Source,
        filePath: String,
        canvasOrientation: CanvasOrientation = .any,
        shelfCategory: String? = nil,
        complexity: String? = nil,
        mood: [String]? = nil,
        session: String? = nil,
        lineWeight: String? = nil,
        featured: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.source = source
        self.filePath = filePath
        self.canvasOrientation = canvasOrientation
        self.shelfCategory = shelfCategory
        self.complexity = complexity
        self.mood = mood
        self.session = session
        self.lineWeight = lineWeight
        self.featured = featured
    }

    nonisolated var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    nonisolated var isImported: Bool {
        source == .imported
    }
}
