import Foundation

struct TemplateCategoryDeletionMutation {
    let userCategories: [TemplateCategory]
    let categoryOrder: [String]
    let categoryAssignments: [String: String]
    let selectedCategoryFilter: String
}

enum TemplateCategoryMutationSupport {
    static func makeUserCategory(name: String, id: String) -> TemplateCategory {
        TemplateCategory(
            id: id,
            name: name,
            isUserCreated: true
        )
    }

    static func appendingCategory(_ category: TemplateCategory, to categories: [TemplateCategory]) -> [TemplateCategory] {
        var updatedCategories = categories
        updatedCategories.append(category)
        return updatedCategories
    }

    static func renamingCategory(
        in categories: [TemplateCategory],
        at index: Int,
        to name: String
    ) -> [TemplateCategory] {
        var updatedCategories = categories
        updatedCategories[index].name = name
        return updatedCategories
    }

    static func deletingCategoryState(
        categoryID: String,
        userCategories: [TemplateCategory],
        categoryOrder: [String],
        categoryAssignments: [String: String],
        selectedCategoryFilter: String
    ) -> TemplateCategoryDeletionMutation {
        var updatedUserCategories = userCategories
        updatedUserCategories.removeAll { $0.id == categoryID }

        var updatedCategoryOrder = categoryOrder
        updatedCategoryOrder.removeAll { $0 == categoryID }

        var updatedCategoryAssignments = categoryAssignments
        for (templateID, assignedCategoryID) in categoryAssignments where assignedCategoryID == categoryID {
            updatedCategoryAssignments.removeValue(forKey: templateID)
        }

        let updatedSelectedCategoryFilter: String
        if selectedCategoryFilter == categoryID {
            updatedSelectedCategoryFilter = TemplateCategory.allCategory.id
        } else {
            updatedSelectedCategoryFilter = selectedCategoryFilter
        }

        return TemplateCategoryDeletionMutation(
            userCategories: updatedUserCategories,
            categoryOrder: updatedCategoryOrder,
            categoryAssignments: updatedCategoryAssignments,
            selectedCategoryFilter: updatedSelectedCategoryFilter
        )
    }

    static func assigningTemplate(
        _ templateID: String,
        to categoryID: String?,
        in categoryAssignments: [String: String]
    ) -> [String: String] {
        var updatedAssignments = categoryAssignments
        if let categoryID {
            updatedAssignments[templateID] = categoryID
        } else {
            updatedAssignments.removeValue(forKey: templateID)
        }
        return updatedAssignments
    }

    static func movedCategoryOrder(
        reorderableCategories: [TemplateCategory],
        source: IndexSet,
        destination: Int
    ) -> [String] {
        var updatedCategories = reorderableCategories
        let sourceIndexes = source.sorted()
        let movedCategories = sourceIndexes.map { updatedCategories[$0] }

        for index in sourceIndexes.sorted(by: >) {
            updatedCategories.remove(at: index)
        }

        let removalsBeforeDestination = sourceIndexes.filter { $0 < destination }.count
        let adjustedDestination = max(0, min(updatedCategories.count, destination - removalsBeforeDestination))
        updatedCategories.insert(contentsOf: movedCategories, at: adjustedDestination)
        return updatedCategories.map(\.id)
    }

    static func toggledMembership(of templateID: String, in templateIDs: Set<String>) -> Set<String> {
        var updatedTemplateIDs = templateIDs
        if updatedTemplateIDs.contains(templateID) {
            updatedTemplateIDs.remove(templateID)
        } else {
            updatedTemplateIDs.insert(templateID)
        }
        return updatedTemplateIDs
    }

    static func insertingTemplateID(_ templateID: String, into templateIDs: Set<String>) -> Set<String> {
        var updatedTemplateIDs = templateIDs
        updatedTemplateIDs.insert(templateID)
        return updatedTemplateIDs
    }

    static func removingTemplateID(_ templateID: String, from templateIDs: Set<String>) -> Set<String> {
        var updatedTemplateIDs = templateIDs
        updatedTemplateIDs.remove(templateID)
        return updatedTemplateIDs
    }

    static func clearingTemplateIDs() -> Set<String> {
        []
    }
}
