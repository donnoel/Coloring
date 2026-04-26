import Foundation
import OSLog

struct ICloudDocumentsFileStore {
    private let fileManager: FileManager
    private let logger: Logger
    private let cloudContainerIdentifier: String?
    private let ubiquityContainerURLProvider: @Sendable (String?) -> URL?
    private let fallbackLogMessage: String?

    init(
        fileManager: FileManager,
        logger: Logger,
        cloudContainerIdentifier: String?,
        ubiquityContainerURLProvider: @escaping @Sendable (String?) -> URL?,
        fallbackLogMessage: String? = nil
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.cloudContainerIdentifier = cloudContainerIdentifier
        self.ubiquityContainerURLProvider = ubiquityContainerURLProvider
        self.fallbackLogMessage = fallbackLogMessage
    }

    func directory(named directoryName: String, accessDescription: String) -> URL? {
        guard let cloudRootURL = cloudContainerRootURL() else {
            return nil
        }

        let directoryURL = cloudRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)

        do {
            try ensureDirectoryExists(at: directoryURL)
            return directoryURL
        } catch {
            logger.error("Could not access \(accessDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func existingFileURL(named filename: String, in directoryURL: URL) -> URL? {
        let fileURL = fileURL(named: filename, in: directoryURL)
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let placeholderURL = placeholderURL(named: filename, in: directoryURL)
        if fileManager.fileExists(atPath: placeholderURL.path) {
            return placeholderURL
        }

        return nil
    }

    func readDataResolvingPlaceholder(from sourceURL: URL) throws -> Data {
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

    func mirrorDataIfNeeded(_ data: Data, filename: String, in directoryURL: URL) throws {
        let cloudFileURL = fileURL(named: filename, in: directoryURL)

        if fileManager.fileExists(atPath: cloudFileURL.path),
           fileMatches(data, existingFileURL: cloudFileURL)
        {
            return
        }

        let cloudPlaceholderURL = placeholderURL(named: filename, in: directoryURL)
        if fileManager.fileExists(atPath: cloudPlaceholderURL.path) {
            try fileManager.removeItem(at: cloudPlaceholderURL)
        }

        if fileManager.fileExists(atPath: cloudFileURL.path) {
            try fileManager.removeItem(at: cloudFileURL)
        }

        try data.write(to: cloudFileURL, options: [.atomic])
    }

    func deleteFileIfNeeded(filename: String, in directoryURL: URL) throws {
        let cloudFileURL = fileURL(named: filename, in: directoryURL)
        if fileManager.fileExists(atPath: cloudFileURL.path) {
            try fileManager.removeItem(at: cloudFileURL)
        }

        let cloudPlaceholderURL = placeholderURL(named: filename, in: directoryURL)
        if fileManager.fileExists(atPath: cloudPlaceholderURL.path) {
            try fileManager.removeItem(at: cloudPlaceholderURL)
        }
    }

    func syncFileBidirectionally(filename: String, localDirectoryURL: URL, cloudDirectoryURL: URL) throws {
        let localFileURL = localDirectoryURL.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: localFileURL.path) {
            let localData = try Data(contentsOf: localFileURL)
            try mirrorDataIfNeeded(localData, filename: filename, in: cloudDirectoryURL)
            return
        }

        guard let cloudSourceURL = existingFileURL(named: filename, in: cloudDirectoryURL) else {
            return
        }

        let cloudData = try readDataResolvingPlaceholder(from: cloudSourceURL)
        try cloudData.write(to: localFileURL, options: [.atomic])
    }

    func fileURL(named filename: String, in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(filename)
    }

    func placeholderURL(named filename: String, in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("\(filename).icloud")
    }

    private func cloudContainerRootURL() -> URL? {
        if let cloudRootURL = ubiquityContainerURLProvider(cloudContainerIdentifier) {
            return cloudRootURL
        }

        guard cloudContainerIdentifier != nil else {
            return nil
        }

        if let fallbackCloudRootURL = ubiquityContainerURLProvider(nil) {
            if let fallbackLogMessage {
                logger.log("\(fallbackLogMessage, privacy: .public)")
            }
            return fallbackCloudRootURL
        }

        return nil
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileMatches(_ data: Data, existingFileURL: URL) -> Bool {
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
}
