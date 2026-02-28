import Foundation

protocol TemplateCategoryStoreProviding {
    func loadUserCategories() async throws -> [TemplateCategory]
    func saveUserCategories(_ categories: [TemplateCategory]) async throws
    func loadCategoryAssignments() async throws -> [String: String]
    func saveCategoryAssignments(_ assignments: [String: String]) async throws
    func loadCategoryOrder() async throws -> [String]
    func saveCategoryOrder(_ categoryOrder: [String]) async throws
    func loadFavoriteTemplateIDs() async throws -> Set<String>
    func saveFavoriteTemplateIDs(_ templateIDs: Set<String>) async throws
    func loadCompletedTemplateIDs() async throws -> Set<String>
    func saveCompletedTemplateIDs(_ templateIDs: Set<String>) async throws
    func loadRecentTemplateIDs() async throws -> [String]
    func saveRecentTemplateIDs(_ templateIDs: [String]) async throws
}

actor TemplateCategoryStoreService: TemplateCategoryStoreProviding {
    nonisolated private let documentsDirectoryURLProvider: @Sendable () throws -> URL

    init(
        documentsDirectoryURLProvider: @escaping @Sendable () throws -> URL = {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            return documentsURL
        }
    ) {
        self.documentsDirectoryURLProvider = documentsDirectoryURLProvider
    }

    private func storeDirectory() throws -> URL {
        let fileManager = FileManager.default
        let documents = try documentsDirectoryURLProvider()
        let directory = documents.appendingPathComponent("TemplateCategories", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func categoriesFileURL() throws -> URL {
        try storeDirectory().appendingPathComponent("user_categories.json")
    }

    private func assignmentsFileURL() throws -> URL {
        try storeDirectory().appendingPathComponent("category_assignments.json")
    }

    private func categoryOrderFileURL() throws -> URL {
        try storeDirectory().appendingPathComponent("category_order.json")
    }

    private func favoritesFileURL() throws -> URL {
        try storeDirectory().appendingPathComponent("favorite_template_ids.json")
    }

    private func completedFileURL() throws -> URL {
        try storeDirectory().appendingPathComponent("completed_template_ids.json")
    }

    private func recentFileURL() throws -> URL {
        try storeDirectory().appendingPathComponent("recent_template_ids.json")
    }

    func loadUserCategories() throws -> [TemplateCategory] {
        let fileManager = FileManager.default
        let fileURL = try categoriesFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([TemplateCategory].self, from: data)
    }

    func saveUserCategories(_ categories: [TemplateCategory]) throws {
        let fileURL = try categoriesFileURL()
        let data = try JSONEncoder().encode(categories)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadCategoryAssignments() throws -> [String: String] {
        let fileManager = FileManager.default
        let fileURL = try assignmentsFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func saveCategoryAssignments(_ assignments: [String: String]) throws {
        let fileURL = try assignmentsFileURL()
        let data = try JSONEncoder().encode(assignments)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadCategoryOrder() throws -> [String] {
        let fileManager = FileManager.default
        let fileURL = try categoryOrderFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String].self, from: data)
    }

    func saveCategoryOrder(_ categoryOrder: [String]) throws {
        let fileURL = try categoryOrderFileURL()
        let data = try JSONEncoder().encode(categoryOrder)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadFavoriteTemplateIDs() throws -> Set<String> {
        let fileManager = FileManager.default
        let fileURL = try favoritesFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Set<String>.self, from: data)
    }

    func saveFavoriteTemplateIDs(_ templateIDs: Set<String>) throws {
        let fileURL = try favoritesFileURL()
        let data = try JSONEncoder().encode(templateIDs)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadCompletedTemplateIDs() throws -> Set<String> {
        let fileManager = FileManager.default
        let fileURL = try completedFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Set<String>.self, from: data)
    }

    func saveCompletedTemplateIDs(_ templateIDs: Set<String>) throws {
        let fileURL = try completedFileURL()
        let data = try JSONEncoder().encode(templateIDs)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadRecentTemplateIDs() throws -> [String] {
        let fileManager = FileManager.default
        let fileURL = try recentFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String].self, from: data)
    }

    func saveRecentTemplateIDs(_ templateIDs: [String]) throws {
        let fileURL = try recentFileURL()
        let data = try JSONEncoder().encode(templateIDs)
        try data.write(to: fileURL, options: .atomic)
    }
}
