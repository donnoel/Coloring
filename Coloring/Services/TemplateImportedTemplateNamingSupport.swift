import Foundation

enum TemplateImportedTemplateNamingSupport {
    static func sanitizedFilename(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let filteredScalars = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let normalized = String(filteredScalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")

        return normalized.isEmpty ? "imported-drawing" : normalized
    }

    static func uuidSuffix(from fileStem: String) -> String? {
        let pattern = "-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        guard let range = fileStem.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(fileStem[range])
    }

    static func humanReadableTitle(from filename: String) -> String {
        var stem = filename.replacingOccurrences(of: ".png", with: "")
        if let uuidRange = stem.range(
            of: "-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            options: .regularExpression
        ) {
            stem.removeSubrange(uuidRange)
        }

        let normalized = stem.replacingOccurrences(of: "-", with: " ")
        return normalized.capitalized
    }
}
