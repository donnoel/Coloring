import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest

@testable import Coloring

final class ColoringTests: XCTestCase {
    func testApplyColorStoresSelectionForRegion() async {
        await MainActor.run {
            let viewModel = makeViewModel(scenes: [makeScene(id: "scene-1", regionIDs: ["sky", "sun"])])

            viewModel.selectColor("ocean")
            viewModel.applyColor(to: "sky")

            XCTAssertEqual(viewModel.colorForRegion("sky")?.id, "ocean")
        }
    }

    func testSwitchingScenesKeepsIndependentColorMaps() async {
        await MainActor.run {
            let sceneOne = makeScene(id: "scene-1", regionIDs: ["sky"])
            let sceneTwo = makeScene(id: "scene-2", regionIDs: ["track"])
            let viewModel = makeViewModel(scenes: [sceneOne, sceneTwo])

            viewModel.selectColor("sunset-red")
            viewModel.applyColor(to: "sky")

            viewModel.selectScene("scene-2")
            viewModel.selectColor("teal")
            viewModel.applyColor(to: "track")

            XCTAssertEqual(viewModel.colorForRegion("track")?.id, "teal")

            viewModel.selectScene("scene-1")
            XCTAssertEqual(viewModel.colorForRegion("sky")?.id, "sunset-red")
        }
    }

    func testClearCurrentSceneRemovesAppliedColors() async {
        await MainActor.run {
            let viewModel = makeViewModel(scenes: [makeScene(id: "scene-1", regionIDs: ["ocean"])])

            viewModel.selectColor("violet")
            viewModel.applyColor(to: "ocean")
            XCTAssertTrue(viewModel.canClearCurrentScene)

            viewModel.clearCurrentScene()

            XCTAssertNil(viewModel.colorForRegion("ocean"))
            XCTAssertFalse(viewModel.canClearCurrentScene)
        }
    }

    func testExportSetsShareURL() async {
        let expectedURL = URL(fileURLWithPath: "/tmp/preview.png")
        let exportService = StubExportService(resultURL: expectedURL)
        let viewModel = await MainActor.run {
            makeViewModel(
                scenes: [makeScene(id: "scene-1", regionIDs: ["field"])],
                exportService: exportService
            )
        }

        await viewModel.exportCurrentScene(canvasSize: CGSize(width: 640, height: 480))

        await MainActor.run {
            XCTAssertEqual(viewModel.exportedFileURL, expectedURL)
            XCTAssertEqual(viewModel.exportStatusMessage, "Export is ready to share.")
        }

        let exportedSceneIDs = await MainActor.run {
            exportService.exportedSceneIDs
        }
        XCTAssertEqual(exportedSceneIDs, ["scene-1"])
    }

    func testTemplateLoadSelectsFirstTemplate() async {
        let library = StubTemplateLibrary(templates: [
            Self.makeTemplate(id: "builtin-1", title: "Template One"),
            Self.makeTemplate(id: "builtin-2", title: "Template Two")
        ])
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            XCTAssertEqual(viewModel.selectedTemplateID, "builtin-1")
            XCTAssertEqual(viewModel.selectedTemplate?.title, "Template One")
            XCTAssertNotNil(viewModel.selectedTemplateImage)
        }
    }

    func testTemplateImportAddsAndSelectsImportedTemplate() async {
        let initialTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let library = StubTemplateLibrary(templates: [initialTemplate])
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        await viewModel.importTemplateImage(sampleTemplateImageData, suggestedName: "Rocket City")

        await MainActor.run {
            XCTAssertEqual(viewModel.selectedTemplate?.source, .imported)
            XCTAssertEqual(viewModel.importStatusMessage, "Imported drawing is ready to color.")
            XCTAssertTrue(viewModel.templates.contains(where: { $0.source == .imported }))
        }
    }

    func testTemplateSelectionSwitchesDisplayedImageForSameSizedTemplates() async {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let firstImageData = await MainActor.run { solidColorTemplateImageData(.red) }
        let secondImageData = await MainActor.run { solidColorTemplateImageData(.blue) }
        let firstImageSignature = await MainActor.run { imageSignature(from: firstImageData) }
        let secondImageSignature = await MainActor.run { imageSignature(from: secondImageData) }
        let library = StubTemplateLibrary(
            templates: [firstTemplate, secondTemplate],
            imageDataSequence: [firstImageData, secondImageData]
        )
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            XCTAssertEqual(viewModel.selectedTemplateID, firstTemplate.id)
            XCTAssertEqual(imageSignature(from: viewModel.selectedTemplateImage), firstImageSignature)
            viewModel.selectTemplate(secondTemplate.id)
        }

        let imageDidUpdate = await waitForCondition(timeout: 5.0) {
            await MainActor.run {
                viewModel.selectedTemplateID == secondTemplate.id
                    && self.imageSignature(from: viewModel.selectedTemplateImage) == secondImageSignature
            }
        }
        XCTAssertTrue(imageDidUpdate)
    }

    func testTitleBasedBuiltInCategoriesAppearFromTemplateTitles() async {
        let templates = [
            Self.makeTemplate(id: "builtin-cats", title: "Cats"),
            Self.makeTemplate(id: "builtin-bridge", title: "Brooklyn Bridge"),
            Self.makeTemplate(id: "builtin-ocean", title: "Ocean"),
            Self.makeTemplate(id: "builtin-wheelie", title: "Wheelie"),
            Self.makeTemplate(id: "builtin-mother", title: "Loving Mother")
        ]
        let library = StubTemplateLibrary(templates: templates)
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            let categoryNames = Set(viewModel.builtInCategories.map(\.name))
            XCTAssertTrue(categoryNames.contains("Cities & Landmarks"))
            XCTAssertTrue(categoryNames.contains("Nature & Outdoors"))
            XCTAssertTrue(categoryNames.contains("People & Portraits"))
            XCTAssertTrue(categoryNames.contains("Animals & Wildlife"))
            XCTAssertTrue(categoryNames.contains("Action & Motion"))
        }
    }

    func testTitleBasedBuiltInCategoriesAllowMultipleFolderMembership() async {
        let neon = Self.makeTemplate(id: "builtin-neon", title: "Neon City Racing")
        let bridge = Self.makeTemplate(id: "builtin-bridge", title: "Brooklyn Bridge")
        let wheelie = Self.makeTemplate(id: "builtin-wheelie", title: "Wheelie")
        let library = StubTemplateLibrary(templates: [neon, bridge, wheelie])
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            guard let cityCategoryID = viewModel.allCategories.first(where: { $0.name == "Cities & Landmarks" })?.id else {
                XCTFail("Expected Cities & Landmarks category.")
                return
            }
            guard let actionCategoryID = viewModel.allCategories.first(where: { $0.name == "Action & Motion" })?.id else {
                XCTFail("Expected Action & Motion category.")
                return
            }

            viewModel.selectedCategoryFilter = cityCategoryID
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([neon.id, bridge.id]))

            viewModel.selectedCategoryFilter = actionCategoryID
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([neon.id, wheelie.id]))
        }
    }

    func testMoveCategoriesReordersFolderChips() async {
        let templates = [
            Self.makeTemplate(id: "builtin-bridge", title: "Brooklyn Bridge"),
            Self.makeTemplate(id: "builtin-cats", title: "Cats"),
            Self.makeTemplate(id: "builtin-wheelie", title: "Wheelie")
        ]
        let library = StubTemplateLibrary(templates: templates)
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            let folderNames = viewModel.reorderableCategories.map(\.name)
            guard let sourceIndex = folderNames.firstIndex(of: "Action & Motion") else {
                XCTFail("Expected Action & Motion folder.")
                return
            }

            viewModel.moveCategories(from: IndexSet(integer: sourceIndex), to: 0)

            XCTAssertEqual(viewModel.reorderableCategories.first?.name, "Action & Motion")
            XCTAssertEqual(viewModel.allCategories[1].name, "Action & Motion")
        }
    }

    func testTemplateRenameKeepsTemplateSelected() async {
        let importedTemplate = Self.makeTemplate(
            id: "imported-1",
            title: "Old Name",
            source: .imported
        )
        let library = StubTemplateLibrary(templates: [importedTemplate], importedCount: 1)
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        await viewModel.renameTemplate("imported-1", to: "Racing Storm")

        await MainActor.run {
            XCTAssertEqual(viewModel.selectedTemplate?.title, "Racing Storm")
            XCTAssertEqual(viewModel.selectedTemplate?.source, .imported)
            XCTAssertEqual(viewModel.importStatusMessage, "Drawing renamed.")
        }
    }

    func testTemplateDeleteRemovesImportedDrawing() async {
        let builtInTemplate = Self.makeTemplate(id: "builtin-1", title: "Built In")
        let importedTemplate = Self.makeTemplate(
            id: "imported-1",
            title: "Imported One",
            source: .imported
        )
        let library = StubTemplateLibrary(
            templates: [builtInTemplate, importedTemplate],
            importedCount: 1
        )
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        await viewModel.deleteTemplate("imported-1")

        await MainActor.run {
            XCTAssertFalse(viewModel.templates.contains(where: { $0.id == "imported-1" }))
            XCTAssertEqual(viewModel.importStatusMessage, "Drawing deleted.")
            XCTAssertEqual(viewModel.selectedTemplate?.id, "builtin-1")
        }
    }

    func testDeleteAllImportedTemplatesKeepsBuiltInTemplates() async {
        let builtInTemplate = Self.makeTemplate(id: "builtin-1", title: "Built In")
        let importedTemplateOne = Self.makeTemplate(
            id: "imported-1",
            title: "Imported One",
            source: .imported
        )
        let importedTemplateTwo = Self.makeTemplate(
            id: "imported-2",
            title: "Imported Two",
            source: .imported
        )
        let library = StubTemplateLibrary(
            templates: [builtInTemplate, importedTemplateOne, importedTemplateTwo],
            importedCount: 2
        )
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        await viewModel.deleteAllImportedTemplates()

        await MainActor.run {
            XCTAssertEqual(viewModel.templates.map(\.id), [builtInTemplate.id])
            XCTAssertEqual(viewModel.importStatusMessage, "All imported drawings deleted.")
            XCTAssertFalse(viewModel.hasImportedTemplates)
        }
    }

    func testTemplateDrawingPersistsAcrossViewModelReload() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let drawingStore = StubTemplateDrawingStore()
        let firstLibrary = StubTemplateLibrary(templates: [template])
        let firstViewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: firstLibrary,
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await firstViewModel.loadTemplatesIfNeeded()
        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }
        let sampleStrokeCount = sampleDrawing.strokes.count
        await MainActor.run {
            firstViewModel.updateDrawing(sampleDrawing)
        }

        let didPersistDrawing = await waitForCondition(timeout: 3.0) {
            let persistedLayerData = try? await drawingStore.loadLayerStackData(for: template.id)
            return persistedLayerData?.isEmpty == false
        }
        XCTAssertTrue(didPersistDrawing, "Expected layer stack data to be persisted for selected template.")

        let secondLibrary = StubTemplateLibrary(templates: [template])
        let secondViewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: secondLibrary,
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await secondViewModel.loadTemplatesIfNeeded()

        let didRestoreDrawing = await waitForCondition(timeout: 5.0) {
            await MainActor.run {
                secondViewModel.selectedTemplateID == template.id &&
                secondViewModel.currentDrawing.strokes.count == sampleStrokeCount
            }
        }
        XCTAssertTrue(didRestoreDrawing, "Expected persisted drawing strokes to restore after reload.")
    }

    func testTemplateDrawingStorePersistsDrawingDataLocally() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let store = makeRealTemplateDrawingStore(documentsURL: documentsURL)
        let templateID = "builtin-drawing"
        let drawingData = Data("drawing-data".utf8)

        try await store.saveDrawingData(drawingData, for: templateID)

        let loadedData = try await store.loadDrawingData(for: templateID)

        XCTAssertEqual(loadedData, drawingData)

        let fileURL = documentsURL
            .appendingPathComponent("TemplateDrawings", isDirectory: true)
            .appendingPathComponent("builtin-drawing.drawing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testTemplateDrawingStoreRenamesAndDeletesFillDataLocally() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let store = makeRealTemplateDrawingStore(documentsURL: documentsURL)
        let originalTemplateID = "imported-old"
        let renamedTemplateID = "imported-new"
        let fillData = Data("fill-data".utf8)

        try await store.saveFillData(fillData, for: originalTemplateID)
        try await store.renameFillData(from: originalTemplateID, to: renamedTemplateID)

        let renamedData = try await store.loadFillData(for: renamedTemplateID)
        let oldData = try await store.loadFillData(for: originalTemplateID)

        XCTAssertEqual(renamedData, fillData)
        XCTAssertNil(oldData)

        try await store.deleteFillData(for: renamedTemplateID)

        let deletedData = try await store.loadFillData(for: renamedTemplateID)
        XCTAssertNil(deletedData)
    }

    func testTemplateDrawingStorePersistsAndRenamesLayerStackDataLocally() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let store = makeRealTemplateDrawingStore(documentsURL: documentsURL)
        let originalTemplateID = "layer-template"
        let renamedTemplateID = "layer-template-renamed"
        let layerData = Data("layer-stack-data".utf8)

        try await store.saveLayerStackData(layerData, for: originalTemplateID)
        try await store.renameLayerStackData(from: originalTemplateID, to: renamedTemplateID)

        let renamedData = try await store.loadLayerStackData(for: renamedTemplateID)
        let originalData = try await store.loadLayerStackData(for: originalTemplateID)

        XCTAssertEqual(renamedData, layerData)
        XCTAssertNil(originalData)
    }

    func testTemplateExportUsesTemplateSizedCanvas() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let templateImageData = await MainActor.run {
            solidColorTemplateImageData(.black, size: CGSize(width: 1536, height: 1024))
        }
        let library = StubTemplateLibrary(
            templates: [template],
            imageDataSequence: [templateImageData, templateImageData]
        )
        let exportService = CapturingTemplateExportService()
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: exportService,
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        let selectedTemplateSize = await MainActor.run {
            viewModel.selectedTemplateImage?.size
        }
        await viewModel.exportCurrentTemplate()

        let exportedCanvasSize = await exportService.lastCanvasSize
        let expectedCanvasSize = normalizedCanvasSize(for: selectedTemplateSize)
        XCTAssertNotNil(selectedTemplateSize)
        XCTAssertNotNil(exportedCanvasSize)
        XCTAssertNotNil(expectedCanvasSize)
        XCTAssertEqual(
            exportedCanvasSize?.width ?? 0,
            expectedCanvasSize?.width ?? 0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            exportedCanvasSize?.height ?? 0,
            expectedCanvasSize?.height ?? 0,
            accuracy: 0.01
        )
    }

    func testFillUndoRedoStepsApplyOneAtATime() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let templateImageData = await MainActor.run {
            solidColorTemplateImageData(.white, size: CGSize(width: 8, height: 8))
        }
        let firstFilledImage = await MainActor.run {
            solidColorTemplateImage(.red, size: CGSize(width: 8, height: 8))
        }
        let secondFilledImage = await MainActor.run {
            solidColorTemplateImage(.blue, size: CGSize(width: 8, height: 8))
        }

        let library = StubTemplateLibrary(
            templates: [template],
            imageDataSequence: [templateImageData]
        )
        let floodFillService = StubFloodFillService(images: [firstFilledImage, secondFilledImage])
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: floodFillService,
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            viewModel.isFillModeActive = true
            XCTAssertFalse(viewModel.canUndoFill)
            XCTAssertFalse(viewModel.canRedoFill)

            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
            let firstSignature = imageSignature(from: viewModel.currentFillImage)
            XCTAssertNotNil(firstSignature)
            XCTAssertTrue(viewModel.canUndoFill)
            XCTAssertFalse(viewModel.canRedoFill)

            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
            let secondSignature = imageSignature(from: viewModel.currentFillImage)
            XCTAssertNotNil(secondSignature)
            XCTAssertNotEqual(firstSignature, secondSignature)
            XCTAssertTrue(viewModel.canUndoFill)
            XCTAssertFalse(viewModel.canRedoFill)

            viewModel.undoFillStep()
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), firstSignature)
            XCTAssertTrue(viewModel.canUndoFill)
            XCTAssertTrue(viewModel.canRedoFill)

            viewModel.undoFillStep()
            XCTAssertNil(viewModel.currentFillImage)
            XCTAssertFalse(viewModel.canUndoFill)
            XCTAssertTrue(viewModel.canRedoFill)

            viewModel.redoFillStep()
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), firstSignature)
            XCTAssertTrue(viewModel.canUndoFill)
            XCTAssertTrue(viewModel.canRedoFill)

            viewModel.redoFillStep()
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), secondSignature)
            XCTAssertTrue(viewModel.canUndoFill)
            XCTAssertFalse(viewModel.canRedoFill)
        }
    }

    func testPencilCanvasCoordinatorPreventsStaleDrawingReapplyDuringLocalSync() async {
        await MainActor.run {
            let drawingState = DrawingStateBox()
            let initialDrawing = PKDrawing()
            let localDrawing = makeSampleTemplateDrawing()

            drawingState.drawing = initialDrawing

            let view = PencilCanvasView(
                templateImage: solidColorTemplateImage(.white),
                templateID: "builtin-1",
                drawing: Binding(
                    get: { drawingState.drawing },
                    set: { drawingState.drawing = $0 }
                )
            )

            let coordinator = view.makeCoordinator()
            let canvasView = PKCanvasView()
            canvasView.drawing = localDrawing

            coordinator.canvasViewDrawingDidChange(canvasView)

            XCTAssertEqual(drawingState.drawing, localDrawing)
            XCTAssertFalse(
                coordinator.shouldApplyExternalDrawing(
                    initialDrawing,
                    currentCanvasDrawing: canvasView.drawing
                )
            )

            coordinator.resetLocalDrawingSyncTracking()

            XCTAssertTrue(
                coordinator.shouldApplyExternalDrawing(
                    initialDrawing,
                    currentCanvasDrawing: canvasView.drawing
                )
            )
        }
    }

    @MainActor
    private func makeViewModel(
        scenes: [ColoringScene],
        exportService: any ArtworkExporting = NoOpExportService()
    ) -> ColoringBookViewModel {
        ColoringBookViewModel(
            sceneCatalog: StubSceneCatalog(scenes: scenes),
            exportService: exportService,
            palette: ColoringColor.palette
        )
    }

    private func makeScene(id: String, regionIDs: [String]) -> ColoringScene {
        let regions = regionIDs.map { regionID in
            SceneRegion(
                id: regionID,
                name: regionID,
                shape: .polygon([
                    UnitPoint2D(x: 0.1, y: 0.1),
                    UnitPoint2D(x: 0.9, y: 0.1),
                    UnitPoint2D(x: 0.9, y: 0.9),
                    UnitPoint2D(x: 0.1, y: 0.9)
                ])
            )
        }

        return ColoringScene(
            id: id,
            title: id,
            subtitle: "Test Scene",
            canvasAspectRatio: 4.0 / 3.0,
            regions: regions,
            detailStrokes: []
        )
    }

    private static func makeTemplate(id: String, title: String, source: ColoringTemplate.Source = .builtIn) -> ColoringTemplate {
        ColoringTemplate(
            id: id,
            title: title,
            category: source == .builtIn ? "Scenery" : "Imported",
            source: source,
            filePath: "/tmp/\(id).png"
        )
    }

    @MainActor
    private func solidColorTemplateImageData(
        _ color: UIColor,
        size imageSize: CGSize = CGSize(width: 2, height: 2)
    ) -> Data {
        solidColorTemplateImage(color, size: imageSize).pngData() ?? sampleTemplateImageData
    }

    @MainActor
    private func solidColorTemplateImage(
        _ color: UIColor,
        size imageSize: CGSize = CGSize(width: 2, height: 2)
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
    }

    @MainActor
    private func makeSampleTemplateDrawing() -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 10, y: 10),
                timeOffset: 0,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 160, y: 120),
                timeOffset: 0.1,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path)
        return PKDrawing(strokes: [stroke])
    }

    @MainActor
    private func imageSignature(from imageData: Data) -> [UInt8]? {
        guard let image = UIImage(data: imageData) else {
            return nil
        }
        return imageSignature(from: image)
    }

    @MainActor
    private func imageSignature(from image: UIImage?) -> [UInt8]? {
        guard let image,
              let cgImage = image.cgImage
        else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let bytesPerRow = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        let drewPixel: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: 1,
                      height: 1,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  )
            else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }

        return drewPixel ? pixel : nil
    }

    private func waitForCondition(
        timeout: TimeInterval = 3.0,
        pollingIntervalNanoseconds: UInt64 = 25_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
        }

        return await condition()
    }

    private func normalizedCanvasSize(
        for size: CGSize?,
        maxLongEdge: CGFloat = 2048
    ) -> CGSize? {
        guard let size,
              size.width > 0,
              size.height > 0
        else {
            return nil
        }

        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else {
            return size
        }

        let scale = maxLongEdge / longEdge
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func makeTemporaryDocumentsDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL
    }

    private func makeRealTemplateDrawingStore(documentsURL: URL) -> TemplateDrawingStoreService {
        TemplateDrawingStoreService(
            cloudContainerIdentifier: nil,
            documentsDirectoryURLProvider: { documentsURL },
            ubiquityContainerURLProvider: { _ in nil }
        )
    }
}

@MainActor
private final class DrawingStateBox {
    var drawing = PKDrawing()
}

private struct StubSceneCatalog: SceneCatalogProviding {
    let scenes: [ColoringScene]

    func loadScenes() -> [ColoringScene] {
        scenes
    }
}

private struct NoOpExportService: ArtworkExporting {
    func exportPNG(scene _: ColoringScene, regionColors _: [String: ColoringColor], canvasSize _: CGSize) async throws -> URL {
        URL(fileURLWithPath: "/tmp/noop.png")
    }
}

@MainActor
private final class StubExportService: ArtworkExporting {
    private(set) var exportedSceneIDs: [String] = []
    private let resultURL: URL

    init(resultURL: URL) {
        self.resultURL = resultURL
    }

    func exportPNG(scene: ColoringScene, regionColors _: [String: ColoringColor], canvasSize _: CGSize) async throws -> URL {
        exportedSceneIDs.append(scene.id)
        return resultURL
    }
}

private actor StubTemplateLibrary: TemplateLibraryProviding {
    private var builtInTemplates: [ColoringTemplate]
    private var importedTemplates: [ColoringTemplate]
    private var imageDataSequence: [Data]
    private var imageDataIndex = 0
    private let fallbackTemplateImageData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/w8AAgMBgGd9mKsAAAAASUVORK5CYII="
    )!

    init(templates: [ColoringTemplate], imageDataSequence: [Data] = [], importedCount: Int = 0) {
        let clampedImportedCount = max(0, min(importedCount, templates.count))
        let builtInCount = templates.count - clampedImportedCount
        self.builtInTemplates = Array(templates.prefix(builtInCount))
        self.importedTemplates = Array(templates.suffix(clampedImportedCount))
        self.imageDataSequence = imageDataSequence
    }

    func loadTemplates() throws -> [ColoringTemplate] {
        builtInTemplates + importedTemplates
    }

    func imageData(for _: ColoringTemplate) throws -> Data {
        guard imageDataIndex < imageDataSequence.count else {
            return fallbackTemplateImageData
        }

        let data = imageDataSequence[imageDataIndex]
        imageDataIndex += 1
        return data
    }

    func importTemplate(imageData _: Data, preferredName: String?) throws -> ColoringTemplate {
        let filenameTitle = preferredName ?? "Imported Drawing"
        let imported = ColoringTemplate(
            id: "imported-\(importedTemplates.count + 1)",
            title: filenameTitle,
            category: "Imported",
            source: .imported,
            filePath: "/tmp/imported-\(importedTemplates.count + 1).png"
        )
        importedTemplates.append(imported)
        return imported
    }

    func renameImportedTemplate(id: String, newTitle: String) throws -> ColoringTemplate {
        guard !importedTemplates.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let index = importedTemplates.count - 1
        let renamed = ColoringTemplate(
            id: id,
            title: newTitle,
            category: "Imported",
            source: .imported,
            filePath: "/tmp/\(id)-renamed.png"
        )
        importedTemplates[index] = renamed
        return renamed
    }

    func deleteImportedTemplate(id _: String) throws {
        guard !importedTemplates.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        importedTemplates.removeLast()
    }

    func deleteAllImportedTemplates() throws {
        importedTemplates.removeAll()
    }
}

private actor StubTemplateDrawingStore: TemplateDrawingStoreProviding {
    private var drawingDataByTemplateID: [String: Data] = [:]
    private var fillDataByTemplateID: [String: Data] = [:]
    private var layerStackDataByTemplateID: [String: Data] = [:]

    func loadDrawingData(for templateID: String) throws -> Data? {
        drawingDataByTemplateID[templateID]
    }

    func saveDrawingData(_ drawingData: Data, for templateID: String) throws {
        drawingDataByTemplateID[templateID] = drawingData
    }

    func renameDrawingData(from oldTemplateID: String, to newTemplateID: String) throws {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let drawingData = drawingDataByTemplateID.removeValue(forKey: oldTemplateID) {
            drawingDataByTemplateID[newTemplateID] = drawingData
        }
    }

    func deleteDrawingData(for templateID: String) throws {
        drawingDataByTemplateID.removeValue(forKey: templateID)
    }

    func loadFillData(for templateID: String) throws -> Data? {
        fillDataByTemplateID[templateID]
    }

    func saveFillData(_ fillData: Data, for templateID: String) throws {
        fillDataByTemplateID[templateID] = fillData
    }

    func renameFillData(from oldTemplateID: String, to newTemplateID: String) throws {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let fillData = fillDataByTemplateID.removeValue(forKey: oldTemplateID) {
            fillDataByTemplateID[newTemplateID] = fillData
        }
    }

    func deleteFillData(for templateID: String) throws {
        fillDataByTemplateID.removeValue(forKey: templateID)
    }

    func loadLayerStackData(for templateID: String) throws -> Data? {
        layerStackDataByTemplateID[templateID]
    }

    func saveLayerStackData(_ data: Data, for templateID: String) throws {
        layerStackDataByTemplateID[templateID] = data
    }

    func renameLayerStackData(from oldTemplateID: String, to newTemplateID: String) throws {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let data = layerStackDataByTemplateID.removeValue(forKey: oldTemplateID) {
            layerStackDataByTemplateID[newTemplateID] = data
        }
    }

    func deleteLayerStackData(for templateID: String) throws {
        layerStackDataByTemplateID.removeValue(forKey: templateID)
    }

    func drawingData(for templateID: String) -> Data? {
        drawingDataByTemplateID[templateID]
    }
}

private let sampleTemplateImageData = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/w8AAgMBgGd9mKsAAAAASUVORK5CYII="
)!

private struct StubTemplateExportService: TemplateArtworkExporting {
    func exportPNG(
        templateData _: Data,
        drawingData _: Data,
        fillLayerData _: Data?,
        compositedLayersImageData _: Data?,
        canvasSize _: CGSize,
        templateID _: String
    ) async throws -> URL {
        URL(fileURLWithPath: "/tmp/template-export.png")
    }
}

private actor CapturingTemplateExportService: TemplateArtworkExporting {
    private(set) var lastCanvasSize: CGSize?

    func exportPNG(
        templateData _: Data,
        drawingData _: Data,
        fillLayerData _: Data?,
        compositedLayersImageData _: Data?,
        canvasSize: CGSize,
        templateID _: String
    ) async throws -> URL {
        lastCanvasSize = canvasSize
        return URL(fileURLWithPath: "/tmp/template-export-capture.png")
    }
}

private actor StubBrushPresetStore: BrushPresetStoreProviding {
    private var presets: [BrushPreset] = []

    func loadUserPresets() throws -> [BrushPreset] {
        presets
    }

    func saveUserPresets(_ presets: [BrushPreset]) throws {
        self.presets = presets
    }
}

private final class StubFloodFillService: FloodFillProviding {
    private let images: [CGImage]
    private var index = 0

    init(images: [UIImage]) {
        self.images = images.compactMap(\.cgImage)
    }

    func floodFill(
        image _: CGImage,
        at _: CGPoint,
        with _: UIColor,
        tolerance _: Int
    ) -> CGImage? {
        guard !images.isEmpty else {
            return nil
        }

        let currentImage = images[min(index, images.count - 1)]
        if index < images.count - 1 {
            index += 1
        }
        return currentImage
    }
}

private actor StubCategoryStore: TemplateCategoryStoreProviding {
    private var categories: [TemplateCategory] = []
    private var assignments: [String: String] = [:]
    private var categoryOrder: [String] = []

    func loadUserCategories() throws -> [TemplateCategory] {
        categories
    }

    func saveUserCategories(_ categories: [TemplateCategory]) throws {
        self.categories = categories
    }

    func loadCategoryAssignments() throws -> [String: String] {
        assignments
    }

    func saveCategoryAssignments(_ assignments: [String: String]) throws {
        self.assignments = assignments
    }

    func loadCategoryOrder() throws -> [String] {
        categoryOrder
    }

    func saveCategoryOrder(_ categoryOrder: [String]) throws {
        self.categoryOrder = categoryOrder
    }
}

@MainActor
private final class StubGalleryStore: GalleryStoreProviding {
    private var entries: [ArtworkEntry] = []

    func loadEntries() throws -> [ArtworkEntry] {
        entries
    }

    func saveArtwork(imageData: Data, sourceTemplateID: String, sourceTemplateName: String) throws -> ArtworkEntry {
        let entry = ArtworkEntry(
            id: UUID().uuidString,
            sourceTemplateID: sourceTemplateID,
            sourceTemplateName: sourceTemplateName,
            createdAt: Date(),
            fullImageFilename: "test.png",
            thumbnailFilename: "test_thumb.png"
        )
        entries.insert(entry, at: 0)
        return entry
    }

    func deleteEntry(_ id: String) throws {
        let targetID = id
        entries.removeAll { entry in entry.id == targetID }
    }
}
