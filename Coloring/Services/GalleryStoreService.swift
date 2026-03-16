import Foundation
import UIKit

protocol GalleryStoreProviding {
    func loadEntries() async throws -> [ArtworkEntry]
    func saveArtwork(imageData: Data, sourceTemplateID: String, sourceTemplateName: String) async throws -> ArtworkEntry
    func deleteEntry(_ id: String) async throws
}

actor GalleryStoreService: GalleryStoreProviding {
    nonisolated private let galleryDirectoryURLProvider: @Sendable () throws -> URL
    private var cachedEntries: [ArtworkEntry]?

    nonisolated static let galleryDirectoryURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Gallery", isDirectory: true)
    }()

    init(
        galleryDirectoryURLProvider: (@Sendable () throws -> URL)? = nil
    ) {
        self.galleryDirectoryURLProvider = galleryDirectoryURLProvider ?? {
            GalleryStoreService.galleryDirectoryURL
        }
    }

    private func galleryDirectoryURL() throws -> URL {
        try galleryDirectoryURLProvider()
    }

    private func manifestURL() throws -> URL {
        try galleryDirectoryURL().appendingPathComponent("manifest.json")
    }

    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        let directoryURL = try galleryDirectoryURL()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func loadEntries() throws -> [ArtworkEntry] {
        let fileManager = FileManager.default
        try ensureDirectoryExists()
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
        try ensureDirectoryExists()
        let directoryURL = try galleryDirectoryURL()

        let entryID = UUID().uuidString
        let fullImageFilename = "\(entryID).png"
        let thumbnailFilename = "\(entryID)_thumb.png"
        let normalizedImageData = normalizeArtworkImageData(imageData)

        // Save full image
        let fullImageURL = directoryURL.appendingPathComponent(fullImageFilename)
        try normalizedImageData.write(to: fullImageURL, options: .atomic)

        // Generate and save thumbnail
        if let fullImage = UIImage(data: normalizedImageData) {
            let thumbnailData = generateThumbnail(from: fullImage, maxSize: 300)
            let thumbnailURL = directoryURL.appendingPathComponent(thumbnailFilename)
            try? thumbnailData?.write(to: thumbnailURL, options: .atomic)
        }

        let entry = ArtworkEntry(
            id: entryID,
            sourceTemplateID: sourceTemplateID,
            sourceTemplateName: sourceTemplateName,
            createdAt: Date(),
            fullImageFilename: fullImageFilename,
            thumbnailFilename: thumbnailFilename
        )

        var entries = (try? loadEntries()) ?? []
        entries.insert(entry, at: 0)
        cachedEntries = entries
        try persistManifest(entries)

        return entry
    }

    func deleteEntry(_ id: String) throws {
        let fileManager = FileManager.default
        let directoryURL = try galleryDirectoryURL()
        var entries = (try? loadEntries()) ?? []
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = entries[index]
        entries.remove(at: index)
        cachedEntries = entries
        try persistManifest(entries)

        // Clean up files
        let fullImageURL = directoryURL.appendingPathComponent(entry.fullImageFilename)
        let thumbnailURL = directoryURL.appendingPathComponent(entry.thumbnailFilename)
        try? fileManager.removeItem(at: fullImageURL)
        try? fileManager.removeItem(at: thumbnailURL)
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
