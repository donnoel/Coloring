import Foundation
import OSLog
import UIKit

protocol GalleryStoreProviding {
    func loadEntries() async throws -> [ArtworkEntry]
    func saveArtwork(imageData: Data, sourceTemplateID: String, sourceTemplateName: String) async throws -> ArtworkEntry
    func deleteEntry(_ id: String) async throws
}

actor GalleryStoreService: GalleryStoreProviding {
    private let logger = Logger(subsystem: "Coloring", category: "GalleryStore")
    private let fileManager: FileManager
    private let cloudContainerIdentifier: String?
    nonisolated private let galleryDirectoryURLProvider: @Sendable () throws -> URL
    nonisolated private let ubiquityContainerURLProvider: @Sendable (String?) -> URL?
    private var cachedEntries: [ArtworkEntry]?

    nonisolated static let galleryDirectoryURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Gallery", isDirectory: true)
    }()

    init(
        galleryDirectoryURLProvider: (@Sendable () throws -> URL)? = nil,
        fileManager: FileManager = .default,
        cloudContainerIdentifier: String? = "iCloud.dn.coloring",
        ubiquityContainerURLProvider: @escaping @Sendable (String?) -> URL? = {
            FileManager.default.url(forUbiquityContainerIdentifier: $0)
        }
    ) {
        self.galleryDirectoryURLProvider = galleryDirectoryURLProvider ?? {
            GalleryStoreService.galleryDirectoryURL
        }
        self.fileManager = fileManager
        self.cloudContainerIdentifier = cloudContainerIdentifier
        self.ubiquityContainerURLProvider = ubiquityContainerURLProvider
    }

    private func galleryDirectoryURL() throws -> URL {
        try galleryDirectoryURLProvider()
    }

    private func manifestURL() throws -> URL {
        try galleryDirectoryURL().appendingPathComponent("manifest.json")
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func ensureLocalDirectoryExists() throws {
        let directoryURL = try galleryDirectoryURL()
        try ensureDirectoryExists(at: directoryURL)
    }

    private func cloudGalleryDirectoryURL() -> URL? {
        guard let cloudRootURL = cloudContainerRootURL() else {
            return nil
        }

        let directoryURL = cloudRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Gallery", isDirectory: true)

        do {
            try ensureDirectoryExists(at: directoryURL)
            return directoryURL
        } catch {
            logger.error("Could not access iCloud gallery folder: \(error.localizedDescription, privacy: .public)")
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
            logger.log("Using default iCloud container fallback for gallery sync.")
            return fallbackCloudRootURL
        }

        return nil
    }

    private func cloudFileURL(for filename: String, in cloudDirectoryURL: URL) -> URL {
        cloudDirectoryURL.appendingPathComponent(filename)
    }

    private func cloudPlaceholderURL(for filename: String, in cloudDirectoryURL: URL) -> URL {
        cloudDirectoryURL.appendingPathComponent("\(filename).icloud")
    }

    private func cloudFileURLIfExists(for filename: String, in cloudDirectoryURL: URL) -> URL? {
        let cloudFileURL = cloudFileURL(for: filename, in: cloudDirectoryURL)
        if fileManager.fileExists(atPath: cloudFileURL.path) {
            return cloudFileURL
        }

        let placeholderURL = cloudPlaceholderURL(for: filename, in: cloudDirectoryURL)
        if fileManager.fileExists(atPath: placeholderURL.path) {
            return placeholderURL
        }

        return nil
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

    private func syncDataToCloudIfNeeded(_ data: Data, filename: String, cloudDirectoryURL: URL) {
        let cloudFileURL = cloudFileURL(for: filename, in: cloudDirectoryURL)
        let placeholderURL = cloudPlaceholderURL(for: filename, in: cloudDirectoryURL)

        do {
            if fileManager.fileExists(atPath: cloudFileURL.path),
               cloudFileMatches(data, existingFileURL: cloudFileURL)
            {
                return
            }

            if fileManager.fileExists(atPath: placeholderURL.path) {
                try fileManager.removeItem(at: placeholderURL)
            }
            if fileManager.fileExists(atPath: cloudFileURL.path) {
                try fileManager.removeItem(at: cloudFileURL)
            }

            try data.write(to: cloudFileURL, options: [.atomic])
        } catch {
            logger.error("Failed to sync gallery file to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncFileBidirectionally(filename: String, localDirectoryURL: URL, cloudDirectoryURL: URL) throws {
        let localFileURL = localDirectoryURL.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: localFileURL.path) {
            let localData = try Data(contentsOf: localFileURL)
            syncDataToCloudIfNeeded(localData, filename: filename, cloudDirectoryURL: cloudDirectoryURL)
            return
        }

        guard let cloudSourceURL = cloudFileURLIfExists(for: filename, in: cloudDirectoryURL) else {
            return
        }

        let cloudData = try readData(from: cloudSourceURL)
        try cloudData.write(to: localFileURL, options: [.atomic])
    }

    private func syncManifestToCloudIfNeeded(_ entries: [ArtworkEntry], cloudDirectoryURL: URL) {
        do {
            let data = try JSONEncoder().encode(entries)
            syncDataToCloudIfNeeded(data, filename: "manifest.json", cloudDirectoryURL: cloudDirectoryURL)
        } catch {
            logger.error("Failed to encode gallery manifest for iCloud sync: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteCloudFileIfNeeded(filename: String, cloudDirectoryURL: URL) {
        let cloudFileURL = cloudFileURL(for: filename, in: cloudDirectoryURL)
        let placeholderURL = cloudPlaceholderURL(for: filename, in: cloudDirectoryURL)

        do {
            if fileManager.fileExists(atPath: cloudFileURL.path) {
                try fileManager.removeItem(at: cloudFileURL)
            }
            if fileManager.fileExists(atPath: placeholderURL.path) {
                try fileManager.removeItem(at: placeholderURL)
            }
        } catch {
            logger.error("Failed to delete gallery cloud file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func synchronizeLocalGalleryWithCloud() {
        guard let cloudDirectoryURL = cloudGalleryDirectoryURL() else {
            return
        }

        do {
            let localDirectoryURL = try galleryDirectoryURL()
            try ensureDirectoryExists(at: localDirectoryURL)

            let localManifestURL = localDirectoryURL.appendingPathComponent("manifest.json")

            if !fileManager.fileExists(atPath: localManifestURL.path),
               let cloudManifestURL = cloudFileURLIfExists(for: "manifest.json", in: cloudDirectoryURL)
            {
                let cloudManifestData = try readData(from: cloudManifestURL)
                try cloudManifestData.write(to: localManifestURL, options: [.atomic])
            }

            guard fileManager.fileExists(atPath: localManifestURL.path) else {
                return
            }

            let localManifestData = try Data(contentsOf: localManifestURL)
            let entries = try JSONDecoder().decode([ArtworkEntry].self, from: localManifestData)

            syncDataToCloudIfNeeded(localManifestData, filename: "manifest.json", cloudDirectoryURL: cloudDirectoryURL)

            for entry in entries {
                try syncFileBidirectionally(
                    filename: entry.fullImageFilename,
                    localDirectoryURL: localDirectoryURL,
                    cloudDirectoryURL: cloudDirectoryURL
                )
                try syncFileBidirectionally(
                    filename: entry.thumbnailFilename,
                    localDirectoryURL: localDirectoryURL,
                    cloudDirectoryURL: cloudDirectoryURL
                )
            }
        } catch {
            logger.error("Gallery sync with iCloud failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadEntries() throws -> [ArtworkEntry] {
        try ensureLocalDirectoryExists()
        synchronizeLocalGalleryWithCloud()

        let manifestURL = try manifestURL()

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            cachedEntries = []
            return []
        }

        let data = try Data(contentsOf: manifestURL)
        let entries = try JSONDecoder().decode([ArtworkEntry].self, from: data)
        cachedEntries = entries
        return entries
    }

    func saveArtwork(
        imageData: Data,
        sourceTemplateID: String,
        sourceTemplateName: String
    ) throws -> ArtworkEntry {
        try ensureLocalDirectoryExists()
        let directoryURL = try galleryDirectoryURL()

        let entryID = UUID().uuidString
        let fullImageFilename = "\(entryID).png"
        let thumbnailFilename = "\(entryID)_thumb.png"
        let normalizedImageData = normalizeArtworkImageData(imageData)

        let fullImageURL = directoryURL.appendingPathComponent(fullImageFilename)
        let thumbnailURL = directoryURL.appendingPathComponent(thumbnailFilename)
        try normalizedImageData.write(to: fullImageURL, options: .atomic)

        var thumbnailDataForCloud: Data?
        if let fullImage = UIImage(data: normalizedImageData) {
            let thumbnailData = generateThumbnail(from: fullImage, maxSize: 300)
            if let thumbnailData {
                do {
                    try thumbnailData.write(to: thumbnailURL, options: .atomic)
                    thumbnailDataForCloud = thumbnailData
                } catch {
                    logger.error("Failed to write gallery thumbnail: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let entry = ArtworkEntry(
            id: entryID,
            sourceTemplateID: sourceTemplateID,
            sourceTemplateName: sourceTemplateName,
            createdAt: Date(),
            fullImageFilename: fullImageFilename,
            thumbnailFilename: thumbnailFilename
        )

        do {
            var entries = try loadEntries()
            entries.insert(entry, at: 0)
            try persistManifest(entries)
            cachedEntries = entries

            if let cloudDirectoryURL = cloudGalleryDirectoryURL() {
                syncDataToCloudIfNeeded(normalizedImageData, filename: fullImageFilename, cloudDirectoryURL: cloudDirectoryURL)
                if let thumbnailDataForCloud {
                    syncDataToCloudIfNeeded(thumbnailDataForCloud, filename: thumbnailFilename, cloudDirectoryURL: cloudDirectoryURL)
                }
                syncManifestToCloudIfNeeded(entries, cloudDirectoryURL: cloudDirectoryURL)
            }

            return entry
        } catch {
            do {
                try fileManager.removeItem(at: fullImageURL)
            } catch {
                logger.error("Failed to roll back full image after manifest error: \(error.localizedDescription, privacy: .public)")
            }
            do {
                try fileManager.removeItem(at: thumbnailURL)
            } catch {
                logger.error("Failed to roll back thumbnail after manifest error: \(error.localizedDescription, privacy: .public)")
            }
            throw error
        }
    }

    func deleteEntry(_ id: String) throws {
        let directoryURL = try galleryDirectoryURL()
        let loadedEntries: [ArtworkEntry]
        do {
            loadedEntries = try loadEntries()
        } catch {
            logger.error("Failed to load gallery manifest for delete: \(error.localizedDescription, privacy: .public)")
            return
        }

        var entries = loadedEntries
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = entries[index]
        entries.remove(at: index)
        cachedEntries = entries
        try persistManifest(entries)

        let fullImageURL = directoryURL.appendingPathComponent(entry.fullImageFilename)
        let thumbnailURL = directoryURL.appendingPathComponent(entry.thumbnailFilename)
        do {
            try fileManager.removeItem(at: fullImageURL)
        } catch {
            logger.error("Failed to delete gallery full image file: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try fileManager.removeItem(at: thumbnailURL)
        } catch {
            logger.error("Failed to delete gallery thumbnail file: \(error.localizedDescription, privacy: .public)")
        }

        if let cloudDirectoryURL = cloudGalleryDirectoryURL() {
            deleteCloudFileIfNeeded(filename: entry.fullImageFilename, cloudDirectoryURL: cloudDirectoryURL)
            deleteCloudFileIfNeeded(filename: entry.thumbnailFilename, cloudDirectoryURL: cloudDirectoryURL)
            syncManifestToCloudIfNeeded(entries, cloudDirectoryURL: cloudDirectoryURL)
        }
    }

    private func persistManifest(_ entries: [ArtworkEntry]) throws {
        let manifestURL = try manifestURL()
        let data = try JSONEncoder().encode(entries)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func generateThumbnail(from image: UIImage, maxSize: CGFloat) -> Data? {
        let aspectRatio = image.size.width / image.size.height
        let thumbnailSize: CGSize
        if aspectRatio > 1 {
            thumbnailSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            thumbnailSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize, format: format)
        let thumbnailImage = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: thumbnailSize))
            image.stableDisplayImage().draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }

        return thumbnailImage.pngData()
    }

    private func normalizeArtworkImageData(_ imageData: Data) -> Data {
        guard let sourceImage = UIImage(data: imageData) else {
            return imageData
        }

        let stableImage = sourceImage.stableDisplayImage()
        guard stableImage.size.width > 0, stableImage.size.height > 0 else {
            return imageData
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = stableImage.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: stableImage.size, format: format)
        let normalizedImage = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: stableImage.size))
            stableImage.draw(in: CGRect(origin: .zero, size: stableImage.size))
        }

        return normalizedImage.pngData() ?? imageData
    }
}
