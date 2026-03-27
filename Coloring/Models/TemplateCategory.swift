import Foundation

struct TemplateCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    let isUserCreated: Bool

    static let allCategory = TemplateCategory(id: "all", name: "All", isUserCreated: false)
    static let inProgressCategory = TemplateCategory(id: "in-progress", name: "In Progress", isUserCreated: false)
    static let favoritesCategory = TemplateCategory(id: "favorites", name: "Favorites", isUserCreated: false)
    static let recentCategory = TemplateCategory(id: "recent", name: "Recent", isUserCreated: false)
    static let completedCategory = TemplateCategory(id: "completed", name: "Completed", isUserCreated: false)
    static let importedCategory = TemplateCategory(id: "imported", name: "Imported", isUserCreated: false)
    private static let shelfDisplayNameByKey: [String: String] = [
        "cozy": "Cozy",
        "nature": "Nature",
        "animals": "Animals",
        "fantasy": "Fantasy",
        "patterns": "Patterns",
        "seasonal": "Seasonal",
        "motorsport": "Motorsport",
        "scifi": "Sci-Fi"
    ]
    private static let complexityDisplayNameByKey: [String: String] = [
        "easy": "Easy",
        "medium": "Medium",
        "detailed": "Detailed",
        "dense": "Dense"
    ]

    static func builtInCategoryNames(for template: ColoringTemplate) -> Set<String> {
        guard template.source == .builtIn else {
            return []
        }

        var names: Set<String> = []

        if let shelfKey = normalizedKey(template.shelfCategory),
           let shelfDisplayName = shelfDisplayNameByKey[shelfKey]
        {
            names.insert(shelfDisplayName)
        } else {
            let fallbackCategory = template.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackCategory.isEmpty {
                names.insert(fallbackCategory)
            }
        }

        if let complexityKey = normalizedKey(template.complexity),
           let complexityDisplayName = complexityDisplayNameByKey[complexityKey]
        {
            names.insert(complexityDisplayName)
        }

        switch template.canvasOrientation {
        case .landscape:
            names.insert("Landscape")
        case .portrait:
            names.insert("Portrait")
        case .any:
            break
        }

        return names
    }

    /// Derive built-in categories from template manifest categories.
    static func builtInCategories(from templates: [ColoringTemplate]) -> [TemplateCategory] {
        let derivedCategoryNames = Set(
            templates.flatMap { template in
                builtInCategoryNames(for: template)
            }
        )

        return derivedCategoryNames.sorted().map { name in
            TemplateCategory(
                id: builtInCategoryID(for: name),
                name: name,
                isUserCreated: false
            )
        }
    }

    static func builtInCategoryID(for name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let resolvedSlug = slug.isEmpty ? "category" : slug
        return "builtin-\(resolvedSlug)"
    }

    private static func normalizedKey(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalized.isEmpty ? nil : normalized
    }
}
