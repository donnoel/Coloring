import Combine
import Foundation
import UIKit

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var entries: [ArtworkEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let galleryStore: any GalleryStoreProviding
    private var thumbnailCache: [String: UIImage] = [:]
    private var fullImageCache: [String: UIImage] = [:]

    init(galleryStore: any GalleryStoreProviding) {
        self.galleryStore = galleryStore
    }

    convenience init() {
        self.init(galleryStore: GalleryStoreService())
    }

    func loadEntries() async {
        isLoading = true
        errorMessage = nil

        do {
            entries = try await galleryStore.loadEntries()
            let thumbnailPaths = Set(entries.map(\.thumbnailPath))
            let fullImagePaths = Set(entries.map(\.fullImagePath))
            thumbnailCache = thumbnailCache.filter { thumbnailPaths.contains($0.key) }
            fullImageCache = fullImageCache.filter { fullImagePaths.contains($0.key) }
        } catch {
            errorMessage = "Could not load gallery."
        }

        isLoading = false
    }

    func deleteEntry(_ id: String) {
        Task {
            do {
                if let deletedEntry = entries.first(where: { $0.id == id }) {
                    thumbnailCache.removeValue(forKey: deletedEntry.thumbnailPath)
                    fullImageCache.removeValue(forKey: deletedEntry.fullImagePath)
                }
                try await galleryStore.deleteEntry(id)
                entries.removeAll { $0.id == id }
            } catch {
                errorMessage = "Could not delete artwork."
            }
        }
    }

    func thumbnailImage(for entry: ArtworkEntry) -> UIImage? {
        if let cachedImage = thumbnailCache[entry.thumbnailPath] {
            return cachedImage
        }

        guard let image = UIImage(contentsOfFile: entry.thumbnailPath) else {
            return nil
        }

        thumbnailCache[entry.thumbnailPath] = image
        return image
    }

    func fullImage(for entry: ArtworkEntry) -> UIImage? {
        if let cachedImage = fullImageCache[entry.fullImagePath] {
            return cachedImage
        }

        guard let image = UIImage(contentsOfFile: entry.fullImagePath) else {
            return nil
        }

        fullImageCache[entry.fullImagePath] = image
        return image
    }
}
