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

    private func cloudStoreDirectoryURL() -> URL? {
        guard let cloudRootURL = cloudContainerRootURL() else {
            return nil
        }

        let directoryURL = cloudRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TemplateCategories", isDirectory: true)

        do {
            try ensureDirectoryExists(at: directoryURL)
            return directoryURL
        } catch {
            logger.error("Could not access iCloud template category folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cloudContainerRootURL() -> URL? {
        if let cloudRootURL = ubiquityContainerURLProvider(cloudContainerIdentifier) {
            return cloudRootURL
        }

        guard cloudContainerIdentifier != nil else {
            return nil
        }

        if let fallbackCloudRootURL = ubiquityContainerURLProvider(nil) {
            logger.log("Using default iCloud container fallback for template category sync.")
            return fallbackCloudRootURL
        }

        return nil
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
        cloudStoreDirectoryURL()?.appendingPathComponent(filename)
    }

    private func cloudPlaceholderURL(for filename: String) -> URL? {
        cloudStoreDirectoryURL()?.appendingPathComponent("\(filename).icloud")
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
        guard let cloudFileURL = cloudFileURL(for: filename) else {
            return nil
        }

        if fileManager.fileExists(atPath: cloudFileURL.path) {
            return cloudFileURL
        }

        guard let placeholderURL = cloudPlaceholderURL(for: filename),
              fileManager.fileExists(atPath: placeholderURL.path)
        else {
            return nil
        }

        return placeholderURL
    }

    private func syncDataToCloudIfNeeded(_ data: Data, filename: String) {
        guard let cloudFileURL = cloudFileURL(for: filename) else {
            return
        }

        do {
            if fileManager.fileExists(atPath: cloudFileURL.path),
               cloudFileMatches(data, existingFileURL: cloudFileURL)
            {
                return
            }

            if let placeholderURL = cloudPlaceholderURL(for: filename),
               fileManager.fileExists(atPath: placeholderURL.path)
            {
                try fileManager.removeItem(at: placeholderURL)
            }

            if fileManager.fileExists(atPath: cloudFileURL.path) {
                try fileManager.removeItem(at: cloudFileURL)
            }

            try data.write(to: cloudFileURL, options: [.atomic])
        } catch {
            logger.error("Failed to sync template category state to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cloudFileMatches(_ data: Data, existingFileURL: URL) -> Bool {
        do {
            let values = try existingFileURL.resourceValues(forKeys: [.fileSizeKey])
            guard values.fileSize == data.count else {
                return false
            }

            return try Data(contentsOf: existingFileURL) == data
        } catch {
            return false
        }
    }

    private func readData(from sourceURL: URL) throws -> Data {
        let fallbackDownloadedURL = fallbackDownloadedURLIfPlaceholder(for: sourceURL)
        do {
            return try Data(contentsOf: sourceURL)
        } catch {
            if let fallbackDownloadedURL,
               let fallbackData = try? Data(contentsOf: fallbackDownloadedURL)
            {
                return fallbackData
            }

            requestUbiquitousDownloadIfNeeded(at: sourceURL)
            if let fallbackDownloadedURL {
                requestUbiquitousDownloadIfNeeded(at: fallbackDownloadedURL)
            }

            var lastError: Error = error
            for _ in 0..<8 {
                do {
                    return try Data(contentsOf: sourceURL)
                } catch {
                    lastError = error
                }

                if let fallbackDownloadedURL {
                    do {
                        return try Data(contentsOf: fallbackDownloadedURL)
                    } catch {
                        lastError = error
                    }
                }
            }

            throw lastError
        }
    }

    private func fallbackDownloadedURLIfPlaceholder(for sourceURL: URL) -> URL? {
        guard sourceURL.pathExtension.lowercased() == "icloud" else {
            return nil
        }

        return sourceURL.deletingPathExtension()
    }

    private func requestUbiquitousDownloadIfNeeded(at sourceURL: URL) {
        do {
            try fileManager.startDownloadingUbiquitousItem(at: sourceURL)
        } catch {
            // Non-ubiquitous local files throw here; ignore and keep local read behavior.
        }
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
