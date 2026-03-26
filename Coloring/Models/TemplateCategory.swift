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
    private static let titleBasedBuiltInCategoryTitles: [String: Set<String>] = [
        "Cities & Landmarks": [
            "alleyway with steps",
            "arch of constantine",
            "settlement",
            "neighborhood",
            "brooklyn bridge",
            "manhattan island",
            "the needle",
            "city scape",
            "invasion over seattle",
            "london city scape",
            "london cityscape",
            "manhattan skyline",
            "portland downtown",
            "rialto bridge",
            "rushmore",
            "space needle",
            "village by the sea",
            "gothic courtyard",
            "futuristic lunar base",
            "neon city racing"
        ],
        "Nature & Outdoors": [
            "beach",
            "grand canyon",
            "future nature",
            "glacier park",
            "half dome",
            "lack como",
            "lake como",
            "lake and mountain",
            "lake stroll",
            "mountain view",
            "ocean",
            "manhattan island",
            "elephant in savanna",
            "flower garden",
            "melancholy at the pool",
            "mountain hike",
            "off-roading adventure",
            "rainforest",
            "ranch",
            "redwood forest",
            "tent time",
            "the beach",
            "trailing",
            "village by the sea"
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
            "future alien",
            "boys and bikes",
            "boys friend",
            "girl on the bench",
            "melancholy at the pool",
            "stuntman bob",
            "winning"
        ],
        "Animals & Wildlife": [
            "jacks",
            "cat and flag",
            "cats",
            "dogs",
            "elephant",
            "elephant sculpture",
            "lurking",
            "future alien",
            "elephant in savanna",
            "playful kitten"
        ],
        "Action & Motion": [
            "bikes",
            "standoff",
            "4 wheeling",
            "ice skating in space",
            "wheelie",
            "neon city racing",
            "ai and robotics",
            "boys and bikes",
            "invasion over seattle",
            "motorcycle racers",
            "mountain hike",
            "off-roading adventure",
            "rocket launch",
            "showdown",
            "stuntman bob",
            "truck and bike",
            "voyage through space",
            "vroom vroom",
            "winning"
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

    static func builtInCategoryID(for name: String) -> String {
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
