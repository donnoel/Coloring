import Foundation

struct TemplateCategoryComputedState {
    let categoryOrder: [String]
    let reorderableCategories: [TemplateCategory]
    let allCategories: [TemplateCategory]
}

enum TemplateCategoryViewStateBuilder {
    static func filteredTemplates(
        templates: [ColoringTemplate],
        selectedCategoryFilter: String,
        visibleInProgressTemplateIDs: Set<String>,
        favoriteTemplateIDs: Set<String>,
        recentTemplateIDs: [String],
        completedTemplateIDs: Set<String>,
        categoryAssignments: [String: String],
        builtInCategories: [TemplateCategory],
        builtInCategoryNamesByTemplateID: [String: Set<String>]
    ) -> [ColoringTemplate] {
        let filterID = selectedCategoryFilter
        guard filterID != TemplateCategory.allCategory.id else {
            return templates
        }

        if filterID == TemplateCategory.inProgressCategory.id {
            return templates.filter { visibleInProgressTemplateIDs.contains($0.id) }
        }

        if filterID == TemplateCategory.favoritesCategory.id {
            return templates.filter { favoriteTemplateIDs.contains($0.id) }
        }

        if filterID == TemplateCategory.recentCategory.id {
            let templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            return recentTemplateIDs.compactMap { templatesByID[$0] }
        }

        if filterID == TemplateCategory.completedCategory.id {
            return templates.filter { completedTemplateIDs.contains($0.id) }
        }

        if filterID == TemplateCategory.importedCategory.id {
            return templates.filter { $0.source == .imported && categoryAssignments[$0.id] == nil }
        }

        let assignedToCategory = templates.filter { categoryAssignments[$0.id] == filterID }
        if !assignedToCategory.isEmpty {
            return assignedToCategory
        }

        if let builtInCategory = builtInCategories.first(where: { $0.id == filterID }) {
            return templates.filter { template in
                builtInCategoryNamesByTemplateID[template.id]?.contains(builtInCategory.name) ?? false
            }
        }

        return templates
    }

    static func computeState(
        categoryOrder: [String],
        builtInCategories: [TemplateCategory],
        userCategories: [TemplateCategory]
    ) -> TemplateCategoryComputedState {
        let availableCategories = builtInCategories + userCategories
        let availableCategoryIDs = Set(availableCategories.map(\.id))
        var normalizedCategoryOrder = categoryOrder.filter { availableCategoryIDs.contains($0) }
        for category in availableCategories where !normalizedCategoryOrder.contains(category.id) {
            normalizedCategoryOrder.append(category.id)
        }

        guard !availableCategories.isEmpty else {
            return TemplateCategoryComputedState(
                categoryOrder: normalizedCategoryOrder,
                reorderableCategories: [],
                allCategories: [
                    TemplateCategory.allCategory,
                    TemplateCategory.inProgressCategory,
                    TemplateCategory.favoritesCategory,
                    TemplateCategory.recentCategory,
                    TemplateCategory.completedCategory,
                    TemplateCategory.importedCategory
                ]
            )
        }

        let categoriesByID = Dictionary(uniqueKeysWithValues: availableCategories.map { ($0.id, $0) })
        var ordered: [TemplateCategory] = []
        var seenCategoryIDs = Set<String>()

        for categoryID in normalizedCategoryOrder {
            guard let category = categoriesByID[categoryID] else {
                continue
            }

            ordered.append(category)
            seenCategoryIDs.insert(categoryID)
        }

        for category in availableCategories where !seenCategoryIDs.contains(category.id) {
            ordered.append(category)
        }

        return TemplateCategoryComputedState(
            categoryOrder: normalizedCategoryOrder,
            reorderableCategories: ordered,
            allCategories: [
                TemplateCategory.allCategory,
                TemplateCategory.inProgressCategory,
                TemplateCategory.favoritesCategory,
                TemplateCategory.recentCategory,
                TemplateCategory.completedCategory
            ] + ordered + [TemplateCategory.importedCategory]
        )
    }
}
