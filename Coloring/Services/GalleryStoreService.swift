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
    private var artworkSyncTask: Task<Void, Never>?

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

    private var cloudStore: ICloudDocumentsFileStore {
        ICloudDocumentsFileStore(
            fileManager: fileManager,
            logger: logger,
            cloudContainerIdentifier: cloudContainerIdentifier,
            ubiquityContainerURLProvider: ubiquityContainerURLProvider,
            fallbackLogMessage: "Using default iCloud container fallback for gallery sync."
        )
    }

    private func cloudGalleryDirectoryURL() -> URL? {
        cloudStore.directory(named: "Gallery", accessDescription: "iCloud gallery folder")
    }

    private func cloudFileURLIfExists(for filename: String, in cloudDirectoryURL: URL) -> URL? {
        cloudStore.existingFileURL(named: filename, in: cloudDirectoryURL)
    }

    private func readData(from sourceURL: URL) throws -> Data {
        try cloudStore.readDataResolvingPlaceholder(from: sourceURL)
    }

    private func syncDataToCloudIfNeeded(_ data: Data, filename: String, cloudDirectoryURL: URL) {
        do {
            try cloudStore.mirrorDataIfNeeded(data, filename: filename, in: cloudDirectoryURL)
        } catch {
            logger.error("Failed to sync gallery file to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncFileBidirectionally(filename: String, localDirectoryURL: URL, cloudDirectoryURL: URL) throws {
        try cloudStore.syncFileBidirectionally(
            filename: filename,
            localDirectoryURL: localDirectoryURL,
            cloudDirectoryURL: cloudDirectoryURL
        )
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
        do {
            try cloudStore.deleteFileIfNeeded(filename: filename, in: cloudDirectoryURL)
        } catch {
            logger.error("Failed to delete gallery cloud file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func synchronizeLocalManifestWithCloud() {
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
            syncDataToCloudIfNeeded(localManifestData, filename: "manifest.json", cloudDirectoryURL: cloudDirectoryURL)
        } catch {
            logger.error("Gallery sync with iCloud failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleArtworkSync(entries: [ArtworkEntry]) {
        artworkSyncTask?.cancel()

        guard !entries.isEmpty else {
            return
        }

        artworkSyncTask = Task { [entries] in
            await self.syncArtworkFilesFromCloudIfNeeded(entries: entries)
        }
    }

    private func syncArtworkFilesFromCloudIfNeeded(entries: [ArtworkEntry]) async {
        guard let cloudDirectoryURL = cloudGalleryDirectoryURL() else {
            return
        }

        do {
            let localDirectoryURL = try galleryDirectoryURL()
            try ensureDirectoryExists(at: localDirectoryURL)

            for entry in entries {
                if Task.isCancelled {
                    return
                }

                do {
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
                } catch {
                    logger.error("Failed to sync gallery artwork file: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.error("Gallery artwork sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadEntries() throws -> [ArtworkEntry] {
        try ensureLocalDirectoryExists()
        synchronizeLocalManifestWithCloud()

        let manifestURL = try manifestURL()

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            cachedEntries = []
            return []
        }

        let data = try Data(contentsOf: manifestURL)
        let entries = try JSONDecoder().decode([ArtworkEntry].self, from: data)
        cachedEntries = entries
        scheduleArtworkSync(entries: entries)
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
