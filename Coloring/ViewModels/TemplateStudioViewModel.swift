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

    private var drawingsByTemplateID: [String: PKDrawing] = [:]
    private var layerStacksByTemplateID: [String: LayerStack] = [:]
    private var fillImagesByTemplateID: [String: Data] = [:]
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
            let validTemplateIDs = Set(loadedTemplates.map(\.id))
            drawingsByTemplateID = drawingsByTemplateID.filter { validTemplateIDs.contains($0.key) }
            layerStacksByTemplateID = layerStacksByTemplateID.filter { validTemplateIDs.contains($0.key) }
            fillImagesByTemplateID = fillImagesByTemplateID.filter { validTemplateIDs.contains($0.key) }
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
        currentLayerStack.updateDrawingData(drawing.dataRepresentation(), for: currentLayerStack.activeLayerID)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
        debouncedPersistLayerStack(for: selectedTemplateID)
        invalidateExport()
    }

    func clearDrawing() {
        currentDrawing = PKDrawing()
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
        currentLayerStack.updateDrawingData(Data(), for: currentLayerStack.activeLayerID)
        layerStacksByTemplateID[selectedTemplateID] = currentLayerStack
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
        persistLayerStack(for: selectedTemplateID)
        recompositeLayerOverlays()
        invalidateExport()
    }

    private func syncActiveLayerDrawingToStack() {
        let drawingData = currentDrawing.dataRepresentation()
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
        [TemplateCategory.allCategory] + builtInCategories + [TemplateCategory.importedCategory] + userCategories
    }

    var filteredTemplates: [ColoringTemplate] {
        let filterID = selectedCategoryFilter
        guard filterID != TemplateCategory.allCategory.id else {
            return templates
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
            return templates.filter { $0.category == builtInCat.name && $0.source == .builtIn }
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
        persistUserCategories()
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
        // Unassign templates from the deleted category
        for (templateID, catID) in categoryAssignments where catID == id {
            categoryAssignments.removeValue(forKey: templateID)
        }
        if selectedCategoryFilter == id {
            selectedCategoryFilter = TemplateCategory.allCategory.id
        }
        persistUserCategories()
        persistCategoryAssignments()
    }

    func assignTemplate(_ templateID: String, toCategoryID categoryID: String?) {
        if let categoryID {
            categoryAssignments[templateID] = categoryID
        } else {
            categoryAssignments.removeValue(forKey: templateID)
        }
        persistCategoryAssignments()
    }

    func loadCategoriesIfNeeded() {
        Task { [categoryStore] in
            do {
                let categories = try await categoryStore.loadUserCategories()
                self.userCategories = categories
                let assignments = try await categoryStore.loadCategoryAssignments()
                self.categoryAssignments = assignments
            } catch {
                // Silently ignore - starts with empty user categories
            }
        }
        builtInCategories = TemplateCategory.builtInCategories(from: templates)
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

        currentFillImage = fillOverlay
        fillImagesByTemplateID[selectedTemplateID] = fillOverlay.pngData()
        persistFill(for: selectedTemplateID)
        invalidateExport()
    }

    func clearFills() {
        currentFillImage = nil
        fillImagesByTemplateID.removeValue(forKey: selectedTemplateID)
        persistFill(for: selectedTemplateID)
        invalidateExport()
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

            // Persist the migrated layer stack.
            persistLayerStack(for: templateID)
        } catch {
            drawingRestoreErrorMessage = "Could not read saved drawing data. Your previous strokes may not have been restored."
        }
    }

    // MARK: - Private: Fill Persistence

    private func persistCurrentFill() {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        if let fillImage = currentFillImage {
            fillImagesByTemplateID[selectedTemplateID] = fillImage.pngData()
        }
        persistFill(for: selectedTemplateID)
    }

    private func restoreFillForSelectedTemplate() {
        guard !selectedTemplateID.isEmpty else {
            currentFillImage = nil
            return
        }

        if let fillData = fillImagesByTemplateID[selectedTemplateID] {
            currentFillImage = UIImage(data: fillData)
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
                currentFillImage = UIImage(data: fillData)
            }
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
