import OSLog
import PencilKit
import UIKit
import WidgetKit

protocol ColoringWidgetSnapshotWriting: Sendable {
    func updateCurrentArtwork(
        templateID: String,
        title: String,
        progress: Double,
        imageData: Data
    ) async
    func removeCurrentArtwork(ifMatching templateID: String) async
    func updateLatestGalleryArtwork(_ entry: ArtworkEntry?) async
}

struct DisabledColoringWidgetSnapshotWriter: ColoringWidgetSnapshotWriting {
    func updateCurrentArtwork(
        templateID: String,
        title: String,
        progress: Double,
        imageData: Data
    ) async {}

    func removeCurrentArtwork(ifMatching templateID: String) async {}

    func updateLatestGalleryArtwork(_ entry: ArtworkEntry?) async {}
}

actor ColoringWidgetSnapshotWriter: ColoringWidgetSnapshotWriting {
    static let shared = ColoringWidgetSnapshotWriter()

    private let logger: Logger
    private let fileURLProvider: @Sendable () -> URL?
    private let timelineReloader: @Sendable () -> Void
    private var cachedSnapshot: ColoringWidgetSnapshot?

    init(
        logger: Logger = Logger(subsystem: "Coloring", category: "WidgetSnapshot"),
        fileURLProvider: @escaping @Sendable () -> URL? = {
            ColoringWidgetSnapshotStore.sharedFileURL()
        },
        timelineReloader: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: ColoringWidgetSnapshotStore.widgetKind)
        }
    ) {
        self.logger = logger
        self.fileURLProvider = fileURLProvider
        self.timelineReloader = timelineReloader
    }

    func updateCurrentArtwork(
        templateID: String,
        title: String,
        progress: Double,
        imageData: Data
    ) {
        guard !templateID.isEmpty, !imageData.isEmpty else {
            return
        }

        var snapshot = currentSnapshot()
        snapshot.currentArtwork = ColoringWidgetCurrentArtwork(
            templateID: templateID,
            title: title,
            progress: min(max(progress, 0), 0.99),
            imageData: imageData
        )
        persist(snapshot)
    }

    func removeCurrentArtwork(ifMatching templateID: String) {
        var snapshot = currentSnapshot()
        guard snapshot.currentArtwork?.templateID == templateID else {
            return
        }

        snapshot.currentArtwork = nil
        persist(snapshot)
    }

    func updateLatestGalleryArtwork(_ entry: ArtworkEntry?) {
        var snapshot = currentSnapshot()

        if let entry,
           let imageData = try? Data(contentsOf: URL(fileURLWithPath: entry.thumbnailPath), options: [.mappedIfSafe]),
           !imageData.isEmpty
        {
            snapshot.latestGalleryArtwork = ColoringWidgetGalleryArtwork(
                entryID: entry.id,
                title: entry.sourceTemplateName,
                createdAt: entry.createdAt,
                imageData: imageData
            )
        } else {
            snapshot.latestGalleryArtwork = nil
        }

        persist(snapshot)
    }

    private func currentSnapshot() -> ColoringWidgetSnapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        let snapshot = ColoringWidgetSnapshotStore.load(from: fileURLProvider())
        cachedSnapshot = snapshot
        return snapshot
    }

    private func persist(_ snapshot: ColoringWidgetSnapshot) {
        guard let fileURL = fileURLProvider() else {
            logger.error("App Group container is unavailable for widget snapshot persistence.")
            return
        }

        var updatedSnapshot = snapshot
        updatedSnapshot.updatedAt = Date()

        do {
            let data = try JSONEncoder().encode(updatedSnapshot)
            try data.write(to: fileURL, options: [.atomic])
            cachedSnapshot = updatedSnapshot
            timelineReloader()
        } catch {
            logger.error("Failed to persist widget snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
enum TemplateWidgetArtworkRenderer {
    static func makeImageData(
        templateImage: UIImage,
        drawing: PKDrawing,
        fillImage: UIImage?,
        belowLayerImage: UIImage?,
        aboveLayerImage: UIImage?,
        canvasSize: CGSize,
        maximumLongEdge: CGFloat = 720
    ) -> Data? {
        guard canvasSize.width > 0, canvasSize.height > 0, maximumLongEdge > 0 else {
            return nil
        }

        let scale = min(maximumLongEdge / max(canvasSize.width, canvasSize.height), 1)
        let outputSize = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let normalizedDrawing = drawing.stableColorDrawing(using: lightTraits)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)

        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(outputRect)
            templateImage.stableDisplayImage().draw(in: outputRect)
            fillImage?.stableDisplayImage().draw(in: outputRect)
            belowLayerImage?.stableDisplayImage().draw(in: outputRect)
            normalizedDrawing.image(from: canvasRect, scale: scale).draw(in: outputRect)
            aboveLayerImage?.stableDisplayImage().draw(in: outputRect)
        }

        return image.jpegData(compressionQuality: 0.84)
    }
}
