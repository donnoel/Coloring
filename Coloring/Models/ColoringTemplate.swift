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

    nonisolated init(
        id: String,
        title: String,
        category: String,
        source: Source,
        filePath: String,
        canvasOrientation: CanvasOrientation = .any
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.source = source
        self.filePath = filePath
        self.canvasOrientation = canvasOrientation
    }

    nonisolated var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    nonisolated var isImported: Bool {
        source == .imported
    }
}
