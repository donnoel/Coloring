import Foundation
import OSLog

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
    private let logger = Logger(subsystem: "Coloring", category: "TemplateCategoryPersistence")
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
        let persistenceLogger = logger
        Task { [categoryStore, categories, persistenceLogger] in
            do {
                try await categoryStore.saveUserCategories(categories)
            } catch {
                persistenceLogger.error("Failed to persist user categories: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func persistCategoryAssignments(_ assignments: [String: String]) {
        let persistenceLogger = logger
        Task { [categoryStore, assignments, persistenceLogger] in
            do {
                try await categoryStore.saveCategoryAssignments(assignments)
            } catch {
                persistenceLogger.error("Failed to persist category assignments: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func persistCategoryOrder(_ categoryOrder: [String]) {
        let persistenceLogger = logger
        Task { [categoryStore, categoryOrder, persistenceLogger] in
            do {
                try await categoryStore.saveCategoryOrder(categoryOrder)
            } catch {
                persistenceLogger.error("Failed to persist category order: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func persistFavoriteTemplateIDs(_ templateIDs: Set<String>) {
        let persistenceLogger = logger
        Task { [categoryStore, templateIDs, persistenceLogger] in
            do {
                try await categoryStore.saveFavoriteTemplateIDs(templateIDs)
            } catch {
                persistenceLogger.error("Failed to persist favorites: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func persistCompletedTemplateIDs(_ templateIDs: Set<String>) {
        let persistenceLogger = logger
        Task { [categoryStore, templateIDs, persistenceLogger] in
            do {
                try await categoryStore.saveCompletedTemplateIDs(templateIDs)
            } catch {
                persistenceLogger.error("Failed to persist completed IDs: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func persistRecentTemplateIDs(_ templateIDs: [String]) {
        let persistenceLogger = logger
        Task { [categoryStore, templateIDs, persistenceLogger] in
            do {
                try await categoryStore.saveRecentTemplateIDs(templateIDs)
            } catch {
                persistenceLogger.error("Failed to persist recents: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func persistHiddenTemplateIDs(_ templateIDs: Set<String>) {
        let persistenceLogger = logger
        Task { [categoryStore, templateIDs, persistenceLogger] in
            do {
                try await categoryStore.saveHiddenTemplateIDs(templateIDs)
            } catch {
                persistenceLogger.error("Failed to persist hidden IDs: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
