import Foundation

struct TemplateCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    let isUserCreated: Bool

    static let allCategory = TemplateCategory(id: "all", name: "All", isUserCreated: false)
    static let importedCategory = TemplateCategory(id: "imported", name: "Imported", isUserCreated: false)
    private static let titleBasedBuiltInCategoryTitles: [String: Set<String>] = [
        "Cities & Landmarks": [
            "settlement",
            "neighborhood",
            "brooklyn bridge",
            "manhattan island",
            "the needle",
            "city scape",
            "futuristic lunar base",
            "neon city racing"
        ],
        "Nature & Outdoors": [
            "beach",
            "future nature",
            "glacier park",
            "ocean",
            "manhattan island"
        ],
        "People & Portraits": [
            "home",
            "friends",
            "lovely",
            "gentle help",
            "happy",
            "loving mother",
            "sad girl",
            "ai girl",
            "future alien"
        ],
        "Animals & Wildlife": [
            "cats",
            "dogs",
            "elephant",
            "lurking",
            "future alien"
        ],
        "Action & Motion": [
            "bikes",
            "standoff",
            "4 wheeling",
            "ice skating in space",
            "wheelie",
            "neon city racing"
        ]
    ]

    static func builtInCategoryNames(for template: ColoringTemplate) -> Set<String> {
        guard template.source == .builtIn else {
            return []
        }

        var names: Set<String> = [template.category]
        let normalizedTitle = normalizeTitle(template.title)

        for (categoryName, matchingTitles) in titleBasedBuiltInCategoryTitles
        where matchingTitles.contains(normalizedTitle) {
            names.insert(categoryName)
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

    private static func builtInCategoryID(for name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let resolvedSlug = slug.isEmpty ? "category" : slug
        return "builtin-\(resolvedSlug)"
    }

    private static func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
