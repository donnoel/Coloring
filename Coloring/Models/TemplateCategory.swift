import Foundation

struct TemplateCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    let isUserCreated: Bool

    static let allCategory = TemplateCategory(id: "all", name: "All", isUserCreated: false)
    static let importedCategory = TemplateCategory(id: "imported", name: "Imported", isUserCreated: false)

    /// Derive built-in categories from template manifest categories.
    static func builtInCategories(from templates: [ColoringTemplate]) -> [TemplateCategory] {
        let builtInCategoryNames = Set(
            templates
                .filter { $0.source == .builtIn }
                .map(\.category)
        )

        return builtInCategoryNames.sorted().map { name in
            TemplateCategory(
                id: "builtin-\(name.lowercased())",
                name: name,
                isUserCreated: false
            )
        }
    }
}
