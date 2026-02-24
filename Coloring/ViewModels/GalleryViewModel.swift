import Combine
import Foundation
import UIKit

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var entries: [ArtworkEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let galleryStore: any GalleryStoreProviding

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
        } catch {
            errorMessage = "Could not load gallery."
        }

        isLoading = false
    }

    func deleteEntry(_ id: String) {
        Task {
            do {
                try await galleryStore.deleteEntry(id)
                entries.removeAll { $0.id == id }
            } catch {
                errorMessage = "Could not delete artwork."
            }
        }
    }

    func thumbnailImage(for entry: ArtworkEntry) -> UIImage? {
        UIImage(contentsOfFile: entry.thumbnailPath)
    }

    func fullImage(for entry: ArtworkEntry) -> UIImage? {
        UIImage(contentsOfFile: entry.fullImagePath)
    }
}
