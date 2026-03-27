import Foundation

struct TemplateCategoryStoredState {
    let userCategories: [TemplateCategory]
    let categoryAssignments: [String: String]
    let categoryOrder: [String]
    let favoriteTemplateIDs: Set<String>
    let completedTemplateIDs: Set<String>
    let recentTemplateIDs: [String]
    let hiddenTemplateIDs: Set<String>
}

final class TemplateCategoryPersistenceCoordinator {
    private let categoryStore: any TemplateCategoryStoreProviding

    init(categoryStore: any TemplateCategoryStoreProviding) {
        self.categoryStore = categoryStore
    }

    func loadState() async throws -> TemplateCategoryStoredState {
        let userCategories = try await categoryStore.loadUserCategories()
        let categoryAssignments = try await categoryStore.loadCategoryAssignments()
        let categoryOrder = try await categoryStore.loadCategoryOrder()
        let favoriteTemplateIDs = try await categoryStore.loadFavoriteTemplateIDs()
        let completedTemplateIDs = try await categoryStore.loadCompletedTemplateIDs()
        let recentTemplateIDs = try await categoryStore.loadRecentTemplateIDs()
        let hiddenTemplateIDs = try await categoryStore.loadHiddenTemplateIDs()

        return TemplateCategoryStoredState(
            userCategories: userCategories,
            categoryAssignments: categoryAssignments,
            categoryOrder: categoryOrder,
            favoriteTemplateIDs: favoriteTemplateIDs,
            completedTemplateIDs: completedTemplateIDs,
            recentTemplateIDs: recentTemplateIDs,
            hiddenTemplateIDs: hiddenTemplateIDs
        )
    }

    func persistUserCategories(_ categories: [TemplateCategory]) {
        Task { [categoryStore, categories] in
            try? await categoryStore.saveUserCategories(categories)
        }
    }

    func persistCategoryAssignments(_ assignments: [String: String]) {
        Task { [categoryStore, assignments] in
            try? await categoryStore.saveCategoryAssignments(assignments)
        }
    }

    func persistCategoryOrder(_ categoryOrder: [String]) {
        Task { [categoryStore, categoryOrder] in
            try? await categoryStore.saveCategoryOrder(categoryOrder)
        }
    }

    func persistFavoriteTemplateIDs(_ templateIDs: Set<String>) {
        Task { [categoryStore, templateIDs] in
            try? await categoryStore.saveFavoriteTemplateIDs(templateIDs)
        }
    }

    func persistCompletedTemplateIDs(_ templateIDs: Set<String>) {
        Task { [categoryStore, templateIDs] in
            try? await categoryStore.saveCompletedTemplateIDs(templateIDs)
        }
    }

    func persistRecentTemplateIDs(_ templateIDs: [String]) {
        Task { [categoryStore, templateIDs] in
            try? await categoryStore.saveRecentTemplateIDs(templateIDs)
        }
    }

    func persistHiddenTemplateIDs(_ templateIDs: Set<String>) {
        Task { [categoryStore, templateIDs] in
            try? await categoryStore.saveHiddenTemplateIDs(templateIDs)
        }
    }
}
