import Foundation

protocol TemplateCategoryStoreProviding {
    func loadUserCategories() async throws -> [TemplateCategory]
    func saveUserCategories(_ categories: [TemplateCategory]) async throws
    func loadCategoryAssignments() async throws -> [String: String]
    func saveCategoryAssignments(_ assignments: [String: String]) async throws
}

actor TemplateCategoryStoreService: TemplateCategoryStoreProviding {
    private let fileManager = FileManager.default

    private var storeDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent("TemplateCategories", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private var categoriesFileURL: URL {
        storeDirectory.appendingPathComponent("user_categories.json")
    }

    private var assignmentsFileURL: URL {
        storeDirectory.appendingPathComponent("category_assignments.json")
    }

    func loadUserCategories() throws -> [TemplateCategory] {
        guard fileManager.fileExists(atPath: categoriesFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: categoriesFileURL)
        return try JSONDecoder().decode([TemplateCategory].self, from: data)
    }

    func saveUserCategories(_ categories: [TemplateCategory]) throws {
        let data = try JSONEncoder().encode(categories)
        try data.write(to: categoriesFileURL, options: .atomic)
    }

    func loadCategoryAssignments() throws -> [String: String] {
        guard fileManager.fileExists(atPath: assignmentsFileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: assignmentsFileURL)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func saveCategoryAssignments(_ assignments: [String: String]) throws {
        let data = try JSONEncoder().encode(assignments)
        try data.write(to: assignmentsFileURL, options: .atomic)
    }
}
