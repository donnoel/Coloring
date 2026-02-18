import Foundation

struct ColoringTemplate: Identifiable, Hashable, Sendable {
    enum Source: String, Hashable, Sendable {
        case builtIn
        case imported
    }

    let id: String
    let title: String
    let category: String
    let source: Source
    let filePath: String

    nonisolated var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    nonisolated var isImported: Bool {
        source == .imported
    }
}
