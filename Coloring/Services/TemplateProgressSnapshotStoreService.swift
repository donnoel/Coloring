import Foundation
import OSLog

protocol TemplateProgressSnapshotStoreProviding: Actor {
    func loadSnapshots() throws -> [String: TemplateProgressSnapshot]
    func saveSnapshots(_ snapshots: [String: TemplateProgressSnapshot]) throws
}

actor TemplateProgressSnapshotStoreService: TemplateProgressSnapshotStoreProviding {
    private let filename = "template_progress_snapshots.json"
    private let fileManager: FileManager
    private let logger: Logger
    private let cloudContainerIdentifier: String?
    private let documentsDirectoryURLProvider: @Sendable () throws -> URL
    private let ubiquityContainerURLProvider: @Sendable (String?) -> URL?

    init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(subsystem: "Coloring", category: "TemplateProgressSnapshotStore"),
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

    func loadSnapshots() throws -> [String: TemplateProgressSnapshot] {
        guard let data = try loadData() else {
            return [:]
        }

        return try JSONDecoder().decode([String: TemplateProgressSnapshot].self, from: data)
    }

    func saveSnapshots(_ snapshots: [String: TemplateProgressSnapshot]) throws {
        let data = try JSONEncoder().encode(snapshots)
        try saveData(data)
    }

    private func storeDirectory() throws -> URL {
        let documents = try documentsDirectoryURLProvider()
        let directory = documents.appendingPathComponent("TemplateProgress", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func localFileURL() throws -> URL {
        try storeDirectory().appendingPathComponent(filename)
    }

    private func cloudFileURL() -> URL? {
        guard let cloudRootURL = cloudContainerRootURL() else {
            return nil
        }

        let directory = cloudRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TemplateProgress", isDirectory: true)

        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory.appendingPathComponent(filename)
        } catch {
            logger.error("Could not access iCloud progress folder: \(error.localizedDescription, privacy: .public)")
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

        return ubiquityContainerURLProvider(nil)
    }

    private func loadData() throws -> Data? {
        let localURL = try localFileURL()
        if fileManager.fileExists(atPath: localURL.path) {
            let localData = try Data(contentsOf: localURL)
            syncDataToCloudIfNeeded(localData)
            return localData
        }

        guard let cloudURL = cloudFileURL(),
              fileManager.fileExists(atPath: cloudURL.path)
        else {
            return nil
        }

        let cloudData = try Data(contentsOf: cloudURL)
        try cloudData.write(to: localURL, options: [.atomic])
        return cloudData
    }

    private func saveData(_ data: Data) throws {
        let localURL = try localFileURL()
        try data.write(to: localURL, options: [.atomic])
        syncDataToCloudIfNeeded(data)
    }

    private func syncDataToCloudIfNeeded(_ data: Data) {
        guard let cloudURL = cloudFileURL() else {
            return
        }

        do {
            if fileManager.fileExists(atPath: cloudURL.path),
               (try? Data(contentsOf: cloudURL)) == data
            {
                return
            }
            try data.write(to: cloudURL, options: [.atomic])
        } catch {
            logger.error("Failed to sync progress snapshots to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }
}
