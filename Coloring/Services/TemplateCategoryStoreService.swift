import Foundation
import OSLog

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
    func loadHiddenTemplateIDs() async throws -> Set<String>
    func saveHiddenTemplateIDs(_ templateIDs: Set<String>) async throws
}

actor TemplateCategoryStoreService: TemplateCategoryStoreProviding {
    private enum Filename {
        static let userCategories = "user_categories.json"
        static let categoryAssignments = "category_assignments.json"
        static let categoryOrder = "category_order.json"
        static let favoriteTemplateIDs = "favorite_template_ids.json"
        static let completedTemplateIDs = "completed_template_ids.json"
        static let recentTemplateIDs = "recent_template_ids.json"
        static let hiddenTemplateIDs = "hidden_template_ids.json"
    }

    private let fileManager: FileManager
    private let logger: Logger
    private let cloudContainerIdentifier: String?
    nonisolated private let documentsDirectoryURLProvider: @Sendable () throws -> URL
    nonisolated private let ubiquityContainerURLProvider: @Sendable (String?) -> URL?

    init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(subsystem: "Coloring", category: "TemplateCategoryStore"),
        cloudContainerIdentifier: String? = "iCloud.dn.coloring",
        documentsDirectoryURLProvider: @escaping @Sendable () throws -> URL = {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            return documentsURL
        },
        ubiquityContainerURLProvider: @escaping @Sendable (String?) -> URL? = {
            FileManager.default.url(forUbiquityContainerIdentifier: $0)
        }
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.cloudContainerIdentifier = cloudContainerIdentifier
        self.documentsDirectoryURLProvider = documentsDirectoryURLProvider
        self.ubiquityContainerURLProvider = ubiquityContainerURLProvider
    }

    private func storeDirectory() throws -> URL {
        let documents = try documentsDirectoryURLProvider()
        let directory = documents.appendingPathComponent("TemplateCategories", isDirectory: true)
        try ensureDirectoryExists(at: directory)
        return directory
    }

    private var cloudStore: ICloudDocumentsFileStore {
        ICloudDocumentsFileStore(
            fileManager: fileManager,
            logger: logger,
            cloudContainerIdentifier: cloudContainerIdentifier,
            ubiquityContainerURLProvider: ubiquityContainerURLProvider,
            fallbackLogMessage: "Using default iCloud container fallback for template category sync."
        )
    }

    private func cloudStoreDirectoryURL() -> URL? {
        cloudStore.directory(named: "TemplateCategories", accessDescription: "iCloud template category folder")
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func localFileURL(for filename: String) throws -> URL {
        try storeDirectory().appendingPathComponent(filename)
    }

    private func cloudFileURL(for filename: String) -> URL? {
        cloudStoreDirectoryURL().map { cloudStore.fileURL(named: filename, in: $0) }
    }

    private func loadData(for filename: String) throws -> Data? {
        let localURL = try localFileURL(for: filename)
        if fileManager.fileExists(atPath: localURL.path) {
            let localData = try Data(contentsOf: localURL)
            syncDataToCloudIfNeeded(localData, filename: filename)
            return localData
        }

        guard let cloudURL = cloudFileURLIfExists(for: filename) else {
            return nil
        }

        let cloudData = try readData(from: cloudURL)
        try cloudData.write(to: localURL, options: [.atomic])
        return cloudData
    }

    private func saveData(_ data: Data, for filename: String) throws {
        let localURL = try localFileURL(for: filename)
        try data.write(to: localURL, options: [.atomic])
        syncDataToCloudIfNeeded(data, filename: filename)
    }

    private func cloudFileURLIfExists(for filename: String) -> URL? {
        guard let cloudDirectoryURL = cloudStoreDirectoryURL() else {
            return nil
        }

        return cloudStore.existingFileURL(named: filename, in: cloudDirectoryURL)
    }

    private func syncDataToCloudIfNeeded(_ data: Data, filename: String) {
        guard let cloudFileURL = cloudFileURL(for: filename) else {
            return
        }

        do {
            try cloudStore.mirrorDataIfNeeded(data, filename: filename, in: cloudFileURL.deletingLastPathComponent())
        } catch {
            logger.error("Failed to sync template category state to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readData(from sourceURL: URL) throws -> Data {
        try cloudStore.readDataResolvingPlaceholder(from: sourceURL)
    }

    private func loadDecoded<T: Decodable>(
        _ type: T.Type,
        from filename: String,
        default defaultValue: @autoclosure () -> T
    ) throws -> T {
        guard let data = try loadData(for: filename) else {
            return defaultValue()
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func saveEncoded<T: Encodable>(_ value: T, to filename: String) throws {
        let data = try JSONEncoder().encode(value)
        try saveData(data, for: filename)
    }

    func loadUserCategories() throws -> [TemplateCategory] {
        try loadDecoded([TemplateCategory].self, from: Filename.userCategories, default: [TemplateCategory]())
    }

    func saveUserCategories(_ categories: [TemplateCategory]) throws {
        try saveEncoded(categories, to: Filename.userCategories)
    }

    func loadCategoryAssignments() throws -> [String: String] {
        try loadDecoded([String: String].self, from: Filename.categoryAssignments, default: [String: String]())
    }

    func saveCategoryAssignments(_ assignments: [String: String]) throws {
        try saveEncoded(assignments, to: Filename.categoryAssignments)
    }

    func loadCategoryOrder() throws -> [String] {
        try loadDecoded([String].self, from: Filename.categoryOrder, default: [String]())
    }

    func saveCategoryOrder(_ categoryOrder: [String]) throws {
        try saveEncoded(categoryOrder, to: Filename.categoryOrder)
    }

    func loadFavoriteTemplateIDs() throws -> Set<String> {
        try loadDecoded(Set<String>.self, from: Filename.favoriteTemplateIDs, default: Set<String>())
    }

    func saveFavoriteTemplateIDs(_ templateIDs: Set<String>) throws {
        try saveEncoded(templateIDs, to: Filename.favoriteTemplateIDs)
    }

    func loadCompletedTemplateIDs() throws -> Set<String> {
        try loadDecoded(Set<String>.self, from: Filename.completedTemplateIDs, default: Set<String>())
    }

    func saveCompletedTemplateIDs(_ templateIDs: Set<String>) throws {
        try saveEncoded(templateIDs, to: Filename.completedTemplateIDs)
    }

    func loadRecentTemplateIDs() throws -> [String] {
        try loadDecoded([String].self, from: Filename.recentTemplateIDs, default: [String]())
    }

    func saveRecentTemplateIDs(_ templateIDs: [String]) throws {
        try saveEncoded(templateIDs, to: Filename.recentTemplateIDs)
    }

    func loadHiddenTemplateIDs() throws -> Set<String> {
        try loadDecoded(Set<String>.self, from: Filename.hiddenTemplateIDs, default: Set<String>())
    }

    func saveHiddenTemplateIDs(_ templateIDs: Set<String>) throws {
        try saveEncoded(templateIDs, to: Filename.hiddenTemplateIDs)
    }
}
