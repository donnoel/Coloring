import Foundation
import UIKit

protocol GalleryStoreProviding {
    func loadEntries() async throws -> [ArtworkEntry]
    func saveArtwork(imageData: Data, sourceTemplateID: String, sourceTemplateName: String) async throws -> ArtworkEntry
    func deleteEntry(_ id: String) async throws
}

actor GalleryStoreService: GalleryStoreProviding {
    private let fileManager = FileManager.default
    private var cachedEntries: [ArtworkEntry]?

    nonisolated static let galleryDirectoryURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Gallery", isDirectory: true)
    }()

    private var manifestURL: URL {
        Self.galleryDirectoryURL.appendingPathComponent("manifest.json")
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: Self.galleryDirectoryURL.path) {
            try? fileManager.createDirectory(at: Self.galleryDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func loadEntries() throws -> [ArtworkEntry] {
        ensureDirectoryExists()

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
        ensureDirectoryExists()

        let entryID = UUID().uuidString
        let fullImageFilename = "\(entryID).png"
        let thumbnailFilename = "\(entryID)_thumb.png"

        // Save full image
        let fullImageURL = Self.galleryDirectoryURL.appendingPathComponent(fullImageFilename)
        try imageData.write(to: fullImageURL, options: .atomic)

        // Generate and save thumbnail
        if let fullImage = UIImage(data: imageData) {
            let thumbnailData = generateThumbnail(from: fullImage, maxSize: 300)
            let thumbnailURL = Self.galleryDirectoryURL.appendingPathComponent(thumbnailFilename)
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
        var entries = (try? loadEntries()) ?? []
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = entries[index]
        entries.remove(at: index)
        cachedEntries = entries
        try persistManifest(entries)

        // Clean up files
        let fullImageURL = Self.galleryDirectoryURL.appendingPathComponent(entry.fullImageFilename)
        let thumbnailURL = Self.galleryDirectoryURL.appendingPathComponent(entry.thumbnailFilename)
        try? fileManager.removeItem(at: fullImageURL)
        try? fileManager.removeItem(at: thumbnailURL)
    }

    private func persistManifest(_ entries: [ArtworkEntry]) throws {
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

        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let thumbnailImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }

        return thumbnailImage.pngData()
    }
}
