import Combine
import Foundation
import UIKit

enum GalleryImageLoadState {
    case loading
    case loaded(UIImage)
    case failed
}

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var entries: [ArtworkEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let galleryStore: any GalleryStoreProviding
    private let widgetSnapshotWriter: any ColoringWidgetSnapshotWriting
    private let loadImage: @Sendable (String) async -> UIImage?
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let fullImageCache = NSCache<NSString, UIImage>()
    // Keep displayed images alive even when NSCache evicts an oversized image.
    private var displayedImages: [GalleryImageRequest: UIImage] = [:]
    private var activeArtworkPaths: Set<String> = []
    private var activeArtworkThumbnailPaths: Set<String> = []
    private var visibleThumbnailPaths: Set<String> = []
    private var detailArtworkEntry: ArtworkEntry?
    private var imageLoadTasks: [GalleryImageRequest: Task<Void, Never>] = [:]
    private var failedImageRequests: Set<GalleryImageRequest> = []
    private let maxImageLoadRetries: Int
    private let imageRetryDelayNanoseconds: UInt64

    init(
        galleryStore: any GalleryStoreProviding,
        widgetSnapshotWriter: any ColoringWidgetSnapshotWriting = DisabledColoringWidgetSnapshotWriter(),
        imageLoader: (@Sendable (String) async -> UIImage?)? = nil,
        maxImageLoadRetries: Int = 12,
        imageRetryDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.galleryStore = galleryStore
        self.widgetSnapshotWriter = widgetSnapshotWriter
        if let imageLoader {
            loadImage = imageLoader
        } else {
            let loader = GalleryImageLoader()
            loadImage = { path in await loader.loadImage(atPath: path) }
        }
        self.maxImageLoadRetries = max(0, maxImageLoadRetries)
        self.imageRetryDelayNanoseconds = imageRetryDelayNanoseconds
        thumbnailCache.totalCostLimit = 12 * 1_024 * 1_024
        thumbnailCache.countLimit = 128
        fullImageCache.totalCostLimit = 64 * 1_024 * 1_024
        fullImageCache.countLimit = 12
    }

    convenience init() {
        self.init(
            galleryStore: GalleryStoreService(),
            widgetSnapshotWriter: ColoringWidgetSnapshotWriter.shared
        )
    }

    func loadEntries() async {
        isLoading = true
        errorMessage = nil

        do {
            let loadedEntries = try await galleryStore.loadEntries()
            let loadedEntryIDs = Set(loadedEntries.map(\.id))
            let removedEntries = entries.filter { !loadedEntryIDs.contains($0.id) }
            removedEntries.forEach { removeCachedImages(for: $0) }
            entries = loadedEntries
            let thumbnailPaths = Set(entries.map(\.thumbnailPath))
            let fullImagePaths = Set(entries.map(\.fullImagePath))
            activeArtworkPaths.formIntersection(fullImagePaths)
            activeArtworkThumbnailPaths.formIntersection(thumbnailPaths)
            visibleThumbnailPaths.formIntersection(thumbnailPaths)
            retainDisplayedImages()
            // A foreground/explicit reload gives delayed iCloud files a fresh retry window.
            imageLoadTasks.values.forEach { $0.cancel() }
            imageLoadTasks.removeAll()
            failedImageRequests.removeAll()
            await widgetSnapshotWriter.updateLatestGalleryArtwork(entries.first)
        } catch {
            errorMessage = "Could not load gallery."
        }

        isLoading = false
    }

    func deleteEntry(_ id: String) {
        Task {
            do {
                try await galleryStore.deleteEntry(id)
                if let deletedEntry = entries.first(where: { $0.id == id }) {
                    removeCachedImages(for: deletedEntry)
                }
                entries.removeAll { $0.id == id }
                await widgetSnapshotWriter.updateLatestGalleryArtwork(entries.first)
            } catch {
                errorMessage = "Could not delete artwork."
            }
        }
    }

    func setActiveArtworkEntries(_ entries: [ArtworkEntry]) {
        let nearbyEntries = Array(entries.prefix(3))
        let paths = Set(nearbyEntries.map(\.fullImagePath))
        let thumbnailPaths = Set(nearbyEntries.map(\.thumbnailPath))
        guard paths != activeArtworkPaths || thumbnailPaths != activeArtworkThumbnailPaths else {
            return
        }

        activeArtworkPaths = paths
        activeArtworkThumbnailPaths = thumbnailPaths
        retainDisplayedImages()
        cancelInactiveImageLoads()
        for entry in nearbyEntries {
            _ = fullImage(for: entry)
            _ = thumbnailImage(for: entry)
        }
        objectWillChange.send()
    }

    func setThumbnailVisible(_ entry: ArtworkEntry, isVisible: Bool) {
        if isVisible {
            guard visibleThumbnailPaths.insert(entry.thumbnailPath).inserted else {
                return
            }
            if thumbnailImage(for: entry) != nil {
                objectWillChange.send()
            }
        } else {
            visibleThumbnailPaths.remove(entry.thumbnailPath)
            retainDisplayedImages()
            cancelInactiveImageLoads()
        }
    }

    func thumbnailImage(for entry: ArtworkEntry, loadIfNeeded: Bool = true) -> UIImage? {
        image(for: GalleryImageRequest(path: entry.thumbnailPath, kind: .thumbnail), loadIfNeeded: loadIfNeeded)
    }

    func fullImage(for entry: ArtworkEntry) -> UIImage? {
        image(for: GalleryImageRequest(path: entry.fullImagePath, kind: .fullImage))
    }

    func fullImageLoadState(for entry: ArtworkEntry) -> GalleryImageLoadState {
        // Detail can remain presented while a widget link changes the carousel behind it.
        registerDetailArtwork(entry)
        if let image = fullImage(for: entry) {
            return .loaded(image)
        }

        if failedImageRequests.contains(GalleryImageRequest(path: entry.fullImagePath, kind: .fullImage)) {
            return .failed
        }
        return .loading
    }

    func setDetailArtworkVisible(_ entry: ArtworkEntry, isVisible: Bool) {
        if isVisible {
            registerDetailArtwork(entry)
            _ = fullImage(for: entry)
            _ = thumbnailImage(for: entry)
        } else if detailArtworkEntry?.id == entry.id {
            detailArtworkEntry = nil
            retainDisplayedImages()
            cancelInactiveImageLoads()
        }
    }

    private func registerDetailArtwork(_ entry: ArtworkEntry) {
        guard detailArtworkEntry != entry else { return }
        detailArtworkEntry = entry
        retainDisplayedImages()
        cancelInactiveImageLoads()
    }

    func purgeInactiveImageCaches() {
        // Visible artwork remains pinned; clearing the reusable cache cannot trigger reload churn.
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }

    private func image(for request: GalleryImageRequest, loadIfNeeded: Bool = true) -> UIImage? {
        if let image = displayedImages[request] {
            return image
        }
        if let image = cache(for: request.kind).object(forKey: request.path as NSString) {
            if isDisplayed(request) {
                displayedImages[request] = image
            }
            return image
        }

        if loadIfNeeded, isDisplayed(request) {
            scheduleImageLoadIfNeeded(request)
        }
        return nil
    }

    private func scheduleImageLoadIfNeeded(_ request: GalleryImageRequest) {
        guard imageLoadTasks[request] == nil, !failedImageRequests.contains(request) else {
            return
        }

        imageLoadTasks[request] = Task { [weak self, loadImage, maxImageLoadRetries, imageRetryDelayNanoseconds] in
            for attempt in 0...maxImageLoadRetries {
                guard !Task.isCancelled else {
                    return
                }
                let image = await loadImage(request.path)
                guard !Task.isCancelled else {
                    return
                }
                if let image {
                    self?.finishImageLoad(request, image: image)
                    return
                }
                if attempt < maxImageLoadRetries {
                    do {
                        try await Task.sleep(nanoseconds: imageRetryDelayNanoseconds)
                    } catch {
                        return
                    }
                }
            }
            self?.imageLoadTasks.removeValue(forKey: request)
            self?.failedImageRequests.insert(request)
            self?.objectWillChange.send()
        }
    }

    private func finishImageLoad(_ request: GalleryImageRequest, image: UIImage) {
        imageLoadTasks.removeValue(forKey: request)
        cache(for: request.kind).setObject(image, forKey: request.path as NSString, cost: Self.imageCost(image))
        if isDisplayed(request) {
            displayedImages[request] = image
        }
        objectWillChange.send()
    }

    private func cache(for kind: GalleryImageKind) -> NSCache<NSString, UIImage> {
        switch kind {
        case .thumbnail: thumbnailCache
        case .fullImage: fullImageCache
        }
    }

    private func isDisplayed(_ request: GalleryImageRequest) -> Bool {
        switch request.kind {
        case .thumbnail:
            visibleThumbnailPaths.contains(request.path) || activeArtworkThumbnailPaths.contains(request.path)
                || detailArtworkEntry?.thumbnailPath == request.path
        case .fullImage:
            activeArtworkPaths.contains(request.path) || detailArtworkEntry?.fullImagePath == request.path
        }
    }

    private func retainDisplayedImages() {
        displayedImages = displayedImages.filter { isDisplayed($0.key) }
    }

    private func cancelInactiveImageLoads() {
        for request in imageLoadTasks.keys.filter({ !isDisplayed($0) }) {
            imageLoadTasks.removeValue(forKey: request)?.cancel()
        }
    }

    private func removeCachedImages(for entry: ArtworkEntry) {
        let requests = [
            GalleryImageRequest(path: entry.thumbnailPath, kind: .thumbnail),
            GalleryImageRequest(path: entry.fullImagePath, kind: .fullImage)
        ]
        for request in requests {
            cache(for: request.kind).removeObject(forKey: request.path as NSString)
            displayedImages.removeValue(forKey: request)
            failedImageRequests.remove(request)
            imageLoadTasks.removeValue(forKey: request)?.cancel()
        }
        activeArtworkPaths.remove(entry.fullImagePath)
        activeArtworkThumbnailPaths.remove(entry.thumbnailPath)
        visibleThumbnailPaths.remove(entry.thumbnailPath)
        if detailArtworkEntry?.id == entry.id {
            detailArtworkEntry = nil
        }
    }

    private static func imageCost(_ image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        return Int(image.size.width * image.scale) * Int(image.size.height * image.scale) * 4
    }
}

private actor GalleryImageLoader {
    func loadImage(atPath path: String) -> UIImage? {
        let fileURL = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            return nil
        }
        return UIImage(data: data)?.stableDisplayImage()
    }
}

private enum GalleryImageKind: Hashable {
    case thumbnail
    case fullImage
}

private struct GalleryImageRequest: Hashable {
    let path: String
    let kind: GalleryImageKind
}
