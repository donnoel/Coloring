import Combine
import Foundation
import PencilKit
import UIKit

@MainActor
final class TemplateStudioViewModel: ObservableObject {
    private enum DefaultsKey {
        static let lastSelectedTemplateID = "lastSelectedTemplateID"
    }

    private static let restoredArtworkPreviewHoldNanoseconds: UInt64 = 1_200_000_000

    @Published private(set) var templates: [ColoringTemplate] = []
    @Published var selectedTemplateID: String = ""
    @Published var currentDrawing: PKDrawing
    @Published private(set) var drawingSyncToken: Int = 0
    @Published private(set) var selectedTemplateImage: UIImage?
    @Published private(set) var restoredArtworkPreviewImage: UIImage?
    @Published private(set) var exportStatusMessage: String?
    @Published private(set) var exportErrorMessage: String?
    @Published private(set) var importStatusMessage: String?
    @Published private(set) var importErrorMessage: String?
    @Published private(set) var exportedFileURL: URL?
    @Published private(set) var isExporting: Bool = false
    @Published private(set) var drawingRestoreErrorMessage: String?

    // Fill mode state
    @Published var isFillModeActive: Bool = false
    @Published private(set) var currentFillImage: UIImage?

    // Layer state
    @Published private(set) var currentLayerStack: LayerStack = .singleLayer()
    @Published private(set) var belowLayerImage: UIImage?
    @Published private(set) var aboveLayerImage: UIImage?

    // Brush state
    @Published private(set) var activeBrushPreset: BrushPreset = BrushPreset.builtInPresets.first(where: { $0.id == BrushPreset.defaultPresetID }) ?? BrushPreset.builtInPresets[0]
    @Published var customBrushWidth: CGFloat = 12 {
        didSet { updateCurrentBrushTool() }
    }
    @Published var customBrushOpacity: CGFloat = 1.0 {
        didSet { updateCurrentBrushTool() }
    }
    @Published private(set) var currentBrushTool: PKInkingTool = PKInkingTool(.marker, color: .black, width: 12)
    @Published private(set) var userBrushPresets: [BrushPreset] = []
    @Published private(set) var recentColors: [RecentColorToken] = []
    @Published private(set) var activeColorToken: RecentColorToken?
    @Published private(set) var appliedRecentColor: UIColor?
    @Published private(set) var appliedRecentColorRevision: Int = 0
    @Published private(set) var canUndoEdit: Bool = false
    @Published private(set) var canRedoEdit: Bool = false

    // Category state
    @Published var selectedCategoryFilter: String = TemplateCategory.allCategory.id
    @Published private(set) var builtInCategories: [TemplateCategory] = []
    @Published private(set) var userCategories: [TemplateCategory] = []
    @Published private(set) var categoryAssignments: [String: String] = [:]
    @Published private(set) var categoryOrder: [String] = []
    @Published private(set) var inProgressTemplateIDs: Set<String> = []
    @Published private(set) var favoriteTemplateIDs: Set<String> = []
    @Published private(set) var completedTemplateIDs: Set<String> = []
    @Published private(set) var hiddenTemplateIDs: Set<String> = []
    @Published private(set) var progressSnapshotsByTemplateID: [String: TemplateProgressSnapshot] = [:]
    var visibleInProgressTemplateIDs: Set<String> {
        inProgressTemplateIDs
            .subtracting(completedTemplateIDs)
            .subtracting(hiddenTemplateIDs)
    }
    @Published private(set) var allCategories: [TemplateCategory] = [
        TemplateCategory.allCategory,
        TemplateCategory.inProgressCategory,
        TemplateCategory.favoritesCategory,
        TemplateCategory.recentCategory,
        TemplateCategory.completedCategory,
        TemplateCategory.importedCategory
    ]
    @Published private(set) var reorderableCategories: [TemplateCategory] = []

    private var drawingsByTemplateID: [String: PKDrawing] = [:]
    private var layerStacksByTemplateID: [String: LayerStack] = [:]
    private let fillStateStore = TemplateFillStateStore()
    private var persistedColoringByTemplateID: [String: Bool] = [:]
    private var builtInCategoryNamesByTemplateID: [String: Set<String>] = [:]
    private var recentTemplateIDs: [String] = []
    private var recentColorsByTemplateID: [String: [RecentColorToken]] = [:]
    private let templateLibrary: any TemplateLibraryProviding
    private let importMutationCoordinator: TemplateImportMutationCoordinator
    private let exportCoordinator: TemplateExportCoordinator
    private let persistenceCoordinator: TemplateColoringPersistenceCoordinator
    private let coloringPersistenceInspector: TemplateColoringPersistenceInspector
    private let progressEstimator: TemplateProgressEstimator
    private let progressSnapshotStore: any TemplateProgressSnapshotStoreProviding
    private let drawingStore: any TemplateDrawingStoreProviding
    private let floodFillService: any FloodFillProviding
    private let layerCompositor: any LayerCompositing
    private let brushPresetStore: any BrushPresetStoreProviding
    private let recentColorsStore: any RecentColorsStoreProviding
    private let categoryPersistenceCoordinator: TemplateCategoryPersistenceCoordinator
    private var hasLoadedTemplates = false
    private var loadedTemplateImageID: String?
    private var templateImageLoadTask: Task<Void, Never>?
    private var cloudRestoreTask: Task<Void, Never>?
    private var debouncedPersistTask: Task<Void, Never>?
    private var debouncedProgressTask: Task<Void, Never>?
    private var fillOverlayTask: Task<Void, Never>?
    private var fillOverlayOperationID = 0
    private var fillRestoreOperationID = 0
    private var restoredArtworkPreviewDismissTask: Task<Void, Never>?
    private var pendingPersistTemplateIDs: Set<String> = []
    private var persistenceRevisionStore = TemplatePersistenceRevisionStore()
    private let editHistoryStore = TemplateEditHistoryStore<TemplateEditSnapshot>(maxSteps: 100)
    private let maxRecentTemplates = 20

    init(
        templateLibrary: any TemplateLibraryProviding,
        exportService: any TemplateArtworkExporting,
        drawingStore: any TemplateDrawingStoreProviding,
        floodFillService: any FloodFillProviding,
        layerCompositor: any LayerCompositing,
        brushPresetStore: any BrushPresetStoreProviding,
        categoryStore: any TemplateCategoryStoreProviding,
        galleryStore: any GalleryStoreProviding,
        recentColorsStore: any RecentColorsStoreProviding = RecentColorsStoreService(),
        progressSnapshotStore: any TemplateProgressSnapshotStoreProviding = TemplateProgressSnapshotStoreService()
    ) {
        self.templateLibrary = templateLibrary
        self.importMutationCoordinator = TemplateImportMutationCoordinator(
            templateLibrary: templateLibrary,
            drawingStore: drawingStore
        )
        self.exportCoordinator = TemplateExportCoordinator(
            exportService: exportService,
            galleryStore: galleryStore
        )
        self.persistenceCoordinator = TemplateColoringPersistenceCoordinator(
            drawingStore: drawingStore
        )
        self.coloringPersistenceInspector = TemplateColoringPersistenceInspector(
            drawingStore: drawingStore
        )
        self.progressEstimator = TemplateProgressEstimator()
        self.progressSnapshotStore = progressSnapshotStore
        self.drawingStore = drawingStore
        self.floodFillService = floodFillService
        self.layerCompositor = layerCompositor
        self.brushPresetStore = brushPresetStore
        self.recentColorsStore = recentColorsStore
        self.categoryPersistenceCoordinator = TemplateCategoryPersistenceCoordinator(
            categoryStore: categoryStore
        )
        self.currentDrawing = PKDrawing()
    }

    convenience init() {
        self.init(
            templateLibrary: TemplateLibraryService(),
            exportService: TemplateArtworkExportService(),
            drawingStore: TemplateDrawingStoreService(),
            floodFillService: FloodFillService(),
            layerCompositor: LayerCompositorService(),
            brushPresetStore: BrushPresetStoreService(),
            categoryStore: TemplateCategoryStoreService(),
            galleryStore: GalleryStoreService(),
            recentColorsStore: RecentColorsStoreService()
        )
    }

    var selectedTemplate: ColoringTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }

    var visibleTemplates: [ColoringTemplate] {
        templates.filter { !hiddenTemplateIDs.contains($0.id) }
    }

    var hiddenTemplates: [ColoringTemplate] {
        templates
            .filter { hiddenTemplateIDs.contains($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var visibleImportedTemplateCount: Int {
        visibleTemplates.filter(\.isImported).count
    }

    var hasImportedTemplates: Bool {
        templates.contains(where: \.isImported)
    }

    var selectedTemplateAspectRatio: CGFloat {
        TemplateStudioDrawingExportSupport.selectedTemplateAspectRatio(for: selectedTemplateImage)
    }

    @discardableResult
    private func assignIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<TemplateStudioViewModel, T>,
        to value: T
    ) -> Bool {
        guard self[keyPath: keyPath] != value else {
            return false
        }

        self[keyPath: keyPath] = value
        return true
    }

    // MARK: - Template Loading

    func loadTemplatesIfNeeded() async {
        guard !hasLoadedTemplates else {
            return
        }

        hasLoadedTemplates = await reloadTemplates()
        scheduleDeferredCloudRestoreIfNeeded()
        exportCoordinator.cleanUpStaleExportFiles()
    }

    func refreshTemplatesFromStorage() async {
        guard hasLoadedTemplates else {
            return
        }

        hasLoadedTemplates = await reloadTemplates()
        scheduleDeferredCloudRestoreIfNeeded()
    }

    @discardableResult
    func reloadTemplates() async -> Bool {
        let previousTemplateID = selectedTemplateID

        templateImageLoadTask?.cancel()
        templateImageLoadTask = nil
        cancelPendingFillRestoreWork()

        do {
            let loadedTemplates = try await templateLibrary.loadTemplates()
            let reloadResolution = TemplateReloadStateResolver.resolve(
                loadedTemplates: loadedTemplates,
                hiddenTemplateIDs: hiddenTemplateIDs,
                currentSelectedTemplateID: selectedTemplateID,
                lastSelectedTemplateID: UserDefaults.standard.string(forKey: DefaultsKey.lastSelectedTemplateID),
                recentTemplateIDs: recentTemplateIDs
            )
            assignIfChanged(\.templates, to: loadedTemplates)
            builtInCategoryNamesByTemplateID = reloadResolution.builtInCategoryNamesByTemplateID
            assignIfChanged(\.builtInCategories, to: reloadResolution.builtInCategories)
            syncCategoryOrderWithAvailableCategories()
            let validTemplateIDs = reloadResolution.validTemplateIDs
            drawingsByTemplateID = drawingsByTemplateID.filter { validTemplateIDs.contains($0.key) }
            layerStacksByTemplateID = layerStacksByTemplateID.filter { validTemplateIDs.contains($0.key) }
            fillStateStore.retainEntries(for: validTemplateIDs)
            persistedColoringByTemplateID = persistedColoringByTemplateID.filter { validTemplateIDs.contains($0.key) }
            progressSnapshotsByTemplateID = progressSnapshotsByTemplateID.filter { validTemplateIDs.contains($0.key) }
            let filteredRecentColorsByTemplateID = recentColorsByTemplateID.filter { validTemplateIDs.contains($0.key) }
            if filteredRecentColorsByTemplateID != recentColorsByTemplateID {
                recentColorsByTemplateID = filteredRecentColorsByTemplateID
                persistRecentColors()
            }
            persistenceRevisionStore.retainRevisions(for: validTemplateIDs)
            editHistoryStore.retainHistories(for: validTemplateIDs)
            assignIfChanged(\.favoriteTemplateIDs, to: favoriteTemplateIDs.intersection(validTemplateIDs))
            assignIfChanged(\.completedTemplateIDs, to: completedTemplateIDs.intersection(validTemplateIDs))
            assignIfChanged(\.hiddenTemplateIDs, to: hiddenTemplateIDs.intersection(validTemplateIDs))
            if recentTemplateIDs != reloadResolution.filteredRecentTemplateIDs {
                recentTemplateIDs = reloadResolution.filteredRecentTemplateIDs
            }
            importErrorMessage = nil

            if selectedTemplateID != reloadResolution.selectedTemplateID {
                selectedTemplateID = reloadResolution.selectedTemplateID
            }

            persistLastSelectedTemplateID(selectedTemplateID)
            refreshEditAvailability()

            if selectedTemplateID != previousTemplateID {
                // Only clear when selection changed; preserving same-template image avoids launch flicker.
                clearRestoredArtworkPreview()
                selectedTemplateImage = nil
                loadedTemplateImageID = nil
                refreshRecentColorsForSelectedTemplate()
            }

            await prepareSelectedTemplateForDisplay(selectedTemplateID)
            await restoreInProgressTemplateIDs(for: loadedTemplates.map(\.id))
            await restoreProgressSnapshots(for: validTemplateIDs)
            return true
        } catch {
            importErrorMessage = "Could not load templates: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Template Selection

    func selectTemplate(_ templateID: String) {
        guard templates.contains(where: { $0.id == templateID }) else {
            return
        }

        guard selectedTemplateID != templateID else {
            return
        }

        finalizePendingStrokeEditChange(for: selectedTemplateID)
        persistCurrentDrawing()
        persistCurrentFill()
        cancelPendingFillOverlayWork()
        cancelPendingFillRestoreWork()
        clearRestoredArtworkPreview()
        // Clear before changing the selection so SwiftUI cannot show the previous live canvas for the new ID.
        selectedTemplateImage = nil
        loadedTemplateImageID = nil
        selectedTemplateID = templateID
        refreshRecentColorsForSelectedTemplate()
        persistLastSelectedTemplateID(templateID)
        markTemplateAsRecent(templateID)
        refreshEditAvailability()
        restoreCachedDrawingForSelectedTemplate()
        restoreCachedFillForSelectedTemplate()

        templateImageLoadTask?.cancel()
        templateImageLoadTask = Task { [weak self] in
            await self?.prepareSelectedTemplateForDisplay(templateID)
        }

        invalidateExport()
    }

    // MARK: - Drawing

    func updateStrokeInteraction(isActive: Bool) {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        if isActive {
            clearRestoredArtworkPreview()
            beginPendingStrokeEditChangeIfNeeded(for: selectedTemplateID)
        } else {
            finalizePendingStrokeEditChange(for: selectedTemplateID)
        }
    }

    func updateDrawing(_ drawing: PKDrawing) {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        let templateID = selectedTemplateID
        // Fallback boundary detection: if a stroke-end callback is missed, a new
        // stroke still increases the stroke count. Split pending history at that
        // boundary so undo remains one stroke at a time.
        if TemplateStrokeBoundaryResolver.shouldSplitPendingStroke(
            hasPendingStroke: editHistoryStore.hasPendingStroke(for: templateID),
            previousStrokeCount: currentDrawing.strokes.count,
            updatedStrokeCount: drawing.strokes.count
        )
        {
            finalizePendingStrokeEditChange(for: templateID)
            beginPendingStrokeEditChangeIfNeeded(for: templateID)
        }

        let previousStrokeCount = currentDrawing.strokes.count
        let shouldRecordImmediately = !editHistoryStore.hasPendingStroke(for: templateID)
        let previousSnapshot = snapshot(for: selectedTemplateID)
        currentDrawing = drawing
        drawingsByTemplateID[selectedTemplateID] = drawing
        currentLayerStack.updateDrawingData(serializedDrawingData(for: drawing), for: currentLayerStack.activeLayerID)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        recordUsedStrokeColorIfNeeded(from: drawing, previousStrokeCount: previousStrokeCount)
        if shouldRecordImmediately {
            recordEditChange(from: previousSnapshot, for: selectedTemplateID)
        }
        refreshInProgressState(for: selectedTemplateID)
        scheduleProgressSnapshotUpdate(for: selectedTemplateID)
        debouncedPersistLayerStack(for: selectedTemplateID)
        invalidateExport()
    }

    func clearDrawing() {
        clearRestoredArtworkPreview()
        finalizePendingStrokeEditChange(for: selectedTemplateID)
        let previousSnapshot = snapshot(for: selectedTemplateID)
        setCurrentDrawingFromModel(PKDrawing())
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
        currentLayerStack.updateDrawingData(Data(), for: currentLayerStack.activeLayerID)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
        refreshInProgressState(for: selectedTemplateID)
        scheduleProgressSnapshotUpdate(for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        invalidateExport()
    }

    func normalizeSelectedTemplateColoring(using traitCollection: UITraitCollection?) {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        let normalizedDrawing = currentDrawing.stableColorDrawing(using: traitCollection)
        let normalizedLayerStack = TemplateColorNormalization.normalizedLayerStack(
            currentLayerStack,
            using: traitCollection
        )

        guard normalizedDrawing != currentDrawing || normalizedLayerStack != currentLayerStack else {
            return
        }

        setCurrentDrawingFromModel(normalizedDrawing)
        currentLayerStack = normalizedLayerStack
        drawingsByTemplateID[selectedTemplateID] = normalizedDrawing
        layerStacksByTemplateID[selectedTemplateID] = normalizedLayerStack
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        invalidateExport()
    }

    // MARK: - Layers

    func addLayer() {
        let previousSnapshot = snapshot(for: selectedTemplateID)
        syncActiveLayerDrawingToStack()
        let newLayer = currentLayerStack.addLayer(name: "Layer \(currentLayerStack.layers.count)")
        setCurrentDrawingFromModel(PKDrawing())
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
        refreshInProgressState(for: selectedTemplateID)
        scheduleProgressSnapshotUpdate(for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        _ = newLayer
    }

    func deleteLayer(_ id: UUID) {
        guard currentLayerStack.layers.count > 1 else {
            return
        }

        let previousSnapshot = snapshot(for: selectedTemplateID)
        syncActiveLayerDrawingToStack()
        let wasActive = currentLayerStack.activeLayerID == id
        currentLayerStack.removeLayer(id)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack

        if wasActive {
            restoreActiveLayerDrawing()
        }

        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
        refreshInProgressState(for: selectedTemplateID)
        scheduleProgressSnapshotUpdate(for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        invalidateExport()
    }

    func selectActiveLayer(_ id: UUID) {
        guard id != currentLayerStack.activeLayerID else {
            return
        }

        syncActiveLayerDrawingToStack()
        currentLayerStack.activeLayerID = id
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        restoreActiveLayerDrawing()
        recompositeLayerOverlays()
    }

    func toggleLayerVisibility(_ id: UUID) {
        let previousSnapshot = snapshot(for: selectedTemplateID)
        currentLayerStack.toggleVisibility(id)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        scheduleProgressSnapshotUpdate(for: selectedTemplateID)
        invalidateExport()
    }

    func renameLayer(_ id: UUID, to name: String) {
        currentLayerStack.renameLayer(id, to: name)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        persistLayerStack(for: selectedTemplateID)
    }

    func moveLayer(from source: IndexSet, to destination: Int) {
        let previousSnapshot = snapshot(for: selectedTemplateID)
        currentLayerStack.moveLayer(from: source, to: destination)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        scheduleProgressSnapshotUpdate(for: selectedTemplateID)
        invalidateExport()
    }

    func mergeDown(_ id: UUID) {
        let previousSnapshot = snapshot(for: selectedTemplateID)
        syncActiveLayerDrawingToStack()
        guard let mergedLayerStack = TemplateLayerMergeService.mergeDown(
            in: currentLayerStack,
            upperLayerID: id
        ) else {
            return
        }

        currentLayerStack = mergedLayerStack
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        restoreActiveLayerDrawing()
        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
        refreshInProgressState(for: selectedTemplateID)
        scheduleProgressSnapshotUpdate(for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        invalidateExport()
    }

    private func syncActiveLayerDrawingToStack() {
        let drawingData = serializedDrawingData(for: currentDrawing)
        currentLayerStack.updateDrawingData(drawingData, for: currentLayerStack.activeLayerID)
    }

    private func setCurrentDrawingFromModel(_ drawing: PKDrawing) {
        currentDrawing = drawing
        drawingSyncToken += 1
    }

    private func restoreActiveLayerDrawing() {
        setCurrentDrawingFromModel(TemplateEditSnapshotResolver.drawing(from: currentLayerStack))
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
    }

    private func recompositeLayerOverlays() {
        let canvasSize = bestExportSize(for: selectedTemplateImage)
        belowLayerImage = layerCompositor.compositeLayersBelow(
            layers: currentLayerStack.layers,
            activeLayerID: currentLayerStack.activeLayerID,
            canvasSize: canvasSize
        )
        aboveLayerImage = layerCompositor.compositeLayersAbove(
            layers: currentLayerStack.layers,
            activeLayerID: currentLayerStack.activeLayerID,
            canvasSize: canvasSize
        )
    }

    // MARK: - Brush Customization

    var allBrushPresets: [BrushPreset] {
        BrushPreset.builtInPresets + userBrushPresets
    }

    func selectBrushPreset(_ preset: BrushPreset) {
        activeBrushPreset = preset
        customBrushWidth = preset.width
        customBrushOpacity = preset.opacity
        // updateCurrentBrushTool() is triggered by didSet on width/opacity
    }

    func saveCurrentAsPreset(name: String) {
        let preset = BrushPreset(
            id: "custom-\(UUID().uuidString)",
            name: name,
            inkType: activeBrushPreset.inkType,
            width: customBrushWidth,
            opacity: customBrushOpacity,
            isBuiltIn: false
        )
        userBrushPresets.append(preset)
        persistUserPresets()
    }

    func deleteCustomPreset(_ id: String) {
        userBrushPresets.removeAll { $0.id == id }
        if activeBrushPreset.id == id {
            selectBrushPreset(BrushPreset.builtInPresets[0])
        }
        persistUserPresets()
    }

    func loadBrushPresetsIfNeeded() {
        Task { [brushPresetStore] in
            do {
                let presets = try await brushPresetStore.loadUserPresets()
                self.userBrushPresets = presets
            } catch {
                // Silently ignore - user starts with built-in presets only
            }
        }
    }

    func loadRecentColorsIfNeeded() {
        Task { [recentColorsStore] in
            do {
                let colorsByTemplateID = try await recentColorsStore.loadRecentColorsByTemplateID()
                let validTemplateIDs = Set(self.templates.map(\.id))
                if validTemplateIDs.isEmpty {
                    self.recentColorsByTemplateID = colorsByTemplateID
                } else {
                    let filteredColorsByTemplateID = colorsByTemplateID.filter { validTemplateIDs.contains($0.key) }
                    self.recentColorsByTemplateID = filteredColorsByTemplateID
                    if filteredColorsByTemplateID.count != colorsByTemplateID.count {
                        self.persistRecentColors()
                    }
                }
                self.refreshRecentColorsForSelectedTemplate()
            } catch {
                self.recentColorsByTemplateID = [:]
                self.assignIfChanged(\.recentColors, to: [])
                self.activeColorToken = nil
            }
        }
    }

    func recordUsedColor(_ color: UIColor) {
        guard !selectedTemplateID.isEmpty else {
            return
        }
        guard let token = RecentColorToken(uiColor: color) else {
            return
        }

        activeColorToken = token
        updateRecentColors(with: token)
    }

    func applyRecentColor(_ token: RecentColorToken) {
        guard !selectedTemplateID.isEmpty else {
            return
        }
        activeColorToken = token
        appliedRecentColor = token.uiColor
        appliedRecentColorRevision += 1
    }

    private func recordUsedStrokeColorIfNeeded(from drawing: PKDrawing, previousStrokeCount: Int) {
        guard drawing.strokes.count > previousStrokeCount,
              let color = drawing.strokes.last?.ink.color
        else {
            return
        }

        recordUsedColor(color)
    }

    private func updateCurrentBrushTool() {
        currentBrushTool = PKInkingTool(
            activeBrushPreset.inkType.pkInkType,
            color: UIColor.black.withAlphaComponent(customBrushOpacity),
            width: customBrushWidth
        )
    }

    private func updateRecentColors(with token: RecentColorToken) {
        let updatedColors = RecentColorsStoreService.inserting(
            token,
            into: recentColorsByTemplateID[selectedTemplateID] ?? []
        )
        guard updatedColors != recentColorsByTemplateID[selectedTemplateID] else {
            return
        }

        recentColorsByTemplateID[selectedTemplateID] = updatedColors
        recentColors = updatedColors
        persistRecentColors()
    }

    private func refreshRecentColorsForSelectedTemplate() {
        assignIfChanged(\.recentColors, to: recentColorsByTemplateID[selectedTemplateID] ?? [])
        activeColorToken = nil
    }

    private func persistUserPresets() {
        let presets = userBrushPresets
        Task { [brushPresetStore, presets] in
            try? await brushPresetStore.saveUserPresets(presets)
        }
    }

    private func persistRecentColors() {
        let colorsByTemplateID = recentColorsByTemplateID
        Task { [recentColorsStore, colorsByTemplateID] in
            try? await recentColorsStore.saveRecentColorsByTemplateID(colorsByTemplateID)
        }
    }

    // MARK: - Template Categories

    var filteredTemplates: [ColoringTemplate] {
        TemplateCategoryViewStateBuilder.filteredTemplates(
            templates: visibleTemplates,
            selectedCategoryFilter: selectedCategoryFilter,
            visibleInProgressTemplateIDs: visibleInProgressTemplateIDs,
            favoriteTemplateIDs: favoriteTemplateIDs,
            recentTemplateIDs: recentTemplateIDs,
            completedTemplateIDs: completedTemplateIDs,
            categoryAssignments: categoryAssignments,
            builtInCategories: builtInCategories,
            builtInCategoryNamesByTemplateID: builtInCategoryNamesByTemplateID
        )
    }

    func createUserCategory(name: String) {
        let category = TemplateCategoryMutationSupport.makeUserCategory(
            name: name,
            id: "user-\(UUID().uuidString)"
        )
        userCategories = TemplateCategoryMutationSupport.appendingCategory(category, to: userCategories)
        syncCategoryOrderWithAvailableCategories()
        persistUserCategories()
        persistCategoryOrder()
    }

    func renameUserCategory(_ id: String, to name: String) {
        guard let index = userCategories.firstIndex(where: { $0.id == id }) else {
            return
        }
        userCategories = TemplateCategoryMutationSupport.renamingCategory(
            in: userCategories,
            at: index,
            to: name
        )
        rebuildCategoryLists()
        persistUserCategories()
    }

    func deleteUserCategory(_ id: String) {
        let mutation = TemplateCategoryMutationSupport.deletingCategoryState(
            categoryID: id,
            userCategories: userCategories,
            categoryOrder: categoryOrder,
            categoryAssignments: categoryAssignments,
            selectedCategoryFilter: selectedCategoryFilter
        )
        userCategories = mutation.userCategories
        categoryOrder = mutation.categoryOrder
        categoryAssignments = mutation.categoryAssignments
        selectedCategoryFilter = mutation.selectedCategoryFilter
        syncCategoryOrderWithAvailableCategories()
        persistUserCategories()
        persistCategoryAssignments()
        persistCategoryOrder()
    }

    func assignTemplate(_ templateID: String, toCategoryID categoryID: String?) {
        categoryAssignments = TemplateCategoryMutationSupport.assigningTemplate(
            templateID,
            to: categoryID,
            in: categoryAssignments
        )
        persistCategoryAssignments()
    }

    func moveCategories(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else {
            return
        }

        categoryOrder = TemplateCategoryMutationSupport.movedCategoryOrder(
            reorderableCategories: reorderableCategories,
            source: source,
            destination: destination
        )
        rebuildCategoryLists()
        persistCategoryOrder()
    }

    func toggleFavorite(for templateID: String) {
        guard templates.contains(where: { $0.id == templateID }) else {
            return
        }

        favoriteTemplateIDs = TemplateCategoryMutationSupport.toggledMembership(
            of: templateID,
            in: favoriteTemplateIDs
        )

        persistFavoriteTemplateIDs()
    }

    func toggleCompleted(for templateID: String) {
        guard templates.contains(where: { $0.id == templateID }) else {
            return
        }

        completedTemplateIDs = TemplateCategoryMutationSupport.toggledMembership(
            of: templateID,
            in: completedTemplateIDs
        )

        persistCompletedTemplateIDs()
        scheduleProgressSnapshotUpdate(for: templateID)
    }

    func hideTemplate(_ templateID: String) {
        guard templates.contains(where: { $0.id == templateID }),
              !hiddenTemplateIDs.contains(templateID)
        else {
            return
        }

        hiddenTemplateIDs = TemplateCategoryMutationSupport.insertingTemplateID(
            templateID,
            into: hiddenTemplateIDs
        )
        persistHiddenTemplateIDs()
        refreshBuiltInCategoriesFromVisibleTemplates()
    }

    func unhideTemplate(_ templateID: String) {
        guard hiddenTemplateIDs.contains(templateID) else {
            return
        }

        hiddenTemplateIDs = TemplateCategoryMutationSupport.removingTemplateID(
            templateID,
            from: hiddenTemplateIDs
        )
        persistHiddenTemplateIDs()
        refreshBuiltInCategoriesFromVisibleTemplates()
    }

    func unhideAllTemplates() {
        guard !hiddenTemplateIDs.isEmpty else {
            return
        }

        hiddenTemplateIDs = TemplateCategoryMutationSupport.clearingTemplateIDs()
        persistHiddenTemplateIDs()
        refreshBuiltInCategoriesFromVisibleTemplates()
    }

    func isFavorite(_ templateID: String) -> Bool {
        favoriteTemplateIDs.contains(templateID)
    }

    func isCompleted(_ templateID: String) -> Bool {
        completedTemplateIDs.contains(templateID)
    }

    func displayedProgress(for templateID: String) -> Double? {
        if completedTemplateIDs.contains(templateID) {
            return 1
        }

        guard visibleInProgressTemplateIDs.contains(templateID),
              let snapshot = progressSnapshotsByTemplateID[templateID]
        else {
            return nil
        }

        return snapshot.estimatedProgress
    }

    func isHidden(_ templateID: String) -> Bool {
        hiddenTemplateIDs.contains(templateID)
    }

    func loadCategoriesIfNeeded() {
        Task { [categoryPersistenceCoordinator] in
            do {
                let storedState = try await categoryPersistenceCoordinator.loadState()
                self.assignIfChanged(\.userCategories, to: storedState.userCategories)
                self.assignIfChanged(\.categoryAssignments, to: storedState.categoryAssignments)
                self.assignIfChanged(\.categoryOrder, to: storedState.categoryOrder)
                self.assignIfChanged(\.favoriteTemplateIDs, to: storedState.favoriteTemplateIDs)
                self.assignIfChanged(\.completedTemplateIDs, to: storedState.completedTemplateIDs)
                self.assignIfChanged(\.hiddenTemplateIDs, to: storedState.hiddenTemplateIDs)
                self.recentTemplateIDs = storedState.recentTemplateIDs
                self.filterStoredTemplateStateToAvailableTemplates()
                self.refreshBuiltInCategoriesFromVisibleTemplates()
                self.markTemplateAsRecent(self.selectedTemplateID)
            } catch {
                // Silently ignore - starts with empty user categories
                self.refreshBuiltInCategoriesFromVisibleTemplates()
                self.markTemplateAsRecent(self.selectedTemplateID)
            }
        }
        assignIfChanged(\.builtInCategories, to: TemplateCategory.builtInCategories(from: visibleTemplates))
        syncCategoryOrderWithAvailableCategories()
    }

    private func persistUserCategories() {
        categoryPersistenceCoordinator.persistUserCategories(userCategories)
    }

    private func persistCategoryAssignments() {
        categoryPersistenceCoordinator.persistCategoryAssignments(categoryAssignments)
    }

    private func persistCategoryOrder() {
        categoryPersistenceCoordinator.persistCategoryOrder(categoryOrder)
    }

    private func persistFavoriteTemplateIDs() {
        categoryPersistenceCoordinator.persistFavoriteTemplateIDs(favoriteTemplateIDs)
    }

    private func persistCompletedTemplateIDs() {
        categoryPersistenceCoordinator.persistCompletedTemplateIDs(completedTemplateIDs)
    }

    private func persistRecentTemplateIDs() {
        categoryPersistenceCoordinator.persistRecentTemplateIDs(recentTemplateIDs)
    }

    private func persistHiddenTemplateIDs() {
        categoryPersistenceCoordinator.persistHiddenTemplateIDs(hiddenTemplateIDs)
    }

    private func markTemplateAsRecent(_ templateID: String) {
        let availableTemplateIDs = Set(templates.map(\.id))
        guard let updatedRecentTemplateIDs = TemplateCategoryStateSanitizer.markedRecentTemplateIDs(
            templateID: templateID,
            availableTemplateIDs: availableTemplateIDs,
            recentTemplateIDs: recentTemplateIDs,
            maxRecentTemplates: maxRecentTemplates
        ) else {
            return
        }

        recentTemplateIDs = updatedRecentTemplateIDs
        persistRecentTemplateIDs()
    }

    private func filterStoredTemplateStateToAvailableTemplates() {
        let validTemplateIDs = Set(templates.map(\.id))
        let sanitizedState = TemplateCategoryStateSanitizer.sanitizeStoredState(
            favoriteTemplateIDs: favoriteTemplateIDs,
            completedTemplateIDs: completedTemplateIDs,
            recentTemplateIDs: recentTemplateIDs,
            hiddenTemplateIDs: hiddenTemplateIDs,
            validTemplateIDs: validTemplateIDs
        )
        assignIfChanged(\.favoriteTemplateIDs, to: sanitizedState.favoriteTemplateIDs)
        assignIfChanged(\.completedTemplateIDs, to: sanitizedState.completedTemplateIDs)
        assignIfChanged(\.hiddenTemplateIDs, to: sanitizedState.hiddenTemplateIDs)
        if recentTemplateIDs != sanitizedState.recentTemplateIDs {
            recentTemplateIDs = sanitizedState.recentTemplateIDs
        }
    }

    private func rebuildCategoryLists() {
        let computedState = TemplateCategoryViewStateBuilder.computeState(
            categoryOrder: categoryOrder,
            builtInCategories: builtInCategories,
            userCategories: userCategories
        )
        assignIfChanged(\.reorderableCategories, to: computedState.reorderableCategories)
        assignIfChanged(\.allCategories, to: computedState.allCategories)
    }

    private func syncCategoryOrderWithAvailableCategories() {
        let computedState = TemplateCategoryViewStateBuilder.computeState(
            categoryOrder: categoryOrder,
            builtInCategories: builtInCategories,
            userCategories: userCategories
        )
        assignIfChanged(\.categoryOrder, to: computedState.categoryOrder)
        assignIfChanged(\.reorderableCategories, to: computedState.reorderableCategories)
        assignIfChanged(\.allCategories, to: computedState.allCategories)
    }

    private func refreshBuiltInCategoriesFromVisibleTemplates() {
        assignIfChanged(\.builtInCategories, to: TemplateCategory.builtInCategories(from: visibleTemplates))
        syncCategoryOrderWithAvailableCategories()
        if !allCategories.contains(where: { $0.id == selectedCategoryFilter }) {
            selectedCategoryFilter = TemplateCategory.allCategory.id
        }
        reconcileSelectionAfterVisibilityChange()
    }

    private func reconcileSelectionAfterVisibilityChange() {
        guard hiddenTemplateIDs.contains(selectedTemplateID) else {
            return
        }

        if let fallbackTemplateID = visibleTemplates.first?.id {
            selectTemplate(fallbackTemplateID)
            return
        }

        finalizePendingStrokeEditChange(for: selectedTemplateID)
        persistCurrentDrawing()
        persistCurrentFill()
        clearRestoredArtworkPreview()
        selectedTemplateID = ""
        persistLastSelectedTemplateID("")
        selectedTemplateImage = nil
        loadedTemplateImageID = nil
        setCurrentDrawingFromModel(PKDrawing())
        currentLayerStack = .singleLayer()
        currentFillImage = nil
        belowLayerImage = nil
        aboveLayerImage = nil
        refreshEditAvailability()
    }

    // MARK: - Fill Mode

    func handleFillTap(at normalizedPoint: CGPoint, color: UIColor? = nil) {
        guard isFillModeActive,
              let templateImage = selectedTemplateImage
        else {
            return
        }
        clearRestoredArtworkPreview()
        finalizePendingStrokeEditChange(for: selectedTemplateID)
        let fillColor = color ?? currentBrushTool.color

        cancelPendingFillRestoreWork()
        let templateID = selectedTemplateID
        let currentFillData = fillStateStore.fillData(for: templateID)
        let request = FillOverlayRequest(
            templateImage: templateImage,
            existingFillImage: currentFillImage,
            normalizedPoint: normalizedPoint,
            fillColor: fillColor
        )
        let floodFillService = floodFillService

        cancelPendingFillOverlayWork()
        let operationID = fillOverlayOperationID

        fillOverlayTask = Task { [templateID, currentFillData, request] in
            defer {
                if fillOverlayOperationID == operationID {
                    fillOverlayTask = nil
                }
            }

            let nextFillData = await Task.detached(priority: .userInitiated) {
                FillOverlayRenderer.makeFillOverlayData(
                    request: request,
                    floodFillService: floodFillService
                )
            }.value

            guard !Task.isCancelled,
                  selectedTemplateID == templateID,
                  fillOverlayOperationID == operationID,
                  let nextFillData,
                  nextFillData != currentFillData
            else {
                return
            }

            let previousSnapshot = snapshot(for: templateID)
            applyFillData(nextFillData, for: templateID)
            recordUsedColor(fillColor)
            recordEditChange(from: previousSnapshot, for: templateID)
        }
    }

    func handleFillErase(at normalizedPoint: CGPoint) {
        guard !selectedTemplateID.isEmpty,
              let currentFillImage
        else {
            return
        }

        clearRestoredArtworkPreview()
        finalizePendingStrokeEditChange(for: selectedTemplateID)
        cancelPendingFillRestoreWork()
        cancelPendingFillOverlayWork()
        let eraseResult = TemplateFillEraseService.eraseRegion(in: currentFillImage, at: normalizedPoint)
        guard eraseResult.didChange else {
            return
        }

        let previousSnapshot = snapshot(for: selectedTemplateID)
        let nextFillData = eraseResult.fillData ?? Data()
        applyFillData(nextFillData, for: selectedTemplateID, cachedImage: eraseResult.fillImage)
        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
    }

    func clearFills() {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        clearRestoredArtworkPreview()
        finalizePendingStrokeEditChange(for: selectedTemplateID)
        let currentFillData = fillStateStore.fillData(for: selectedTemplateID)
        guard currentFillData != nil else {
            return
        }

        cancelPendingFillRestoreWork()
        cancelPendingFillOverlayWork()
        let previousSnapshot = snapshot(for: selectedTemplateID)
        applyFillData(Data(), for: selectedTemplateID)
        recordEditChange(from: previousSnapshot, for: selectedTemplateID)
    }

    func undoLastEdit() {
        clearRestoredArtworkPreview()
        finalizePendingStrokeEditChange(for: selectedTemplateID)
        guard !selectedTemplateID.isEmpty,
              let previousSnapshot = editHistoryStore.undo(
                  for: selectedTemplateID,
                  currentSnapshot: snapshot(for: selectedTemplateID)
              )
        else {
            return
        }
        refreshEditAvailability()
        applyEditSnapshot(previousSnapshot, for: selectedTemplateID)
    }

    func redoLastEdit() {
        clearRestoredArtworkPreview()
        finalizePendingStrokeEditChange(for: selectedTemplateID)
        guard !selectedTemplateID.isEmpty,
              let nextSnapshot = editHistoryStore.redo(
                  for: selectedTemplateID,
                  currentSnapshot: snapshot(for: selectedTemplateID)
              )
        else {
            return
        }
        refreshEditAvailability()
        applyEditSnapshot(nextSnapshot, for: selectedTemplateID)
    }

    // MARK: - Import / Rename / Delete

    func importTemplateImage(_ imageData: Data, suggestedName: String?) async {
        importErrorMessage = nil
        importStatusMessage = nil

        do {
            let template = try await importMutationCoordinator.importTemplate(
                imageData: imageData,
                suggestedName: suggestedName
            )
            await reloadTemplates()
            selectTemplate(template.id)
            importStatusMessage = "Imported drawing is ready to color."
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func renameTemplate(_ templateID: String, to newTitle: String) async {
        importErrorMessage = nil
        importStatusMessage = nil

        do {
            let renamedTemplate = try await importMutationCoordinator.renameTemplate(
                templateID: templateID,
                newTitle: newTitle
            )
            renameLocalTemplateState(from: templateID, to: renamedTemplate.id)

            await reloadTemplates()
            selectTemplate(renamedTemplate.id)
            importStatusMessage = "Drawing renamed."
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func deleteTemplate(_ templateID: String) async {
        importErrorMessage = nil
        importStatusMessage = nil

        do {
            try await importMutationCoordinator.deleteTemplate(templateID: templateID)
            removeLocalTemplateState(for: templateID)

            await reloadTemplates()
            invalidateExport()
            persistFavoriteTemplateIDs()
            persistCompletedTemplateIDs()
            persistRecentTemplateIDs()
            importStatusMessage = "Drawing deleted."
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func deleteAllImportedTemplates() async {
        importErrorMessage = nil
        importStatusMessage = nil

        do {
            let importedTemplateIDs = templates
                .filter(\.isImported)
                .map(\.id)
            try await importMutationCoordinator.deleteAllImportedTemplates(templateIDs: importedTemplateIDs)
            for templateID in importedTemplateIDs {
                removeLocalTemplateState(for: templateID)
            }

            await reloadTemplates()
            invalidateExport()
            persistFavoriteTemplateIDs()
            persistCompletedTemplateIDs()
            persistRecentTemplateIDs()
            importStatusMessage = "All imported drawings deleted."
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func reportImportFailure(_ message: String) {
        importErrorMessage = message
        importStatusMessage = nil
    }

    // MARK: - Export

    func exportCurrentTemplate() async {
        let startResult = exportCoordinator.beginExport(selectedTemplate: selectedTemplate)
        applyExportState(exportCoordinator.state)
        guard case let .started(selectedTemplate) = startResult else {
            return
        }

        do {
            let templateData = try await templateLibrary.imageData(for: selectedTemplate)

            let canvasSize = bestExportSize(for: selectedTemplateImage)
            let exportTraitCollection = UITraitCollection(userInterfaceStyle: .light)
            let normalizedExportDrawing = currentDrawing.stableColorDrawing(using: exportTraitCollection)
            let fillData = currentFillImage?.stableDisplayImage().pngData()

            // Sync the active layer before export.
            syncActiveLayerDrawingToStack()
            let normalizedExportLayerStack = TemplateColorNormalization.normalizedLayerStack(
                currentLayerStack,
                using: exportTraitCollection
            )
            let allLayersImageData: Data?
            if normalizedExportLayerStack.layers.count > 1 {
                allLayersImageData = layerCompositor.compositeAllVisibleLayers(
                    layers: normalizedExportLayerStack.layers,
                    canvasSize: canvasSize
                )?.pngData()
            } else {
                allLayersImageData = nil
            }
            let drawingData = normalizedExportDrawing.dataRepresentation()

            let request = TemplateExportRequest(
                templateData: templateData,
                drawingData: drawingData,
                fillLayerData: fillData,
                compositedLayersImageData: allLayersImageData,
                canvasSize: canvasSize,
                templateID: selectedTemplate.id,
                templateName: selectedTemplate.title
            )
            let exportedURL = try await exportCoordinator.performExport(using: request)
            exportCoordinator.completeExportSuccess(exportedURL: exportedURL)
            applyExportState(exportCoordinator.state)
        } catch {
            exportCoordinator.completeExportFailure(error)
            applyExportState(exportCoordinator.state)
        }
    }

    // MARK: - Private: Image Loading

    private func prepareSelectedTemplateForDisplay(_ templateID: String) async {
        guard selectedTemplateID == templateID else {
            return
        }

        let hasCachedDrawing = restoreCachedDrawingForSelectedTemplate()
        let hasCachedFill = restoreCachedFillForSelectedTemplate()
        if !hasCachedDrawing || !hasCachedFill {
            selectedTemplateImage = nil
            loadedTemplateImageID = nil
        }

        if !hasCachedDrawing {
            await loadPersistedDrawing(for: templateID)
        }

        guard !Task.isCancelled, selectedTemplateID == templateID else {
            return
        }

        if !hasCachedFill {
            cancelPendingFillRestoreWork()
            let operationID = fillRestoreOperationID
            await loadPersistedFill(for: templateID, operationID: operationID)
        }

        guard !Task.isCancelled, selectedTemplateID == templateID else {
            return
        }

        await loadSelectedTemplateImage(for: templateID)
    }

    private func loadSelectedTemplateImage(for templateID: String) async {
        guard let template = templates.first(where: { $0.id == templateID }) else {
            if selectedTemplateID == templateID {
                clearRestoredArtworkPreview()
                selectedTemplateImage = nil
                loadedTemplateImageID = nil
            }
            return
        }

        if loadedTemplateImageID == templateID, selectedTemplateImage != nil {
            return
        }

        let loadResult = await TemplateSelectedImageLoader.loadImage(
            for: template,
            using: templateLibrary
        )
        guard !Task.isCancelled else {
            return
        }

        guard selectedTemplateID == templateID else {
            return
        }

        switch loadResult {
        case let .success(image):
            guard let image else {
                clearRestoredArtworkPreview()
                selectedTemplateImage = nil
                loadedTemplateImageID = nil
                return
            }

            showRestoredArtworkPreviewIfNeeded(for: templateID, templateImage: image)
            selectedTemplateImage = image
            loadedTemplateImageID = templateID
        case let .failure(message):
            clearRestoredArtworkPreview()
            selectedTemplateImage = nil
            loadedTemplateImageID = nil
            importErrorMessage = message
        }
    }

    // MARK: - Private: Drawing Persistence

    private func restoreInProgressTemplateIDs(for templateIDs: [String]) async {
        var restoredTemplateIDs = Set<String>()

        for templateID in templateIDs {
            if hasColoring(for: templateID) {
                restoredTemplateIDs.insert(templateID)
                persistedColoringByTemplateID[templateID] = true
                continue
            }

            if await hasColoringOnDiskIfNeeded(for: templateID) {
                restoredTemplateIDs.insert(templateID)
            }
        }

        assignIfChanged(\.inProgressTemplateIDs, to: restoredTemplateIDs)
    }

    private func refreshInProgressState(for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        if hasColoring(for: templateID) {
            if !inProgressTemplateIDs.contains(templateID) {
                inProgressTemplateIDs.insert(templateID)
            }

            if persistedColoringByTemplateID[templateID] != true {
                persistedColoringByTemplateID[templateID] = true
            }
        } else {
            if inProgressTemplateIDs.contains(templateID) {
                inProgressTemplateIDs.remove(templateID)
            }

            if persistedColoringByTemplateID[templateID] != false {
                persistedColoringByTemplateID[templateID] = false
            }

            removeProgressSnapshot(for: templateID)
            removeRecentColors(for: templateID)
        }
    }

    private func restoreProgressSnapshots(for validTemplateIDs: Set<String>) async {
        do {
            let storedSnapshots = try await progressSnapshotStore.loadSnapshots()
            let sanitizedSnapshots = storedSnapshots.filter { validTemplateIDs.contains($0.key) }
            assignIfChanged(\.progressSnapshotsByTemplateID, to: sanitizedSnapshots)

            if sanitizedSnapshots.count != storedSnapshots.count {
                persistProgressSnapshots()
            }
        } catch {
            assignIfChanged(\.progressSnapshotsByTemplateID, to: [:])
        }
    }

    private func scheduleProgressSnapshotUpdate(for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        debouncedProgressTask?.cancel()
        debouncedProgressTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.updateProgressSnapshot(for: templateID)
        }
    }

    private func updateProgressSnapshot(for templateID: String) async {
        guard hasColoring(for: templateID) else {
            removeProgressSnapshot(for: templateID)
            return
        }

        let layerStack = layerStacksByTemplateID[templateID]
        let fallbackDrawingData = drawingsByTemplateID[templateID]?.dataRepresentation()
        let fillData = fillStateStore.fillData(for: templateID)
        let canvasSize = bestExportSize(for: selectedTemplateID == templateID ? selectedTemplateImage : nil)
        let progress = await progressEstimator.estimateProgress(
            layerStack: layerStack,
            fallbackDrawingData: fallbackDrawingData,
            fillData: fillData,
            canvasSize: canvasSize
        )

        guard let progress else {
            removeProgressSnapshot(for: templateID)
            return
        }

        let snapshot = TemplateProgressSnapshot(templateID: templateID, estimatedProgress: progress)
        guard progressSnapshotsByTemplateID[templateID] != snapshot else {
            return
        }

        progressSnapshotsByTemplateID[templateID] = snapshot
        persistProgressSnapshots()
    }

    private func removeProgressSnapshot(for templateID: String) {
        guard progressSnapshotsByTemplateID.removeValue(forKey: templateID) != nil else {
            return
        }

        persistProgressSnapshots()
    }

    private func removeRecentColors(for templateID: String) {
        guard recentColorsByTemplateID.removeValue(forKey: templateID) != nil else {
            return
        }

        if selectedTemplateID == templateID {
            assignIfChanged(\.recentColors, to: [])
            activeColorToken = nil
        }
        persistRecentColors()
    }

    private func persistProgressSnapshots() {
        let snapshots = progressSnapshotsByTemplateID
        Task { [progressSnapshotStore, snapshots] in
            try? await progressSnapshotStore.saveSnapshots(snapshots)
        }
    }

    private func hasColoring(for templateID: String) -> Bool {
        TemplateColoringPersistenceInspector.hasColoring(
            layerStack: layerStacksByTemplateID[templateID],
            drawing: drawingsByTemplateID[templateID],
            fillData: fillStateStore.fillData(for: templateID)
        )
    }

    private func hasStrokeColoring(for templateID: String) -> Bool {
        TemplateColoringPersistenceInspector.hasStrokeColoring(
            layerStack: layerStacksByTemplateID[templateID],
            drawing: drawingsByTemplateID[templateID]
        )
    }

    private func hasFillColoring(for templateID: String) -> Bool {
        TemplateColoringPersistenceInspector.hasFillColoring(
            fillData: fillStateStore.fillData(for: templateID)
        )
    }

    private func hasPersistedColoring(for templateID: String) async -> Bool {
        await coloringPersistenceInspector.hasPersistedColoring(for: templateID)
    }

    private func hasColoringOnDiskIfNeeded(for templateID: String) async -> Bool {
        if let hasPersistedColoring = persistedColoringByTemplateID[templateID] {
            return hasPersistedColoring
        }

        let hasPersistedColoring = await hasPersistedColoring(for: templateID)
        persistedColoringByTemplateID[templateID] = hasPersistedColoring
        return hasPersistedColoring
    }

    private func serializedDrawingData(for drawing: PKDrawing) -> Data {
        TemplateStudioDrawingExportSupport.serializedDrawingData(for: drawing)
    }

    private func persistCurrentDrawing() {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        // Cancel any pending debounced persist and flush immediately.
        debouncedPersistTask?.cancel()
        pendingPersistTemplateIDs.remove(selectedTemplateID)

        syncActiveLayerDrawingToStack()
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        persistLayerStack(for: selectedTemplateID)
    }

    @discardableResult
    private func restoreCachedDrawingForSelectedTemplate() -> Bool {
        guard !selectedTemplateID.isEmpty else {
            setCurrentDrawingFromModel(PKDrawing())
            currentLayerStack = .singleLayer()
            belowLayerImage = nil
            aboveLayerImage = nil
            return true
        }

        if let layerStack = layerStacksByTemplateID[selectedTemplateID] {
            currentLayerStack = layerStack
            restoreActiveLayerDrawing()
            recompositeLayerOverlays()
            return true
        }

        if let drawing = drawingsByTemplateID[selectedTemplateID] {
            setCurrentDrawingFromModel(drawing)
            currentLayerStack = .singleLayer(drawingData: drawing.dataRepresentation())
            belowLayerImage = nil
            aboveLayerImage = nil
            return true
        }

        setCurrentDrawingFromModel(PKDrawing())
        currentLayerStack = .singleLayer()
        belowLayerImage = nil
        aboveLayerImage = nil
        return false
    }

    private func bestExportSize(for image: UIImage?) -> CGSize {
        TemplateStudioDrawingExportSupport.bestExportSize(for: image)
    }

    private func invalidateExport() {
        exportCoordinator.invalidate()
        applyExportState(exportCoordinator.state)
    }

    private func renameLocalTemplateState(from oldTemplateID: String, to newTemplateID: String) {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let drawing = drawingsByTemplateID.removeValue(forKey: oldTemplateID) {
            drawingsByTemplateID[newTemplateID] = drawing
        }

        if let layerStack = layerStacksByTemplateID.removeValue(forKey: oldTemplateID) {
            layerStacksByTemplateID[newTemplateID] = layerStack
        }

        fillStateStore.rename(from: oldTemplateID, to: newTemplateID)
        editHistoryStore.renameHistory(from: oldTemplateID, to: newTemplateID)

        if let hasPersistedColoring = persistedColoringByTemplateID.removeValue(forKey: oldTemplateID) {
            persistedColoringByTemplateID[newTemplateID] = hasPersistedColoring
        }
        if let progressSnapshot = progressSnapshotsByTemplateID.removeValue(forKey: oldTemplateID) {
            progressSnapshotsByTemplateID[newTemplateID] = TemplateProgressSnapshot(
                templateID: newTemplateID,
                estimatedProgress: progressSnapshot.estimatedProgress,
                updatedAt: progressSnapshot.updatedAt
            )
            persistProgressSnapshots()
        }
        if let recentColors = recentColorsByTemplateID.removeValue(forKey: oldTemplateID) {
            recentColorsByTemplateID[newTemplateID] = recentColors
            persistRecentColors()
        }
        persistenceRevisionStore.renameRevisions(from: oldTemplateID, to: newTemplateID)

        if favoriteTemplateIDs.remove(oldTemplateID) != nil {
            favoriteTemplateIDs.insert(newTemplateID)
            persistFavoriteTemplateIDs()
        }

        if completedTemplateIDs.remove(oldTemplateID) != nil {
            completedTemplateIDs.insert(newTemplateID)
            persistCompletedTemplateIDs()
        }

        if let recentIndex = recentTemplateIDs.firstIndex(of: oldTemplateID) {
            recentTemplateIDs[recentIndex] = newTemplateID
            persistRecentTemplateIDs()
        }

        if hiddenTemplateIDs.remove(oldTemplateID) != nil {
            hiddenTemplateIDs.insert(newTemplateID)
            persistHiddenTemplateIDs()
            refreshBuiltInCategoriesFromVisibleTemplates()
        }

        Task { [persistenceCoordinator] in
            await persistenceCoordinator.renameTracking(from: oldTemplateID, to: newTemplateID)
        }
    }

    private func removeLocalTemplateState(for templateID: String) {
        drawingsByTemplateID.removeValue(forKey: templateID)
        layerStacksByTemplateID.removeValue(forKey: templateID)
        fillStateStore.removeAll(for: templateID)
        persistedColoringByTemplateID.removeValue(forKey: templateID)
        removeProgressSnapshot(for: templateID)
        removeRecentColors(for: templateID)
        persistenceRevisionStore.removeRevisions(for: templateID)
        editHistoryStore.removeHistory(for: templateID)
        favoriteTemplateIDs.remove(templateID)
        completedTemplateIDs.remove(templateID)
        if hiddenTemplateIDs.remove(templateID) != nil {
            persistHiddenTemplateIDs()
        }
        recentTemplateIDs.removeAll { $0 == templateID }

        Task { [persistenceCoordinator] in
            await persistenceCoordinator.removeTracking(for: templateID)
        }
    }

    private func applyExportState(_ state: TemplateExportState) {
        assignIfChanged(\.isExporting, to: state.isExporting)
        assignIfChanged(\.exportedFileURL, to: state.exportedFileURL)
        assignIfChanged(\.exportStatusMessage, to: state.statusMessage)
        assignIfChanged(\.exportErrorMessage, to: state.errorMessage)
    }

    private func snapshot(for templateID: String) -> TemplateEditSnapshot? {
        TemplateEditSnapshotResolver.makeSnapshot(
            templateID: templateID,
            selectedTemplateID: selectedTemplateID,
            currentLayerStack: currentLayerStack,
            layerStacksByTemplateID: layerStacksByTemplateID,
            drawingsByTemplateID: drawingsByTemplateID,
            fillData: fillStateStore.fillData(for: templateID),
            serializeDrawing: serializedDrawingData(for:)
        )
    }

    private func recordEditChange(from previousSnapshot: TemplateEditSnapshot?, for templateID: String) {
        guard !templateID.isEmpty,
              let previousSnapshot,
              let currentSnapshot = snapshot(for: templateID),
              previousSnapshot != currentSnapshot
        else {
            return
        }

        if editHistoryStore.recordChange(
            from: previousSnapshot,
            for: templateID,
            currentSnapshot: currentSnapshot
        ) {
            refreshEditAvailability()
        }
    }

    private func beginPendingStrokeEditChangeIfNeeded(for templateID: String) {
        editHistoryStore.beginPendingStrokeIfNeeded(
            for: templateID,
            snapshot: snapshot(for: templateID)
        )
    }

    private func finalizePendingStrokeEditChange(for templateID: String) {
        if editHistoryStore.finalizePendingStrokeIfNeeded(
            for: templateID,
            currentSnapshot: snapshot(for: templateID)
        ) {
            refreshEditAvailability()
        }
    }

    private func refreshEditAvailability() {
        guard !selectedTemplateID.isEmpty else {
            assignIfChanged(\.canUndoEdit, to: false)
            assignIfChanged(\.canRedoEdit, to: false)
            return
        }

        assignIfChanged(\.canUndoEdit, to: editHistoryStore.canUndo(for: selectedTemplateID))
        assignIfChanged(\.canRedoEdit, to: editHistoryStore.canRedo(for: selectedTemplateID))
    }

    private func cachedFillImage(for templateID: String, matching fillData: Data) -> UIImage? {
        fillStateStore.cachedImage(for: templateID, matching: fillData)
    }

    private func storeCachedFillImage(_ image: UIImage, data: Data, for templateID: String) {
        fillStateStore.cacheImage(image, data: data, for: templateID)
    }

    private func clearCachedFillImage(for templateID: String) {
        fillStateStore.clearCachedImage(for: templateID)
    }

    private func showRestoredArtworkPreviewIfNeeded(for templateID: String, templateImage: UIImage) {
        guard selectedTemplateID == templateID,
              hasColoring(for: templateID),
              let previewImage = makeRestoredArtworkPreview(templateImage: templateImage)
        else {
            clearRestoredArtworkPreview()
            return
        }

        restoredArtworkPreviewDismissTask?.cancel()
        restoredArtworkPreviewImage = previewImage
        restoredArtworkPreviewDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.restoredArtworkPreviewHoldNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            self?.dismissRestoredArtworkPreview(for: templateID)
        }
    }

    private func makeRestoredArtworkPreview(templateImage: UIImage) -> UIImage? {
        let canvasSize = bestExportSize(for: templateImage)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let exportTraitCollection = UITraitCollection(userInterfaceStyle: .light)
        let normalizedDrawing = currentDrawing.stableColorDrawing(using: exportTraitCollection)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(canvasRect)
            templateImage.stableDisplayImage().draw(in: canvasRect)
            currentFillImage?.stableDisplayImage().draw(in: canvasRect)
            belowLayerImage?.stableDisplayImage().draw(in: canvasRect)
            let drawingImage = normalizedDrawing.image(from: canvasRect, scale: 2.0)
            drawingImage.draw(in: canvasRect)
            aboveLayerImage?.stableDisplayImage().draw(in: canvasRect)
        }
    }

    private func dismissRestoredArtworkPreview(for templateID: String) {
        guard selectedTemplateID == templateID else {
            return
        }

        restoredArtworkPreviewImage = nil
        restoredArtworkPreviewDismissTask = nil
    }

    private func clearRestoredArtworkPreview() {
        restoredArtworkPreviewDismissTask?.cancel()
        restoredArtworkPreviewDismissTask = nil
        restoredArtworkPreviewImage = nil
    }

    private func resolveFillImage(
        for templateID: String,
        fillData: Data,
        cachedImage: UIImage?
    ) -> UIImage? {
        TemplateFillImageResolver.resolveDisplayImage(
            fillData: fillData,
            cachedImage: cachedImage,
            decodeImage: { data in
                UIImage(data: data)?.stableDisplayImage()
            },
            cacheImage: { decodedImage in
                storeCachedFillImage(decodedImage, data: fillData, for: templateID)
            }
        )
    }

    private func cancelPendingFillOverlayWork() {
        fillOverlayTask?.cancel()
        fillOverlayTask = nil
        fillOverlayOperationID += 1
    }

    private func cancelPendingFillRestoreWork() {
        fillRestoreOperationID += 1
    }

    private func applyEditSnapshot(_ snapshot: TemplateEditSnapshot, for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        layerStacksByTemplateID[templateID] = snapshot.layerStack

        drawingsByTemplateID[templateID] = TemplateEditSnapshotResolver.drawing(from: snapshot.layerStack)

        if let fillData = snapshot.fillData {
            fillStateStore.setFillData(fillData, for: templateID)
            if selectedTemplateID != templateID {
                clearCachedFillImage(for: templateID)
            }
        } else {
            fillStateStore.setFillData(nil, for: templateID)
            clearCachedFillImage(for: templateID)
        }

        if selectedTemplateID == templateID {
            currentLayerStack = snapshot.layerStack
            restoreActiveLayerDrawing()
            recompositeLayerOverlays()
            if let fillData = snapshot.fillData {
                currentFillImage = resolveFillImage(
                    for: templateID,
                    fillData: fillData,
                    cachedImage: cachedFillImage(for: templateID, matching: fillData)
                )
            } else {
                currentFillImage = nil
            }
        }

        refreshInProgressState(for: templateID)
        scheduleProgressSnapshotUpdate(for: templateID)
        persistLayerStack(for: templateID)
        persistFill(for: templateID)
        invalidateExport()
    }

    private func persistLastSelectedTemplateID(_ templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        UserDefaults.standard.set(templateID, forKey: DefaultsKey.lastSelectedTemplateID)
    }

    private func persistLayerStack(for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        let layerStack = layerStacksByTemplateID[templateID] ?? currentLayerStack
        guard let data = try? JSONEncoder().encode(layerStack) else {
            return
        }

        let revision = persistenceRevisionStore.nextLayerRevision(for: templateID)
        Task { [persistenceCoordinator, templateID, data, revision] in
            await persistenceCoordinator.persistLayerStackData(data, for: templateID, revision: revision)
        }
    }

    /// Debounced version of persistLayerStack — coalesces rapid stroke updates
    /// into a single write every 2 seconds to avoid a file-write storm.
    private func debouncedPersistLayerStack(for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        pendingPersistTemplateIDs.insert(templateID)
        debouncedPersistTask?.cancel()
        debouncedPersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.flushPendingPersists()
        }
    }

    private func flushPendingPersists() {
        let templateIDs = pendingPersistTemplateIDs
        pendingPersistTemplateIDs.removeAll()
        for templateID in templateIDs {
            persistLayerStack(for: templateID)
        }
    }

    private func loadPersistedDrawing(for templateID: String) async {
        drawingRestoreErrorMessage = nil

        let persistedDrawing = await TemplatePersistedDrawingLoader.load(
            for: templateID,
            drawingStore: drawingStore
        )
        guard !Task.isCancelled else {
            return
        }

        switch persistedDrawing {
        case .none:
            return
        case .corruptedLayerStack:
            drawingRestoreErrorMessage = "Drawing data for this template appears to be corrupted. Your strokes may not have been restored."
            return
        case .corruptedLegacyDrawing:
            drawingRestoreErrorMessage = "Could not restore drawing strokes — the saved data may be corrupted."
            return
        case .drawingReadFailed:
            drawingRestoreErrorMessage = "Could not read saved drawing data. Your previous strokes may not have been restored."
            return
        case let .layerStack(layerStack):
            guard layerStacksByTemplateID[templateID] == nil else {
                return
            }

            layerStacksByTemplateID[templateID] = layerStack
            if hasStrokeColoring(for: templateID) {
                persistedColoringByTemplateID[templateID] = true
            } else {
                persistedColoringByTemplateID.removeValue(forKey: templateID)
            }
            if selectedTemplateID == templateID {
                currentLayerStack = layerStack
                restoreActiveLayerDrawing()
                recompositeLayerOverlays()
            }
            refreshInProgressState(for: templateID)
            scheduleProgressSnapshotUpdate(for: templateID)
        case let .migratedLegacyDrawing(drawing, layerStack):
            guard drawingsByTemplateID[templateID] == nil else {
                return
            }

            drawingsByTemplateID[templateID] = drawing
            layerStacksByTemplateID[templateID] = layerStack
            if hasStrokeColoring(for: templateID) {
                persistedColoringByTemplateID[templateID] = true
            } else {
                persistedColoringByTemplateID.removeValue(forKey: templateID)
            }

            if selectedTemplateID == templateID {
                setCurrentDrawingFromModel(drawing)
                currentLayerStack = layerStack
                belowLayerImage = nil
                aboveLayerImage = nil
            }

            refreshInProgressState(for: templateID)
            scheduleProgressSnapshotUpdate(for: templateID)
            persistLayerStack(for: templateID)
        }
    }

    // MARK: - Private: Fill Persistence

    private func applyFillData(_ fillData: Data?, for templateID: String, cachedImage: UIImage? = nil) {
        guard !templateID.isEmpty else {
            return
        }

        if let fillData {
            fillStateStore.setFillData(fillData, for: templateID)
            if let cachedImage {
                storeCachedFillImage(cachedImage, data: fillData, for: templateID)
            } else if selectedTemplateID != templateID {
                clearCachedFillImage(for: templateID)
            }
        } else {
            fillStateStore.setFillData(nil, for: templateID)
            clearCachedFillImage(for: templateID)
        }

        if selectedTemplateID == templateID {
            if let fillData {
                let resolvedCachedImage = cachedImage
                    ?? cachedFillImage(for: templateID, matching: fillData)
                currentFillImage = resolveFillImage(
                    for: templateID,
                    fillData: fillData,
                    cachedImage: resolvedCachedImage
                )
            } else {
                currentFillImage = nil
            }
        }

        refreshInProgressState(for: templateID)
        scheduleProgressSnapshotUpdate(for: templateID)
        persistFill(for: templateID)
        invalidateExport()
    }

    private func persistCurrentFill() {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        if fillStateStore.fillData(for: selectedTemplateID) == nil,
           let fillImage = currentFillImage,
           let fillData = fillImage.pngData()
        {
            fillStateStore.setFillData(fillData, for: selectedTemplateID)
            storeCachedFillImage(fillImage, data: fillData, for: selectedTemplateID)
        }
        persistFill(for: selectedTemplateID)
    }

    @discardableResult
    private func restoreCachedFillForSelectedTemplate() -> Bool {
        guard !selectedTemplateID.isEmpty else {
            currentFillImage = nil
            cancelPendingFillRestoreWork()
            return true
        }

        if let fillData = fillStateStore.fillData(for: selectedTemplateID) {
            cancelPendingFillRestoreWork()
            currentFillImage = resolveFillImage(
                for: selectedTemplateID,
                fillData: fillData,
                cachedImage: cachedFillImage(for: selectedTemplateID, matching: fillData)
            )
            return true
        }

        currentFillImage = nil
        return false
    }

    private func persistFill(for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        let fillData = fillStateStore.fillData(for: templateID)
        let revision = persistenceRevisionStore.nextFillRevision(for: templateID)
        Task { [persistenceCoordinator, templateID, fillData, revision] in
            await persistenceCoordinator.persistFillData(fillData, for: templateID, revision: revision)
        }
    }

    private func loadPersistedFill(for templateID: String, operationID: Int) async {
        do {
            guard fillRestoreOperationID == operationID else {
                return
            }

            guard let persistedFillData = try await drawingStore.loadFillData(for: templateID) else {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            guard fillRestoreOperationID == operationID else {
                return
            }

            guard fillStateStore.fillData(for: templateID) == nil else {
                return
            }

            if persistedFillData.isEmpty {
                fillStateStore.setFillData(nil, for: templateID)
                clearCachedFillImage(for: templateID)
                if selectedTemplateID == templateID {
                    currentFillImage = nil
                }
                refreshInProgressState(for: templateID)
                scheduleProgressSnapshotUpdate(for: templateID)
                return
            }

            let fillData = persistedFillData
            fillStateStore.setFillData(fillData, for: templateID)
            persistedColoringByTemplateID[templateID] = true
            if selectedTemplateID == templateID {
                currentFillImage = resolveFillImage(
                    for: templateID,
                    fillData: fillData,
                    cachedImage: cachedFillImage(for: templateID, matching: fillData)
                )
            }
            refreshInProgressState(for: templateID)
            scheduleProgressSnapshotUpdate(for: templateID)
        } catch {
            // Keep existing fill state if persistence read fails.
        }
    }

    // MARK: - Private: Cloud Restore

    private func scheduleDeferredCloudRestoreIfNeeded() {
        cloudRestoreTask?.cancel()
        guard !hasImportedTemplates else {
            return
        }

        cloudRestoreTask = Task { [weak self] in
            await self?.performDeferredCloudRestore()
        }
    }

    private func performDeferredCloudRestore() async {
        await TemplateDeferredCloudRestoreRunner.performDeferredCloudRestore(
            reloadTemplates: { [weak self] in
                guard let self else {
                    return false
                }
                return await self.reloadTemplates()
            },
            hasImportedTemplates: { [weak self] in
                self?.hasImportedTemplates ?? false
            }
        )
    }
}
