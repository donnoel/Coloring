import Combine
import Foundation
import PencilKit
import UIKit

@MainActor
final class TemplateStudioViewModel: ObservableObject {
    private enum DefaultsKey {
        static let lastSelectedTemplateID = "lastSelectedTemplateID"
    }

    @Published private(set) var templates: [ColoringTemplate] = []
    @Published var selectedTemplateID: String = ""
    @Published var currentDrawing: PKDrawing
    @Published private(set) var selectedTemplateImage: UIImage?
    @Published private(set) var exportStatusMessage: String?
    @Published private(set) var exportErrorMessage: String?
    @Published private(set) var importStatusMessage: String?
    @Published private(set) var importErrorMessage: String?
    @Published private(set) var exportedFileURL: URL?
    @Published private(set) var isExporting: Bool = false
    @Published private(set) var drawingRestoreErrorMessage: String?

    // Fill mode state
    @Published var isFillModeActive: Bool = false
    @Published var selectedFillColorID: String = ColoringColor.defaultColorID
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

    // Category state
    @Published var selectedCategoryFilter: String = TemplateCategory.allCategory.id
    @Published private(set) var builtInCategories: [TemplateCategory] = []
    @Published private(set) var userCategories: [TemplateCategory] = []
    @Published private(set) var categoryAssignments: [String: String] = [:]
    @Published private(set) var categoryOrder: [String] = []
    @Published private(set) var inProgressTemplateIDs: Set<String> = []

    private struct FillHistory {
        var undo: [Data?] = []
        var redo: [Data?] = []
    }

    private struct FillEraseResult {
        let didChange: Bool
        let fillData: Data?
        let fillImage: UIImage?
    }

    private var drawingsByTemplateID: [String: PKDrawing] = [:]
    private var layerStacksByTemplateID: [String: LayerStack] = [:]
    private var fillImagesByTemplateID: [String: Data] = [:]
    private var fillImageCacheByTemplateID: [String: UIImage] = [:]
    private var fillHistoryByTemplateID: [String: FillHistory] = [:]
    private let templateLibrary: any TemplateLibraryProviding
    private let exportService: any TemplateArtworkExporting
    private let drawingStore: any TemplateDrawingStoreProviding
    private let floodFillService: any FloodFillProviding
    private let layerCompositor: any LayerCompositing
    private let brushPresetStore: any BrushPresetStoreProviding
    private let categoryStore: any TemplateCategoryStoreProviding
    private let galleryStore: any GalleryStoreProviding
    private var hasLoadedTemplates = false
    private var loadedTemplateImageID: String?
    private var templateImageLoadTask: Task<Void, Never>?
    private var drawingRestoreTask: Task<Void, Never>?
    private var cloudRestoreTask: Task<Void, Never>?
    private var debouncedPersistTask: Task<Void, Never>?
    private var pendingPersistTemplateIDs: Set<String> = []
    private let maxFillHistorySteps = 100

    init(
        templateLibrary: any TemplateLibraryProviding,
        exportService: any TemplateArtworkExporting,
        drawingStore: any TemplateDrawingStoreProviding,
        floodFillService: any FloodFillProviding,
        layerCompositor: any LayerCompositing,
        brushPresetStore: any BrushPresetStoreProviding,
        categoryStore: any TemplateCategoryStoreProviding,
        galleryStore: any GalleryStoreProviding
    ) {
        self.templateLibrary = templateLibrary
        self.exportService = exportService
        self.drawingStore = drawingStore
        self.floodFillService = floodFillService
        self.layerCompositor = layerCompositor
        self.brushPresetStore = brushPresetStore
        self.categoryStore = categoryStore
        self.galleryStore = galleryStore
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
            galleryStore: GalleryStoreService()
        )
    }

    var selectedTemplate: ColoringTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }

    var hasImportedTemplates: Bool {
        templates.contains(where: \.isImported)
    }

    var selectedTemplateAspectRatio: CGFloat {
        guard let size = selectedTemplateImage?.size,
              size.width > 0,
              size.height > 0
        else {
            return 4.0 / 3.0
        }

        return size.width / size.height
    }

    var selectedFillColor: ColoringColor? {
        ColoringColor.palette.first { $0.id == selectedFillColorID }
    }

    var canUndoFill: Bool {
        guard !selectedTemplateID.isEmpty else {
            return false
        }

        return !(fillHistoryByTemplateID[selectedTemplateID]?.undo.isEmpty ?? true)
    }

    var canRedoFill: Bool {
        guard !selectedTemplateID.isEmpty else {
            return false
        }

        return !(fillHistoryByTemplateID[selectedTemplateID]?.redo.isEmpty ?? true)
    }

    // MARK: - Template Loading

    func loadTemplatesIfNeeded() async {
        guard !hasLoadedTemplates else {
            return
        }

        hasLoadedTemplates = await reloadTemplates()
        scheduleDeferredCloudRestoreIfNeeded()
        cleanUpStaleExportFiles()
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
        drawingRestoreTask?.cancel()
        drawingRestoreTask = nil

        do {
            let loadedTemplates = try await templateLibrary.loadTemplates()
            templates = loadedTemplates
            builtInCategories = TemplateCategory.builtInCategories(from: loadedTemplates)
            syncCategoryOrderWithAvailableCategories()
            let validTemplateIDs = Set(loadedTemplates.map(\.id))
            drawingsByTemplateID = drawingsByTemplateID.filter { validTemplateIDs.contains($0.key) }
            layerStacksByTemplateID = layerStacksByTemplateID.filter { validTemplateIDs.contains($0.key) }
            fillImagesByTemplateID = fillImagesByTemplateID.filter { validTemplateIDs.contains($0.key) }
            fillImageCacheByTemplateID = fillImageCacheByTemplateID.filter { validTemplateIDs.contains($0.key) }
            fillHistoryByTemplateID = fillHistoryByTemplateID.filter { validTemplateIDs.contains($0.key) }
            importErrorMessage = nil

            if selectedTemplateID.isEmpty || !validTemplateIDs.contains(selectedTemplateID) {
                let lastSelected = UserDefaults.standard.string(forKey: DefaultsKey.lastSelectedTemplateID) ?? ""
                if !lastSelected.isEmpty, validTemplateIDs.contains(lastSelected) {
                    selectedTemplateID = lastSelected
                } else {
                    selectedTemplateID = templates.first?.id ?? ""
                }
            }

            persistLastSelectedTemplateID(selectedTemplateID)

            await restoreInProgressTemplateIDs(for: loadedTemplates.map(\.id))
            restoreDrawingForSelectedTemplate()
            restoreFillForSelectedTemplate()

            if selectedTemplateID != previousTemplateID {
                // Only clear when selection changed; preserving same-template image avoids launch flicker.
                selectedTemplateImage = nil
                loadedTemplateImageID = nil
            }

            await loadSelectedTemplateImage(for: selectedTemplateID)
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

        persistCurrentDrawing()
        persistCurrentFill()
        selectedTemplateID = templateID
        persistLastSelectedTemplateID(templateID)
        // Clear immediately so the canvas never shows a mismatched image/drawing pair.
        selectedTemplateImage = nil
        loadedTemplateImageID = nil
        restoreDrawingForSelectedTemplate()
        restoreFillForSelectedTemplate()

        templateImageLoadTask?.cancel()
        templateImageLoadTask = Task { [weak self] in
            await self?.loadSelectedTemplateImage(for: templateID)
        }

        invalidateExport()
    }

    // MARK: - Drawing

    func updateDrawing(_ drawing: PKDrawing) {
        currentDrawing = drawing
        drawingsByTemplateID[selectedTemplateID] = drawing
        currentLayerStack.updateDrawingData(serializedDrawingData(for: drawing), for: currentLayerStack.activeLayerID)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        refreshInProgressState(for: selectedTemplateID)
        debouncedPersistLayerStack(for: selectedTemplateID)
        invalidateExport()
    }

    func clearDrawing() {
        currentDrawing = PKDrawing()
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
        currentLayerStack.updateDrawingData(Data(), for: currentLayerStack.activeLayerID)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        refreshInProgressState(for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        invalidateExport()
    }

    // MARK: - Layers

    func addLayer() {
        syncActiveLayerDrawingToStack()
        let newLayer = currentLayerStack.addLayer(name: "Layer \(currentLayerStack.layers.count)")
        currentDrawing = PKDrawing()
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        refreshInProgressState(for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        _ = newLayer
    }

    func deleteLayer(_ id: UUID) {
        guard currentLayerStack.layers.count > 1 else {
            return
        }

        syncActiveLayerDrawingToStack()
        let wasActive = currentLayerStack.activeLayerID == id
        currentLayerStack.removeLayer(id)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack

        if wasActive {
            restoreActiveLayerDrawing()
        }

        refreshInProgressState(for: selectedTemplateID)
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
        currentLayerStack.toggleVisibility(id)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        invalidateExport()
    }

    func renameLayer(_ id: UUID, to name: String) {
        currentLayerStack.renameLayer(id, to: name)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        persistLayerStack(for: selectedTemplateID)
    }

    func moveLayer(from source: IndexSet, to destination: Int) {
        currentLayerStack.moveLayer(from: source, to: destination)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        invalidateExport()
    }

    func mergeDown(_ id: UUID) {
        syncActiveLayerDrawingToStack()
        guard let pair = currentLayerStack.mergeDown(id) else {
            return
        }

        // Composite upper onto lower by combining their drawings.
        if let upperDrawing = try? PKDrawing(data: pair.upper.drawingData),
           let lowerDrawing = try? PKDrawing(data: pair.lower.drawingData)
        {
            var mergedStrokes = lowerDrawing.strokes
            mergedStrokes.append(contentsOf: upperDrawing.strokes)
            let mergedDrawing = PKDrawing(strokes: mergedStrokes)
            currentLayerStack.updateDrawingData(mergedDrawing.dataRepresentation(), for: pair.lower.id)
        }

        currentLayerStack.removeLayer(id)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        restoreActiveLayerDrawing()
        refreshInProgressState(for: selectedTemplateID)
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        invalidateExport()
    }

    private func syncActiveLayerDrawingToStack() {
        let drawingData = serializedDrawingData(for: currentDrawing)
        currentLayerStack.updateDrawingData(drawingData, for: currentLayerStack.activeLayerID)
    }

    private func restoreActiveLayerDrawing() {
        if let activeLayer = currentLayerStack.activeLayer,
           !activeLayer.drawingData.isEmpty,
           let drawing = try? PKDrawing(data: activeLayer.drawingData)
        {
            currentDrawing = drawing
        } else {
            currentDrawing = PKDrawing()
        }
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

    private func updateCurrentBrushTool() {
        currentBrushTool = PKInkingTool(
            activeBrushPreset.inkType.pkInkType,
            color: UIColor.black.withAlphaComponent(customBrushOpacity),
            width: customBrushWidth
        )
    }

    private func persistUserPresets() {
        let presets = userBrushPresets
        Task { [brushPresetStore, presets] in
            try? await brushPresetStore.saveUserPresets(presets)
        }
    }

    // MARK: - Template Categories

    var allCategories: [TemplateCategory] {
        [TemplateCategory.allCategory, TemplateCategory.inProgressCategory] + orderedFolderCategories + [TemplateCategory.importedCategory]
    }

    var reorderableCategories: [TemplateCategory] {
        orderedFolderCategories
    }

    var filteredTemplates: [ColoringTemplate] {
        let filterID = selectedCategoryFilter
        guard filterID != TemplateCategory.allCategory.id else {
            return templates
        }

        if filterID == TemplateCategory.inProgressCategory.id {
            return templates.filter { inProgressTemplateIDs.contains($0.id) }
        }

        if filterID == TemplateCategory.importedCategory.id {
            return templates.filter { $0.source == .imported && categoryAssignments[$0.id] == nil }
        }

        // Check user category assignments first
        let assignedToCategory = templates.filter { categoryAssignments[$0.id] == filterID }
        if !assignedToCategory.isEmpty {
            return assignedToCategory
        }

        // Built-in category: match by category name
        if let builtInCat = builtInCategories.first(where: { $0.id == filterID }) {
            return templates.filter { template in
                TemplateCategory
                    .builtInCategoryNames(for: template)
                    .contains(builtInCat.name)
            }
        }

        return templates
    }

    func createUserCategory(name: String) {
        let category = TemplateCategory(
            id: "user-\(UUID().uuidString)",
            name: name,
            isUserCreated: true
        )
        userCategories.append(category)
        syncCategoryOrderWithAvailableCategories()
        persistUserCategories()
        persistCategoryOrder()
    }

    func renameUserCategory(_ id: String, to name: String) {
        guard let index = userCategories.firstIndex(where: { $0.id == id }) else {
            return
        }
        userCategories[index].name = name
        persistUserCategories()
    }

    func deleteUserCategory(_ id: String) {
        userCategories.removeAll { $0.id == id }
        categoryOrder.removeAll { $0 == id }
        // Unassign templates from the deleted category
        for (templateID, catID) in categoryAssignments where catID == id {
            categoryAssignments.removeValue(forKey: templateID)
        }
        if selectedCategoryFilter == id {
            selectedCategoryFilter = TemplateCategory.allCategory.id
        }
        syncCategoryOrderWithAvailableCategories()
        persistUserCategories()
        persistCategoryAssignments()
        persistCategoryOrder()
    }

    func assignTemplate(_ templateID: String, toCategoryID categoryID: String?) {
        if let categoryID {
            categoryAssignments[templateID] = categoryID
        } else {
            categoryAssignments.removeValue(forKey: templateID)
        }
        persistCategoryAssignments()
    }

    func moveCategories(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else {
            return
        }

        var updatedCategories = orderedFolderCategories
        let sourceIndexes = source.sorted()
        let movedCategories = sourceIndexes.map { updatedCategories[$0] }

        for index in sourceIndexes.sorted(by: >) {
            updatedCategories.remove(at: index)
        }

        let removalsBeforeDestination = sourceIndexes.filter { $0 < destination }.count
        let adjustedDestination = max(0, min(updatedCategories.count, destination - removalsBeforeDestination))
        updatedCategories.insert(contentsOf: movedCategories, at: adjustedDestination)

        categoryOrder = updatedCategories.map(\.id)
        persistCategoryOrder()
    }

    func loadCategoriesIfNeeded() {
        Task { [categoryStore] in
            do {
                let categories = try await categoryStore.loadUserCategories()
                self.userCategories = categories
                let assignments = try await categoryStore.loadCategoryAssignments()
                self.categoryAssignments = assignments
                let storedOrder = try await categoryStore.loadCategoryOrder()
                self.categoryOrder = storedOrder
                self.syncCategoryOrderWithAvailableCategories()
            } catch {
                // Silently ignore - starts with empty user categories
                self.syncCategoryOrderWithAvailableCategories()
            }
        }
        builtInCategories = TemplateCategory.builtInCategories(from: templates)
        syncCategoryOrderWithAvailableCategories()
    }

    private func persistUserCategories() {
        let categories = userCategories
        Task { [categoryStore, categories] in
            try? await categoryStore.saveUserCategories(categories)
        }
    }

    private func persistCategoryAssignments() {
        let assignments = categoryAssignments
        Task { [categoryStore, assignments] in
            try? await categoryStore.saveCategoryAssignments(assignments)
        }
    }

    private func persistCategoryOrder() {
        let categoryOrder = categoryOrder
        Task { [categoryStore, categoryOrder] in
            try? await categoryStore.saveCategoryOrder(categoryOrder)
        }
    }

    private var orderedFolderCategories: [TemplateCategory] {
        let availableCategories = builtInCategories + userCategories
        guard !availableCategories.isEmpty else {
            return []
        }

        let categoriesByID = Dictionary(uniqueKeysWithValues: availableCategories.map { ($0.id, $0) })
        var ordered: [TemplateCategory] = []
        var seenCategoryIDs = Set<String>()

        for categoryID in categoryOrder {
            guard let category = categoriesByID[categoryID] else {
                continue
            }

            ordered.append(category)
            seenCategoryIDs.insert(categoryID)
        }

        for category in availableCategories where !seenCategoryIDs.contains(category.id) {
            ordered.append(category)
        }

        return ordered
    }

    private func syncCategoryOrderWithAvailableCategories() {
        let availableCategoryIDs = Set((builtInCategories + userCategories).map(\.id))
        categoryOrder = categoryOrder.filter { availableCategoryIDs.contains($0) }

        for category in builtInCategories + userCategories where !categoryOrder.contains(category.id) {
            categoryOrder.append(category.id)
        }
    }

    // MARK: - Fill Mode

    func toggleFillMode() {
        isFillModeActive.toggle()
    }

    func selectFillColor(_ colorID: String) {
        selectedFillColorID = colorID
    }

    func handleFillTap(at normalizedPoint: CGPoint) {
        guard isFillModeActive,
              let templateImage = selectedTemplateImage,
              let fillColor = selectedFillColor
        else {
            return
        }

        let fillCanvasSize = normalizedFillCanvasSize(for: templateImage)
        let renderedTemplate = renderTemplateForFill(templateImage, canvasSize: fillCanvasSize)
        guard let templateCGImage = renderedTemplate.cgImage else {
            return
        }

        let clampedPoint = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )
        let imagePoint = CGPoint(
            x: clampedPoint.x * CGFloat(max(templateCGImage.width - 1, 0)),
            y: clampedPoint.y * CGFloat(max(templateCGImage.height - 1, 0))
        )

        // Build the base image: template + existing fill composited.
        guard let baseImage = compositeBaseImageForFill(templateImage: renderedTemplate) else {
            return
        }

        guard let filledImage = floodFillService.floodFill(
            image: baseImage,
            at: imagePoint,
            with: fillColor.uiColor,
            tolerance: 40
        ) else {
            return
        }

        // The flood fill operated on the composited base (template + existing fills).
        // Extract just the fill overlay by diffing against the original template.
        let fillOverlay = extractFillOverlay(
            filledComposite: filledImage,
            templateCGImage: templateCGImage,
            existingFillImage: currentFillImage
        )

        let currentFillData = fillImagesByTemplateID[selectedTemplateID]
        guard let nextFillData = fillOverlay.pngData(), nextFillData != currentFillData else {
            return
        }

        recordFillStateChange(previousFillData: currentFillData, for: selectedTemplateID)
        applyFillData(nextFillData, for: selectedTemplateID, cachedImage: fillOverlay)
    }

    func handleFillErase(at normalizedPoint: CGPoint) {
        guard !selectedTemplateID.isEmpty,
              let currentFillImage
        else {
            return
        }

        let eraseResult = eraseFillOverlayRegion(in: currentFillImage, at: normalizedPoint)
        guard eraseResult.didChange else {
            return
        }

        let currentFillData = fillImagesByTemplateID[selectedTemplateID] ?? currentFillImage.pngData()
        recordFillStateChange(previousFillData: currentFillData, for: selectedTemplateID)
        applyFillData(eraseResult.fillData, for: selectedTemplateID, cachedImage: eraseResult.fillImage)
    }

    func clearFills() {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        let currentFillData = fillImagesByTemplateID[selectedTemplateID]
        guard currentFillData != nil else {
            return
        }

        recordFillStateChange(previousFillData: currentFillData, for: selectedTemplateID)
        applyFillData(nil, for: selectedTemplateID)
    }

    func undoFillStep() {
        guard !selectedTemplateID.isEmpty,
              var history = fillHistoryByTemplateID[selectedTemplateID],
              let previousFillData = history.undo.popLast()
        else {
            return
        }

        history.redo.append(fillImagesByTemplateID[selectedTemplateID])
        fillHistoryByTemplateID[selectedTemplateID] = history
        applyFillData(previousFillData, for: selectedTemplateID)
    }

    func redoFillStep() {
        guard !selectedTemplateID.isEmpty,
              var history = fillHistoryByTemplateID[selectedTemplateID],
              let nextFillData = history.redo.popLast()
        else {
            return
        }

        history.undo.append(fillImagesByTemplateID[selectedTemplateID])
        fillHistoryByTemplateID[selectedTemplateID] = history
        applyFillData(nextFillData, for: selectedTemplateID)
    }

    // MARK: - Import / Rename / Delete

    func importTemplateImage(_ imageData: Data, suggestedName: String?) async {
        importErrorMessage = nil
        importStatusMessage = nil

        do {
            let template = try await templateLibrary.importTemplate(imageData: imageData, preferredName: suggestedName)
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
            let renamedTemplate = try await templateLibrary.renameImportedTemplate(id: templateID, newTitle: newTitle)
            try await drawingStore.renameDrawingData(from: templateID, to: renamedTemplate.id)
            try await drawingStore.renameFillData(from: templateID, to: renamedTemplate.id)
            try await drawingStore.renameLayerStackData(from: templateID, to: renamedTemplate.id)

            if let drawing = drawingsByTemplateID.removeValue(forKey: templateID) {
                drawingsByTemplateID[renamedTemplate.id] = drawing
            }

            if let layerStack = layerStacksByTemplateID.removeValue(forKey: templateID) {
                layerStacksByTemplateID[renamedTemplate.id] = layerStack
            }

            if let fillData = fillImagesByTemplateID.removeValue(forKey: templateID) {
                fillImagesByTemplateID[renamedTemplate.id] = fillData
            }

            if let fillImage = fillImageCacheByTemplateID.removeValue(forKey: templateID) {
                fillImageCacheByTemplateID[renamedTemplate.id] = fillImage
            }

            if let fillHistory = fillHistoryByTemplateID.removeValue(forKey: templateID) {
                fillHistoryByTemplateID[renamedTemplate.id] = fillHistory
            }

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
            try await templateLibrary.deleteImportedTemplate(id: templateID)
            try await drawingStore.deleteDrawingData(for: templateID)
            try await drawingStore.deleteFillData(for: templateID)
            try await drawingStore.deleteLayerStackData(for: templateID)
            drawingsByTemplateID.removeValue(forKey: templateID)
            layerStacksByTemplateID.removeValue(forKey: templateID)
            fillImagesByTemplateID.removeValue(forKey: templateID)
            fillImageCacheByTemplateID.removeValue(forKey: templateID)
            fillHistoryByTemplateID.removeValue(forKey: templateID)

            await reloadTemplates()
            invalidateExport()
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
            try await templateLibrary.deleteAllImportedTemplates()
            for templateID in importedTemplateIDs {
                try await drawingStore.deleteDrawingData(for: templateID)
                try await drawingStore.deleteFillData(for: templateID)
                try await drawingStore.deleteLayerStackData(for: templateID)
                drawingsByTemplateID.removeValue(forKey: templateID)
                layerStacksByTemplateID.removeValue(forKey: templateID)
                fillImagesByTemplateID.removeValue(forKey: templateID)
                fillImageCacheByTemplateID.removeValue(forKey: templateID)
                fillHistoryByTemplateID.removeValue(forKey: templateID)
            }

            await reloadTemplates()
            invalidateExport()
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
        guard !isExporting else {
            return
        }

        guard let selectedTemplate else {
            exportErrorMessage = "No template selected to export."
            return
        }

        isExporting = true
        exportErrorMessage = nil
        defer {
            isExporting = false
        }

        do {
            let templateData = try await templateLibrary.imageData(for: selectedTemplate)

            let canvasSize = bestExportSize(for: selectedTemplateImage)
            let fillData = currentFillImage?.pngData()

            // Sync the active layer before export.
            syncActiveLayerDrawingToStack()
            let allLayersImageData: Data?
            if currentLayerStack.layers.count > 1 {
                allLayersImageData = layerCompositor.compositeAllVisibleLayers(
                    layers: currentLayerStack.layers,
                    canvasSize: canvasSize
                )?.pngData()
            } else {
                allLayersImageData = nil
            }
            let drawingData = currentDrawing.dataRepresentation()

            let exportedURL = try await exportService.exportPNG(
                templateData: templateData,
                drawingData: drawingData,
                fillLayerData: fillData,
                compositedLayersImageData: allLayersImageData,
                canvasSize: canvasSize,
                templateID: selectedTemplate.id
            )

            exportedFileURL = exportedURL
            exportStatusMessage = "Template export is ready to share."

            // Also save to gallery.
            // Read the exported PNG data and hand it to the gallery store.
            do {
                let exportImageData = try Data(contentsOf: exportedURL)
                _ = try await galleryStore.saveArtwork(
                    imageData: exportImageData,
                    sourceTemplateID: selectedTemplate.id,
                    sourceTemplateName: selectedTemplate.title
                )
            } catch {
                // Gallery save is best-effort; don't fail the export.
            }
        } catch {
            exportErrorMessage = error.localizedDescription
            exportStatusMessage = nil
            exportedFileURL = nil
        }
    }

    // MARK: - Private: Export Cleanup

    /// Remove old template export PNGs from the temp directory to avoid accumulating stale files.
    private func cleanUpStaleExportFiles() {
        Task.detached(priority: .utility) {
            let tempDir = FileManager.default.temporaryDirectory
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            ) else {
                return
            }

            let exportPrefix = "template-"
            let pngSuffix = ".png"
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                guard filename.hasPrefix(exportPrefix),
                      filename.hasSuffix(pngSuffix)
                else {
                    continue
                }

                let values = try? fileURL.resourceValues(forKeys: [.creationDateKey])
                if let createdAt = values?.creationDate, createdAt < cutoff {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }

    // MARK: - Private: Image Loading

    private func loadSelectedTemplateImage(for templateID: String) async {
        guard let template = templates.first(where: { $0.id == templateID }) else {
            if selectedTemplateID == templateID {
                selectedTemplateImage = nil
                loadedTemplateImageID = nil
            }
            return
        }

        if loadedTemplateImageID == templateID, selectedTemplateImage != nil {
            return
        }

        do {
            let templateData = try await templateLibrary.imageData(for: template)
            guard !Task.isCancelled else {
                return
            }

            guard selectedTemplateID == templateID else {
                return
            }

            selectedTemplateImage = UIImage(data: templateData)
            loadedTemplateImageID = templateID
        } catch {
            guard !Task.isCancelled else {
                return
            }

            guard selectedTemplateID == templateID else {
                return
            }

            selectedTemplateImage = nil
            loadedTemplateImageID = nil
            importErrorMessage = "Could not load selected template image."
        }
    }

    // MARK: - Private: Drawing Persistence

    private func restoreInProgressTemplateIDs(for templateIDs: [String]) async {
        var restoredTemplateIDs = Set<String>()

        for templateID in templateIDs {
            if hasColoring(for: templateID) {
                restoredTemplateIDs.insert(templateID)
                continue
            }

            if await hasPersistedColoring(for: templateID) {
                restoredTemplateIDs.insert(templateID)
            }
        }

        inProgressTemplateIDs = restoredTemplateIDs
    }

    private func refreshInProgressState(for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        if hasColoring(for: templateID) {
            inProgressTemplateIDs.insert(templateID)
        } else {
            inProgressTemplateIDs.remove(templateID)
        }
    }

    private func hasColoring(for templateID: String) -> Bool {
        hasStrokeColoring(for: templateID) || hasFillColoring(for: templateID)
    }

    private func hasStrokeColoring(for templateID: String) -> Bool {
        if let layerStack = layerStacksByTemplateID[templateID] {
            return layerStack.layers.contains { drawingDataContainsVisibleStrokes($0.drawingData) }
        }

        if let drawing = drawingsByTemplateID[templateID] {
            return !drawing.strokes.isEmpty
        }

        return false
    }

    private func hasFillColoring(for templateID: String) -> Bool {
        guard let fillData = fillImagesByTemplateID[templateID] else {
            return false
        }

        return !fillData.isEmpty
    }

    private func hasPersistedColoring(for templateID: String) async -> Bool {
        do {
            if let layerStackData = try await drawingStore.loadLayerStackData(for: templateID),
               let layerStack = try? JSONDecoder().decode(LayerStack.self, from: layerStackData),
               layerStack.layers.contains(where: { drawingDataContainsVisibleStrokes($0.drawingData) })
            {
                return true
            }

            if let drawingData = try await drawingStore.loadDrawingData(for: templateID),
               drawingDataContainsVisibleStrokes(drawingData)
            {
                return true
            }

            if let fillData = try await drawingStore.loadFillData(for: templateID) {
                return !fillData.isEmpty
            }
        } catch {
            return false
        }

        return false
    }

    private func serializedDrawingData(for drawing: PKDrawing) -> Data {
        guard !drawing.strokes.isEmpty else {
            return Data()
        }

        return drawing.dataRepresentation()
    }

    private func drawingDataContainsVisibleStrokes(_ drawingData: Data) -> Bool {
        guard !drawingData.isEmpty else {
            return false
        }

        guard let drawing = try? PKDrawing(data: drawingData) else {
            return true
        }

        return !drawing.strokes.isEmpty
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

    private func restoreDrawingForSelectedTemplate() {
        guard !selectedTemplateID.isEmpty else {
            currentDrawing = PKDrawing()
            currentLayerStack = .singleLayer()
            belowLayerImage = nil
            aboveLayerImage = nil
            drawingRestoreTask?.cancel()
            drawingRestoreTask = nil
            return
        }

        if let layerStack = layerStacksByTemplateID[selectedTemplateID] {
            currentLayerStack = layerStack
            restoreActiveLayerDrawing()
            recompositeLayerOverlays()
            return
        }

        if let drawing = drawingsByTemplateID[selectedTemplateID] {
            currentDrawing = drawing
            currentLayerStack = .singleLayer(drawingData: drawing.dataRepresentation())
            belowLayerImage = nil
            aboveLayerImage = nil
            return
        }

        currentDrawing = PKDrawing()
        currentLayerStack = .singleLayer()
        belowLayerImage = nil
        aboveLayerImage = nil
        drawingRestoreTask?.cancel()
        let templateID = selectedTemplateID
        drawingRestoreTask = Task { [weak self] in
            await self?.loadPersistedDrawing(for: templateID)
        }
    }

    private func bestExportSize(for image: UIImage?) -> CGSize {
        guard let image else {
            return CGSize(width: 2048, height: 1536)
        }

        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: 2048, height: 1536)
        }

        let longEdge = max(size.width, size.height)
        guard longEdge > 2048 else {
            return size
        }

        let scale = 2048 / longEdge
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func invalidateExport() {
        exportedFileURL = nil
        exportStatusMessage = nil
        exportErrorMessage = nil
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
        Task { [drawingStore, templateID, layerStack] in
            if let data = try? JSONEncoder().encode(layerStack) {
                try? await drawingStore.saveLayerStackData(data, for: templateID)
            }
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

        // Try layer stack first.
        do {
            if let layerStackData = try await drawingStore.loadLayerStackData(for: templateID) {
                guard let layerStack = try? JSONDecoder().decode(LayerStack.self, from: layerStackData) else {
                    drawingRestoreErrorMessage = "Drawing data for this template appears to be corrupted. Your strokes may not have been restored."
                    return
                }

                guard !Task.isCancelled else { return }
                guard layerStacksByTemplateID[templateID] == nil else { return }

                layerStacksByTemplateID[templateID] = layerStack
                if selectedTemplateID == templateID {
                    currentLayerStack = layerStack
                    restoreActiveLayerDrawing()
                    recompositeLayerOverlays()
                }
                refreshInProgressState(for: templateID)
                return
            }
        } catch {
            // Fall through to legacy loading.
        }

        // Fall back to legacy single-drawing persistence.
        do {
            guard let drawingData = try await drawingStore.loadDrawingData(for: templateID) else {
                return
            }
            guard !Task.isCancelled else {
                return
            }

            let drawing: PKDrawing
            do {
                drawing = try PKDrawing(data: drawingData)
            } catch {
                drawingRestoreErrorMessage = "Could not restore drawing strokes — the saved data may be corrupted."
                return
            }

            guard !Task.isCancelled else {
                return
            }

            guard drawingsByTemplateID[templateID] == nil else {
                return
            }

            // Migrate to layer stack.
            let layerStack = LayerStack.singleLayer(drawingData: drawingData)
            drawingsByTemplateID[templateID] = drawing
            layerStacksByTemplateID[templateID] = layerStack

            if selectedTemplateID == templateID {
                currentDrawing = drawing
                currentLayerStack = layerStack
                belowLayerImage = nil
                aboveLayerImage = nil
            }

            refreshInProgressState(for: templateID)

            // Persist the migrated layer stack.
            persistLayerStack(for: templateID)
        } catch {
            drawingRestoreErrorMessage = "Could not read saved drawing data. Your previous strokes may not have been restored."
        }
    }

    // MARK: - Private: Fill Persistence

    private func recordFillStateChange(previousFillData: Data?, for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        var history = fillHistoryByTemplateID[templateID] ?? FillHistory()
        history.undo.append(previousFillData)
        if history.undo.count > maxFillHistorySteps {
            history.undo.removeFirst(history.undo.count - maxFillHistorySteps)
        }
        history.redo.removeAll(keepingCapacity: true)
        fillHistoryByTemplateID[templateID] = history
    }

    private func applyFillData(_ fillData: Data?, for templateID: String, cachedImage: UIImage? = nil) {
        guard !templateID.isEmpty else {
            return
        }

        if let fillData {
            fillImagesByTemplateID[templateID] = fillData
            if let cachedImage {
                fillImageCacheByTemplateID[templateID] = cachedImage
            } else if selectedTemplateID != templateID {
                fillImageCacheByTemplateID.removeValue(forKey: templateID)
            }
        } else {
            fillImagesByTemplateID.removeValue(forKey: templateID)
            fillImageCacheByTemplateID.removeValue(forKey: templateID)
        }

        if selectedTemplateID == templateID {
            if let fillData {
                currentFillImage = cachedImage
                    ?? fillImageCacheByTemplateID[templateID]
                    ?? {
                        let decodedImage = UIImage(data: fillData)
                        if let decodedImage {
                            fillImageCacheByTemplateID[templateID] = decodedImage
                        }
                        return decodedImage
                    }()
            } else {
                currentFillImage = nil
            }
        }

        refreshInProgressState(for: templateID)
        persistFill(for: templateID)
        invalidateExport()
    }

    private func persistCurrentFill() {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        if fillImagesByTemplateID[selectedTemplateID] == nil,
           let fillImage = currentFillImage,
           let fillData = fillImage.pngData()
        {
            fillImagesByTemplateID[selectedTemplateID] = fillData
            fillImageCacheByTemplateID[selectedTemplateID] = fillImage
        }
        persistFill(for: selectedTemplateID)
    }

    private func restoreFillForSelectedTemplate() {
        guard !selectedTemplateID.isEmpty else {
            currentFillImage = nil
            return
        }

        if let fillData = fillImagesByTemplateID[selectedTemplateID] {
            currentFillImage = fillImageCacheByTemplateID[selectedTemplateID]
                ?? {
                    let decodedImage = UIImage(data: fillData)
                    if let decodedImage {
                        fillImageCacheByTemplateID[selectedTemplateID] = decodedImage
                    }
                    return decodedImage
                }()
            return
        }

        currentFillImage = nil
        let templateID = selectedTemplateID
        Task { [weak self] in
            await self?.loadPersistedFill(for: templateID)
        }
    }

    private func persistFill(for templateID: String) {
        guard !templateID.isEmpty else {
            return
        }

        let fillData = fillImagesByTemplateID[templateID]
        Task { [drawingStore, templateID, fillData] in
            if let fillData {
                try? await drawingStore.saveFillData(fillData, for: templateID)
            } else {
                try? await drawingStore.deleteFillData(for: templateID)
            }
        }
    }

    private func loadPersistedFill(for templateID: String) async {
        do {
            guard let fillData = try await drawingStore.loadFillData(for: templateID) else {
                return
            }
            guard !Task.isCancelled else {
                return
            }

            guard fillImagesByTemplateID[templateID] == nil else {
                return
            }

            fillImagesByTemplateID[templateID] = fillData
            if selectedTemplateID == templateID {
                currentFillImage = fillImageCacheByTemplateID[templateID]
                    ?? {
                        let decodedImage = UIImage(data: fillData)
                        if let decodedImage {
                            fillImageCacheByTemplateID[templateID] = decodedImage
                        }
                        return decodedImage
                    }()
            }
            refreshInProgressState(for: templateID)
        } catch {
            // Keep existing fill state if persistence read fails.
        }
    }

    // MARK: - Private: Fill Compositing

    private func normalizedFillCanvasSize(for image: UIImage) -> CGSize {
        let bestSize = bestExportSize(for: image)
        return CGSize(
            width: max(1, bestSize.width.rounded(.toNearestOrAwayFromZero)),
            height: max(1, bestSize.height.rounded(.toNearestOrAwayFromZero))
        )
    }

    private func renderTemplateForFill(_ templateImage: UIImage, canvasSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            templateImage.draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }

    private func compositeBaseImageForFill(templateImage: UIImage) -> CGImage? {
        let size = templateImage.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let composited = renderer.image { _ in
            templateImage.draw(in: CGRect(origin: .zero, size: size))
            if let existingFill = currentFillImage {
                existingFill.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return composited.cgImage ?? templateImage.cgImage
    }

    private func extractFillOverlay(
        filledComposite: CGImage,
        templateCGImage: CGImage,
        existingFillImage: UIImage?
    ) -> UIImage {
        let width = templateCGImage.width
        let height = templateCGImage.height
        let size = CGSize(width: width, height: height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return UIImage(cgImage: filledComposite)
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        // Render the template into a buffer.
        guard let templateContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let templateData = templateContext.data else {
            return UIImage(cgImage: filledComposite)
        }
        templateContext.draw(templateCGImage, in: CGRect(origin: .zero, size: size))
        let templatePixels = templateData.bindMemory(to: UInt8.self, capacity: totalBytes)

        // Render the filled composite into a buffer.
        guard let filledContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let filledData = filledContext.data else {
            return UIImage(cgImage: filledComposite)
        }
        filledContext.draw(filledComposite, in: CGRect(origin: .zero, size: size))
        let filledPixels = filledData.bindMemory(to: UInt8.self, capacity: totalBytes)

        // Build the overlay: where the filled differs from template, use the filled pixel.
        // Start with existing fill overlay if present.
        guard let overlayContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let overlayData = overlayContext.data else {
            return UIImage(cgImage: filledComposite)
        }

        if let existingFill = existingFillImage?.cgImage {
            overlayContext.draw(existingFill, in: CGRect(origin: .zero, size: size))
        }

        let overlayPixels = overlayData.bindMemory(to: UInt8.self, capacity: totalBytes)

        for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
            let templateR = templatePixels[i]
            let templateG = templatePixels[i + 1]
            let templateB = templatePixels[i + 2]
            let filledR = filledPixels[i]
            let filledG = filledPixels[i + 1]
            let filledB = filledPixels[i + 2]

            let differs = abs(Int(templateR) - Int(filledR)) > 2
                || abs(Int(templateG) - Int(filledG)) > 2
                || abs(Int(templateB) - Int(filledB)) > 2

            if differs {
                overlayPixels[i] = filledR
                overlayPixels[i + 1] = filledG
                overlayPixels[i + 2] = filledB
                overlayPixels[i + 3] = filledPixels[i + 3]
            }
        }

        guard let overlayCGImage = overlayContext.makeImage() else {
            return UIImage(cgImage: filledComposite)
        }
        return UIImage(cgImage: overlayCGImage)
    }

    private func eraseFillOverlayRegion(in fillImage: UIImage, at normalizedPoint: CGPoint) -> FillEraseResult {
        guard let fillCGImage = fillImage.cgImage else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let width = fillCGImage.width
        let height = fillCGImage.height
        guard width > 0, height > 0 else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let clampedPoint = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )
        let pixelX = min(max(Int(clampedPoint.x * CGFloat(max(width - 1, 0))), 0), width - 1)
        let pixelY = min(max(Int(clampedPoint.y * CGFloat(max(height - 1, 0))), 0), height - 1)

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        context.draw(fillCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: totalBytes)
        let targetIndex = (pixelY * bytesPerRow) + (pixelX * bytesPerPixel)
        let targetAlpha = pixels[targetIndex + 3]
        guard targetAlpha > 0 else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let targetRed = pixels[targetIndex]
        let targetGreen = pixels[targetIndex + 1]
        let targetBlue = pixels[targetIndex + 2]
        let tolerance = 12

        var stack: [(Int, Int)] = [(pixelX, pixelY)]
        var visited = [Bool](repeating: false, count: width * height)
        var didErase = false

        while let (seedX, seedY) = stack.popLast() {
            let visitIndex = seedY * width + seedX
            guard !visited[visitIndex] else {
                continue
            }

            let seedPixelIndex = (seedY * bytesPerRow) + (seedX * bytesPerPixel)
            guard fillOverlayPixelMatchesTarget(
                pixels: pixels,
                pixelIndex: seedPixelIndex,
                targetRed: targetRed,
                targetGreen: targetGreen,
                targetBlue: targetBlue,
                tolerance: tolerance
            ) else {
                continue
            }

            var leftX = seedX
            while leftX > 0 {
                let checkIndex = (seedY * bytesPerRow) + ((leftX - 1) * bytesPerPixel)
                guard fillOverlayPixelMatchesTarget(
                    pixels: pixels,
                    pixelIndex: checkIndex,
                    targetRed: targetRed,
                    targetGreen: targetGreen,
                    targetBlue: targetBlue,
                    tolerance: tolerance
                ) else {
                    break
                }
                leftX -= 1
            }

            var x = leftX
            var aboveAdded = false
            var belowAdded = false

            while x < width {
                let pixelIndex = (seedY * bytesPerRow) + (x * bytesPerPixel)
                guard fillOverlayPixelMatchesTarget(
                    pixels: pixels,
                    pixelIndex: pixelIndex,
                    targetRed: targetRed,
                    targetGreen: targetGreen,
                    targetBlue: targetBlue,
                    tolerance: tolerance
                ) else {
                    break
                }

                pixels[pixelIndex] = 0
                pixels[pixelIndex + 1] = 0
                pixels[pixelIndex + 2] = 0
                pixels[pixelIndex + 3] = 0
                visited[seedY * width + x] = true
                didErase = true

                if seedY > 0 {
                    let aboveVisitIndex = (seedY - 1) * width + x
                    if !visited[aboveVisitIndex] {
                        let aboveIndex = ((seedY - 1) * bytesPerRow) + (x * bytesPerPixel)
                        let aboveMatches = fillOverlayPixelMatchesTarget(
                            pixels: pixels,
                            pixelIndex: aboveIndex,
                            targetRed: targetRed,
                            targetGreen: targetGreen,
                            targetBlue: targetBlue,
                            tolerance: tolerance
                        )
                        if aboveMatches, !aboveAdded {
                            stack.append((x, seedY - 1))
                            aboveAdded = true
                        } else if !aboveMatches {
                            aboveAdded = false
                        }
                    }
                }

                if seedY < height - 1 {
                    let belowVisitIndex = (seedY + 1) * width + x
                    if !visited[belowVisitIndex] {
                        let belowIndex = ((seedY + 1) * bytesPerRow) + (x * bytesPerPixel)
                        let belowMatches = fillOverlayPixelMatchesTarget(
                            pixels: pixels,
                            pixelIndex: belowIndex,
                            targetRed: targetRed,
                            targetGreen: targetGreen,
                            targetBlue: targetBlue,
                            tolerance: tolerance
                        )
                        if belowMatches, !belowAdded {
                            stack.append((x, seedY + 1))
                            belowAdded = true
                        } else if !belowMatches {
                            belowAdded = false
                        }
                    }
                }

                x += 1
            }
        }

        guard didErase else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let hasVisiblePixels = stride(from: 0, to: totalBytes, by: bytesPerPixel)
            .contains { pixels[$0 + 3] > 0 }
        guard hasVisiblePixels else {
            return FillEraseResult(didChange: true, fillData: nil, fillImage: nil)
        }

        guard let erasedCGImage = context.makeImage() else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let erasedImage = UIImage(cgImage: erasedCGImage)
        guard let fillData = erasedImage.pngData()
        else {
            return FillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        return FillEraseResult(didChange: true, fillData: fillData, fillImage: erasedImage)
    }

    private func fillOverlayPixelMatchesTarget(
        pixels: UnsafeMutablePointer<UInt8>,
        pixelIndex: Int,
        targetRed: UInt8,
        targetGreen: UInt8,
        targetBlue: UInt8,
        tolerance: Int
    ) -> Bool {
        let alpha = pixels[pixelIndex + 3]
        guard alpha > 0 else {
            return false
        }

        return abs(Int(pixels[pixelIndex]) - Int(targetRed)) <= tolerance
            && abs(Int(pixels[pixelIndex + 1]) - Int(targetGreen)) <= tolerance
            && abs(Int(pixels[pixelIndex + 2]) - Int(targetBlue)) <= tolerance
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
        let retryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
        for delay in retryDelays {
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled {
                return
            }

            let didReload = await reloadTemplates()
            if !didReload || hasImportedTemplates {
                return
            }
        }
    }
}
