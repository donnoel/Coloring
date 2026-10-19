import Combine
import Foundation
import UIKit
import XCTest

@testable import Coloring

@MainActor
final class GalleryImageLoadingTests: XCTestCase {
    func testMissingImagesStopAtRetryLimitWithoutRepeatedInvalidations() async {
        let entry = makeEntry("missing")
        let loader = GalleryRecordingImageLoader()
        let viewModel = makeViewModel(entries: [entry], loader: loader, retries: 2, delay: 1_000_000)
        await viewModel.loadEntries()
        let changes = GalleryChangeCounter()
        let subscription = viewModel.objectWillChange.sink { changes.count += 1 }
        viewModel.setActiveArtworkEntries([entry])

        let exhausted = await waitUntil {
            guard await loader.readCount(entry.fullImagePath) == 3,
                  await loader.readCount(entry.thumbnailPath) == 3
            else { return false }
            if case .failed = viewModel.fullImageLoadState(for: entry) { return true }
            return false
        }
        XCTAssertTrue(exhausted)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let settledChangeCount = changes.count

        for _ in 0..<50 {
            XCTAssertNil(viewModel.fullImage(for: entry))
            XCTAssertNil(viewModel.thumbnailImage(for: entry))
            _ = viewModel.fullImageLoadState(for: entry)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        let fullReads = await loader.readCount(entry.fullImagePath)
        let thumbnailReads = await loader.readCount(entry.thumbnailPath)
        XCTAssertEqual(fullReads, 3)
        XCTAssertEqual(thumbnailReads, 3)
        XCTAssertEqual(changes.count, settledChangeCount)
        withExtendedLifetime(subscription) {}
    }

    func testBodyRequestsCannotBypassPendingRetryDelay() async {
        let entry = makeEntry("waiting")
        let loader = GalleryRecordingImageLoader()
        let viewModel = makeViewModel(entries: [entry], loader: loader, retries: 1, delay: 30_000_000_000)
        await viewModel.loadEntries()
        viewModel.setActiveArtworkEntries([entry])
        let initialReadsFinished = await waitUntil {
            let fullReads = await loader.readCount(entry.fullImagePath)
            let thumbnailReads = await loader.readCount(entry.thumbnailPath)
            return fullReads == 1 && thumbnailReads == 1
        }
        XCTAssertTrue(initialReadsFinished)

        for _ in 0..<100 {
            _ = viewModel.fullImage(for: entry)
            _ = viewModel.fullImageLoadState(for: entry)
            _ = viewModel.thumbnailImage(for: entry)
        }
        await Task.yield()

        let fullReads = await loader.readCount(entry.fullImagePath)
        let thumbnailReads = await loader.readCount(entry.thumbnailPath)
        XCTAssertEqual(fullReads, 1)
        XCTAssertEqual(thumbnailReads, 1)
        viewModel.setDetailArtworkVisible(entry, isVisible: false)
        viewModel.setActiveArtworkEntries([])
    }

    func testDelayedArtworkBecomesAvailableDuringAutomaticRetryWindow() async {
        let entry = makeEntry("restoring")
        let loader = GalleryRecordingImageLoader()
        let viewModel = makeViewModel(entries: [entry], loader: loader, retries: 3, delay: 100_000_000)
        await viewModel.loadEntries()
        viewModel.setActiveArtworkEntries([entry])
        let initialReadFinished = await waitUntil {
            let fullReads = await loader.readCount(entry.fullImagePath)
            let thumbnailReads = await loader.readCount(entry.thumbnailPath)
            return fullReads >= 1 && thumbnailReads >= 1
        }
        XCTAssertTrue(initialReadFinished)
        await loader.setImageData(makeImageData())

        let retried = await waitUntil {
            let fullReads = await loader.readCount(entry.fullImagePath)
            let thumbnailReads = await loader.readCount(entry.thumbnailPath)
            return fullReads >= 2 && thumbnailReads >= 2
        }
        XCTAssertTrue(retried)
        let loaded = await waitUntil { viewModel.fullImage(for: entry) != nil && viewModel.thumbnailImage(for: entry) != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(viewModel.fullImage(for: entry)?.size, CGSize(width: 80, height: 60))
        if case .loaded = viewModel.fullImageLoadState(for: entry) {} else {
            XCTFail("Expected the full-resolution image after delayed restoration.")
        }
    }

    func testGalleryReloadResetsExhaustedFailuresForRestoredArtwork() async {
        let entry = makeEntry("reload")
        let loader = GalleryRecordingImageLoader()
        let viewModel = makeViewModel(entries: [entry], loader: loader, retries: 0)
        await viewModel.loadEntries()
        viewModel.setActiveArtworkEntries([entry])
        let exhausted = await waitUntil {
            if case .failed = viewModel.fullImageLoadState(for: entry) {
                return await loader.readCount(entry.thumbnailPath) == 1
            }
            return false
        }
        XCTAssertTrue(exhausted)
        await loader.setImageData(makeImageData())
        XCTAssertNil(viewModel.fullImage(for: entry))
        XCTAssertNil(viewModel.thumbnailImage(for: entry))
        let readsBeforeReload = await loader.readCount(entry.fullImagePath)
        XCTAssertEqual(readsBeforeReload, 1)

        await viewModel.loadEntries()
        _ = viewModel.fullImage(for: entry)
        _ = viewModel.thumbnailImage(for: entry)
        let recovered = await waitUntil { viewModel.fullImage(for: entry) != nil && viewModel.thumbnailImage(for: entry) != nil }
        XCTAssertTrue(recovered)
        let fullReads = await loader.readCount(entry.fullImagePath)
        let thumbnailReads = await loader.readCount(entry.thumbnailPath)
        XCTAssertEqual(fullReads, 2)
        XCTAssertEqual(thumbnailReads, 2)
    }

    func testVisibleImagesSurviveCachePurgeAndOffscreenPagesDoNotReload() async {
        let entries = (1...5).map { makeEntry("window-\($0)") }
        let loader = GalleryRecordingImageLoader(imageData: makeImageData())
        let viewModel = makeViewModel(entries: entries, loader: loader)
        await viewModel.loadEntries()
        viewModel.setActiveArtworkEntries(Array(entries.prefix(3)))
        viewModel.setThumbnailVisible(entries[3], isVisible: true)

        let loaded = await waitUntil {
            entries.prefix(3).allSatisfy { viewModel.fullImage(for: $0) != nil && viewModel.thumbnailImage(for: $0) != nil }
                && viewModel.thumbnailImage(for: entries[3]) != nil
        }
        XCTAssertTrue(loaded)
        viewModel.purgeInactiveImageCaches()

        for _ in 0..<20 {
            for entry in entries.prefix(3) {
                XCTAssertEqual(viewModel.fullImage(for: entry)?.size, CGSize(width: 80, height: 60))
                XCTAssertNotNil(viewModel.thumbnailImage(for: entry))
            }
            XCTAssertNotNil(viewModel.thumbnailImage(for: entries[3]))
            XCTAssertNil(viewModel.fullImage(for: entries[3]))
            XCTAssertNil(viewModel.fullImage(for: entries[4]))
            XCTAssertNil(viewModel.thumbnailImage(for: entries[4]))
        }
        for entry in entries.prefix(3) {
            let reads = await loader.readCount(entry.fullImagePath)
            XCTAssertEqual(reads, 1)
        }
        let visibleThumbnailReads = await loader.readCount(entries[3].thumbnailPath)
        let offscreenFullReads = await loader.readCount(entries[3].fullImagePath)
        let offscreenThumbnailReads = await loader.readCount(entries[4].thumbnailPath)
        XCTAssertEqual(visibleThumbnailReads, 1)
        XCTAssertEqual(offscreenFullReads, 0)
        XCTAssertEqual(offscreenThumbnailReads, 0)

        viewModel.setActiveArtworkEntries(Array(entries[1...3]))
        let nextLoaded = await waitUntil { viewModel.fullImage(for: entries[3]) != nil }
        XCTAssertTrue(nextLoaded)
        viewModel.purgeInactiveImageCaches()
        XCTAssertNil(viewModel.fullImage(for: entries[0]))
        let departedPageReads = await loader.readCount(entries[0].fullImagePath)
        XCTAssertEqual(departedPageReads, 1)

        viewModel.setActiveArtworkEntries([entries[0]])
        let returnedPageLoaded = await waitUntil { viewModel.fullImage(for: entries[0]) != nil }
        XCTAssertTrue(returnedPageLoaded)
        let returnedPageReads = await loader.readCount(entries[0].fullImagePath)
        XCTAssertEqual(returnedPageReads, 2)
    }

    func testPresentedDetailKeepsRetryingWhenCarouselWindowChangesAndReleasesOnDismissal() async {
        let entries = (1...4).map { makeEntry("detail-\($0)") }
        let detailEntry = entries[0]
        let loader = GalleryRecordingImageLoader()
        let viewModel = makeViewModel(entries: entries, loader: loader, retries: 3, delay: 100_000_000)
        await viewModel.loadEntries()
        viewModel.setActiveArtworkEntries([detailEntry])
        viewModel.setDetailArtworkVisible(detailEntry, isVisible: true)
        let initialReadFinished = await waitUntil {
            let fullReads = await loader.readCount(detailEntry.fullImagePath)
            let thumbnailReads = await loader.readCount(detailEntry.thumbnailPath)
            return fullReads >= 1 && thumbnailReads >= 1
        }
        XCTAssertTrue(initialReadFinished)

        viewModel.setActiveArtworkEntries(Array(entries.suffix(3)))
        await loader.setImageData(makeImageData())
        let detailLoaded = await waitUntil {
            viewModel.fullImage(for: detailEntry) != nil && viewModel.thumbnailImage(for: detailEntry) != nil
        }
        XCTAssertTrue(detailLoaded, "Changing the carousel must not cancel the presented detail's pending retry.")
        viewModel.purgeInactiveImageCaches()
        XCTAssertEqual(viewModel.fullImage(for: detailEntry)?.size, CGSize(width: 80, height: 60))
        XCTAssertNotNil(viewModel.thumbnailImage(for: detailEntry))

        viewModel.setDetailArtworkVisible(detailEntry, isVisible: false)
        viewModel.purgeInactiveImageCaches()
        XCTAssertNil(viewModel.fullImage(for: detailEntry))
        XCTAssertNil(viewModel.thumbnailImage(for: detailEntry))
    }

    func testDirectDetailStateRequestCanFailAndRecoverWithoutCarouselWindow() async {
        let entry = makeEntry("direct-detail")
        let loader = GalleryRecordingImageLoader()
        let viewModel = makeViewModel(entries: [entry], loader: loader, retries: 0)
        await viewModel.loadEntries()
        _ = viewModel.fullImageLoadState(for: entry)
        let failed = await waitUntil {
            if case .failed = viewModel.fullImageLoadState(for: entry) { return true }
            return false
        }
        XCTAssertTrue(failed, "A direct detail request must terminate instead of remaining loading without a carousel window.")

        await loader.setImageData(makeImageData())
        await viewModel.loadEntries()
        let recovered = await waitUntil {
            if case .loaded = viewModel.fullImageLoadState(for: entry) { return true }
            return false
        }
        XCTAssertTrue(recovered)
        XCTAssertEqual(viewModel.fullImage(for: entry)?.size, CGSize(width: 80, height: 60))
        viewModel.setDetailArtworkVisible(entry, isVisible: false)
    }

    private func makeViewModel(
        entries: [ArtworkEntry],
        loader: GalleryRecordingImageLoader,
        retries: Int = 2,
        delay: UInt64 = 1_000_000
    ) -> GalleryViewModel {
        GalleryViewModel(
            galleryStore: GalleryImageTestStore(entries: entries),
            imageLoader: { path in await loader.loadImage(atPath: path) },
            maxImageLoadRetries: retries,
            imageRetryDelayNanoseconds: delay
        )
    }

    private func makeEntry(_ id: String) -> ArtworkEntry {
        ArtworkEntry(
            id: id,
            sourceTemplateID: "template-\(id)",
            sourceTemplateName: "Artwork \(id)",
            createdAt: Date(timeIntervalSince1970: 1),
            fullImageFilename: "\(id).png",
            thumbnailFilename: "\(id)_thumb.png"
        )
    }

    private func makeImageData() -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60), format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return await condition()
    }
}

@MainActor
private final class GalleryChangeCounter {
    var count = 0
}

private actor GalleryRecordingImageLoader {
    private var imageData: Data?
    private var reads: [String: Int] = [:]

    init(imageData: Data? = nil) {
        self.imageData = imageData
    }

    func setImageData(_ data: Data) {
        imageData = data
    }

    func readCount(_ path: String) -> Int {
        reads[path, default: 0]
    }

    func loadImage(atPath path: String) -> UIImage? {
        reads[path, default: 0] += 1
        return imageData.flatMap(UIImage.init(data:))
    }
}

@MainActor
private final class GalleryImageTestStore: GalleryStoreProviding {
    private var entries: [ArtworkEntry]

    init(entries: [ArtworkEntry]) {
        self.entries = entries
    }

    func loadEntries() throws -> [ArtworkEntry] { entries }

    func saveArtwork(imageData: Data, sourceTemplateID: String, sourceTemplateName: String) throws -> ArtworkEntry {
        throw CocoaError(.featureUnsupported)
    }

    func saveArtwork(at fileURL: URL, sourceTemplateID: String, sourceTemplateName: String) throws -> ArtworkEntry {
        throw CocoaError(.featureUnsupported)
    }

    func deleteEntry(_ id: String) throws {
        entries.removeAll { $0.id == id }
    }
}
