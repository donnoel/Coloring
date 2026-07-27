import Foundation
import OSLog

enum BuiltInTemplateIdentityPolicy {
    static let retiredManifestTemplateIDs: Set<String> = [
        "builtin_027"
    ]

    static let retiredRuntimeTemplateIDs = Set(
        retiredManifestTemplateIDs.map { "builtin-\($0)" }
    )
}

actor RetiredTemplateDataCleanupService {
    private let drawingStore: any TemplateDrawingStoreProviding
    private let categoryStore: any TemplateCategoryStoreProviding
    private let recentColorsStore: any RecentColorsStoreProviding
    private let progressSnapshotStore: any TemplateProgressSnapshotStoreProviding
    private let galleryStore: any GalleryStoreProviding
    private let widgetSnapshotWriter: any ColoringWidgetSnapshotWriting
    private let logger: Logger

    init(
        drawingStore: any TemplateDrawingStoreProviding = TemplateDrawingStoreService(),
        categoryStore: any TemplateCategoryStoreProviding = TemplateCategoryStoreService(),
        recentColorsStore: any RecentColorsStoreProviding = RecentColorsStoreService(),
        progressSnapshotStore: any TemplateProgressSnapshotStoreProviding = TemplateProgressSnapshotStoreService(),
        galleryStore: any GalleryStoreProviding = GalleryStoreService(),
        widgetSnapshotWriter: any ColoringWidgetSnapshotWriting = ColoringWidgetSnapshotWriter.shared,
        logger: Logger = Logger(subsystem: "Coloring", category: "RetiredTemplateCleanup")
    ) {
        self.drawingStore = drawingStore
        self.categoryStore = categoryStore
        self.recentColorsStore = recentColorsStore
        self.progressSnapshotStore = progressSnapshotStore
        self.galleryStore = galleryStore
        self.widgetSnapshotWriter = widgetSnapshotWriter
        self.logger = logger
    }

    func clean() async {
        let retiredTemplateIDs = BuiltInTemplateIdentityPolicy.retiredRuntimeTemplateIDs

        for templateID in retiredTemplateIDs {
            await deleteColoringData(for: templateID)
            await widgetSnapshotWriter.removeCurrentArtwork(ifMatching: templateID)
        }

        await removeCategoryState(for: retiredTemplateIDs)
        await removeRecentColors(for: retiredTemplateIDs)
        await removeProgressSnapshots(for: retiredTemplateIDs)
        await removeGalleryEntries(for: retiredTemplateIDs)
    }

    private func deleteColoringData(for templateID: String) async {
        do {
            try await drawingStore.deleteDrawingData(for: templateID)
            try await drawingStore.deleteFillData(for: templateID)
            try await drawingStore.deleteLayerStackData(for: templateID)
        } catch {
            logger.error(
                "Failed to delete retired coloring data for \(templateID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func removeCategoryState(for retiredTemplateIDs: Set<String>) async {
        do {
            let assignments = try await categoryStore.loadCategoryAssignments()
            let sanitizedAssignments = assignments.filter { !retiredTemplateIDs.contains($0.key) }
            if sanitizedAssignments != assignments {
                try await categoryStore.saveCategoryAssignments(sanitizedAssignments)
            }

            let favorites = try await categoryStore.loadFavoriteTemplateIDs()
            let sanitizedFavorites = favorites.subtracting(retiredTemplateIDs)
            if sanitizedFavorites != favorites {
                try await categoryStore.saveFavoriteTemplateIDs(sanitizedFavorites)
            }

            let completed = try await categoryStore.loadCompletedTemplateIDs()
            let sanitizedCompleted = completed.subtracting(retiredTemplateIDs)
            if sanitizedCompleted != completed {
                try await categoryStore.saveCompletedTemplateIDs(sanitizedCompleted)
            }

            let recent = try await categoryStore.loadRecentTemplateIDs()
            let sanitizedRecent = recent.filter { !retiredTemplateIDs.contains($0) }
            if sanitizedRecent != recent {
                try await categoryStore.saveRecentTemplateIDs(sanitizedRecent)
            }

            let hidden = try await categoryStore.loadHiddenTemplateIDs()
            let sanitizedHidden = hidden.subtracting(retiredTemplateIDs)
            if sanitizedHidden != hidden {
                try await categoryStore.saveHiddenTemplateIDs(sanitizedHidden)
            }
        } catch {
            logger.error(
                "Failed to remove retired template category state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func removeRecentColors(for retiredTemplateIDs: Set<String>) async {
        do {
            let colors = try await recentColorsStore.loadRecentColorsByTemplateID()
            let sanitizedColors = colors.filter { !retiredTemplateIDs.contains($0.key) }
            if sanitizedColors != colors {
                try await recentColorsStore.saveRecentColorsByTemplateID(sanitizedColors)
            }
        } catch {
            logger.error(
                "Failed to remove retired template recent colors: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func removeProgressSnapshots(for retiredTemplateIDs: Set<String>) async {
        do {
            let snapshots = try await progressSnapshotStore.loadSnapshots()
            let sanitizedSnapshots = snapshots.filter { !retiredTemplateIDs.contains($0.key) }
            if sanitizedSnapshots != snapshots {
                try await progressSnapshotStore.saveSnapshots(sanitizedSnapshots)
            }
        } catch {
            logger.error(
                "Failed to remove retired template progress: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func removeGalleryEntries(for retiredTemplateIDs: Set<String>) async {
        do {
            let entries = try await galleryStore.loadEntries()
            for entry in entries where retiredTemplateIDs.contains(entry.sourceTemplateID) {
                try await galleryStore.deleteEntry(entry.id)
            }
        } catch {
            logger.error(
                "Failed to remove retired template gallery entries: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
