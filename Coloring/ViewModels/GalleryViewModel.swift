import Combine
import Foundation
import UIKit

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var entries: [ArtworkEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let galleryStore: any GalleryStoreProviding
    private let imageLoader = GalleryImageLoader()
    private var thumbnailCache: [String: UIImage] = [:]
    private var fullImageCache: [String: UIImage] = [:]
    private var loadingThumbnailPaths: Set<String> = []
    private var loadingFullImagePaths: Set<String> = []
    private var thumbnailRetryCounts: [String: Int] = [:]
    private var fullImageRetryCounts: [String: Int] = [:]
    private let maxImageLoadRetries = 12
    private let imageRetryDelayNanoseconds: UInt64 = 500_000_000

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
            thumbnailRetryCounts = thumbnailRetryCounts.filter { thumbnailPaths.contains($0.key) }
            fullImageRetryCounts = fullImageRetryCounts.filter { fullImagePaths.contains($0.key) }
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

        scheduleThumbnailLoadIfNeeded(atPath: entry.thumbnailPath)
        return nil
    }

    func fullImage(for entry: ArtworkEntry) -> UIImage? {
        if let cachedImage = fullImageCache[entry.fullImagePath] {
            return cachedImage
        }

        scheduleFullImageLoadIfNeeded(atPath: entry.fullImagePath)
        return nil
    }

    private func scheduleThumbnailLoadIfNeeded(atPath path: String) {
        guard !loadingThumbnailPaths.contains(path) else {
            return
        }

        loadingThumbnailPaths.insert(path)
        Task {
            let image = await imageLoader.loadImage(atPath: path)
            loadingThumbnailPaths.remove(path)

            guard let image else {
                scheduleRetryIfNeeded(forPath: path, imageKind: .thumbnail)
                return
            }

            thumbnailCache[path] = image
            thumbnailRetryCounts.removeValue(forKey: path)
            objectWillChange.send()
        }
    }

    private func scheduleFullImageLoadIfNeeded(atPath path: String) {
        guard !loadingFullImagePaths.contains(path) else {
            return
        }

        loadingFullImagePaths.insert(path)
        Task {
            let image = await imageLoader.loadImage(atPath: path)
            loadingFullImagePaths.remove(path)

            guard let image else {
                scheduleRetryIfNeeded(forPath: path, imageKind: .fullImage)
                return
            }

            fullImageCache[path] = image
            fullImageRetryCounts.removeValue(forKey: path)
            objectWillChange.send()
        }
    }

    private func scheduleRetryIfNeeded(forPath path: String, imageKind: GalleryImageKind) {
        switch imageKind {
        case .thumbnail:
            let currentRetryCount = thumbnailRetryCounts[path, default: 0]
            guard currentRetryCount < maxImageLoadRetries else {
                return
            }

            thumbnailRetryCounts[path] = currentRetryCount + 1
        case .fullImage:
            let currentRetryCount = fullImageRetryCounts[path, default: 0]
            guard currentRetryCount < maxImageLoadRetries else {
                return
            }

            fullImageRetryCounts[path] = currentRetryCount + 1
        }

        Task {
            try? await Task.sleep(nanoseconds: imageRetryDelayNanoseconds)
            objectWillChange.send()
        }
    }
}

private actor GalleryImageLoader {
    func loadImage(atPath path: String) -> UIImage? {
        let fileURL = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            return nil
        }
        return UIImage(data: data)
    }
}

private enum GalleryImageKind {
    case thumbnail
    case fullImage
}
