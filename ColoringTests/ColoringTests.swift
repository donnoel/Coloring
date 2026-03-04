import CoreGraphics
import Foundation
import PencilKit
import SwiftUI
import UIKit
import XCTest

@testable import Coloring

final class ColoringTests: XCTestCase {
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
            XCTAssertEqual(viewModel.allCategories[1], TemplateCategory.inProgressCategory)
            XCTAssertEqual(viewModel.allCategories[2], TemplateCategory.favoritesCategory)
            XCTAssertEqual(viewModel.allCategories[3], TemplateCategory.recentCategory)
            XCTAssertEqual(viewModel.allCategories[4], TemplateCategory.completedCategory)
            XCTAssertEqual(viewModel.allCategories[5].name, "Action & Motion")
        }
    }

    func testFavoritesCompletedAndRecentCategoriesFilterTemplates() async {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let thirdTemplate = Self.makeTemplate(id: "builtin-3", title: "Template Three")
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [firstTemplate, secondTemplate, thirdTemplate]),
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
            viewModel.selectTemplate(secondTemplate.id)
            viewModel.selectTemplate(thirdTemplate.id)
            viewModel.toggleFavorite(for: secondTemplate.id)
            viewModel.toggleCompleted(for: thirdTemplate.id)

            viewModel.selectedCategoryFilter = TemplateCategory.favoritesCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [secondTemplate.id])

            viewModel.selectedCategoryFilter = TemplateCategory.completedCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [thirdTemplate.id])

            viewModel.selectedCategoryFilter = TemplateCategory.recentCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [thirdTemplate.id, secondTemplate.id])
        }
    }

    func testUndoRedoRestoresStrokeAndFillChanges() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let filledImage = await MainActor.run {
            solidColorTemplateImage(.red, size: CGSize(width: 8, height: 8))
        }
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: StubFloodFillService(images: [filledImage]),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }

        await MainActor.run {
            viewModel.updateDrawing(sampleDrawing)
            XCTAssertTrue(viewModel.canUndoEdit)

            viewModel.clearDrawing()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.undoLastEdit()
            XCTAssertEqual(viewModel.currentDrawing.strokes.count, sampleDrawing.strokes.count)

            viewModel.redoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.isFillModeActive = true
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplyFill = await waitForCondition {
            await MainActor.run {
                viewModel.currentFillImage != nil
            }
        }
        XCTAssertTrue(didApplyFill, "Expected fill overlay to be applied.")

        await MainActor.run {
            XCTAssertNotNil(viewModel.currentFillImage)
            viewModel.clearFills()
            XCTAssertNil(viewModel.currentFillImage)

            viewModel.undoLastEdit()
            XCTAssertNotNil(viewModel.currentFillImage)
        }
    }

    func testInProgressCategoryLoadsPersistedColoringForUnselectedTemplate() async throws {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let drawingStore = StubTemplateDrawingStore()
        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }
        let layerStack = LayerStack.singleLayer(drawingData: sampleDrawing.dataRepresentation())
        let layerStackData = try JSONEncoder().encode(layerStack)
        try await drawingStore.saveLayerStackData(layerStackData, for: secondTemplate.id)

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [firstTemplate, secondTemplate]),
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
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
            XCTAssertEqual(viewModel.allCategories[1], TemplateCategory.inProgressCategory)
            XCTAssertEqual(viewModel.allCategories[2], TemplateCategory.favoritesCategory)
            XCTAssertEqual(viewModel.inProgressTemplateIDs, Set([secondTemplate.id]))

            viewModel.selectedCategoryFilter = TemplateCategory.inProgressCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [secondTemplate.id])
        }
    }

    func testInProgressCategoryIgnoresSerializedEmptyDrawingData() async throws {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let drawingStore = StubTemplateDrawingStore()
        let emptyDrawingData = await MainActor.run { PKDrawing().dataRepresentation() }
        let layerStack = LayerStack.singleLayer(drawingData: emptyDrawingData)
        let layerStackData = try JSONEncoder().encode(layerStack)
        try await drawingStore.saveLayerStackData(layerStackData, for: secondTemplate.id)

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [firstTemplate, secondTemplate]),
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            XCTAssertTrue(viewModel.inProgressTemplateIDs.isEmpty)
            viewModel.selectedCategoryFilter = TemplateCategory.inProgressCategory.id
            XCTAssertTrue(viewModel.filteredTemplates.isEmpty)
        }
    }

    func testInProgressCategoryTracksBothStrokesAndFills() async throws {
        let strokeTemplate = Self.makeTemplate(id: "builtin-strokes", title: "Template One")
        let fillTemplate = Self.makeTemplate(id: "builtin-fills", title: "Template Two")
        let drawingStore = StubTemplateDrawingStore()
        try await drawingStore.saveFillData(sampleTemplateImageData, for: fillTemplate.id)

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [strokeTemplate, fillTemplate]),
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }
        await MainActor.run {
            viewModel.updateDrawing(sampleDrawing)
            viewModel.createUserCategory(name: "Favorites")
            guard let categoryID = viewModel.userCategories.first?.id else {
                XCTFail("Expected created category.")
                return
            }
            viewModel.assignTemplate(fillTemplate.id, toCategoryID: categoryID)
        }

        await MainActor.run {
            XCTAssertEqual(viewModel.inProgressTemplateIDs, Set([strokeTemplate.id, fillTemplate.id]))

            viewModel.selectedCategoryFilter = TemplateCategory.inProgressCategory.id
            XCTAssertEqual(
                Set(viewModel.filteredTemplates.map(\.id)),
                Set([strokeTemplate.id, fillTemplate.id])
            )
        }
    }

    func testCompletedTemplateIsHiddenFromInProgressCategory() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
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
        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }

        await MainActor.run {
            viewModel.updateDrawing(sampleDrawing)
            XCTAssertEqual(viewModel.visibleInProgressTemplateIDs, Set([template.id]))

            viewModel.toggleCompleted(for: template.id)
            XCTAssertTrue(viewModel.visibleInProgressTemplateIDs.isEmpty)

            viewModel.selectedCategoryFilter = TemplateCategory.inProgressCategory.id
            XCTAssertTrue(viewModel.filteredTemplates.isEmpty)

            viewModel.selectedCategoryFilter = TemplateCategory.completedCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [template.id])

            viewModel.toggleCompleted(for: template.id)
            XCTAssertEqual(viewModel.visibleInProgressTemplateIDs, Set([template.id]))

            viewModel.selectedCategoryFilter = TemplateCategory.inProgressCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [template.id])
        }
    }

    func testPersistedCompletedTemplateIsExcludedFromInProgressAfterCategoryRestore() async throws {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let drawingStore = StubTemplateDrawingStore()
        let categoryStore = StubCategoryStore()
        try await drawingStore.saveFillData(sampleTemplateImageData, for: secondTemplate.id)
        try await categoryStore.saveCompletedTemplateIDs([secondTemplate.id])

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [firstTemplate, secondTemplate]),
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: categoryStore,
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            viewModel.loadCategoriesIfNeeded()
        }

        let categoriesLoaded = await waitForCondition {
            await MainActor.run {
                viewModel.isCompleted(secondTemplate.id)
            }
        }
        XCTAssertTrue(categoriesLoaded, "Expected completed state to restore from storage.")

        await MainActor.run {
            XCTAssertEqual(viewModel.inProgressTemplateIDs, Set([secondTemplate.id]))
            XCTAssertTrue(viewModel.visibleInProgressTemplateIDs.isEmpty)

            viewModel.selectedCategoryFilter = TemplateCategory.inProgressCategory.id
            XCTAssertTrue(viewModel.filteredTemplates.isEmpty)

            viewModel.selectedCategoryFilter = TemplateCategory.completedCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [secondTemplate.id])
        }
    }

    func testClearingLastStrokeAndFillRemovesTemplateFromInProgress() async throws {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let drawingStore = StubTemplateDrawingStore()
        try await drawingStore.saveFillData(sampleTemplateImageData, for: template.id)

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        let didRestoreFill = await waitForCondition {
            await MainActor.run {
                viewModel.currentFillImage != nil
            }
        }
        XCTAssertTrue(didRestoreFill, "Expected saved fill to restore for the selected template.")

        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }
        await MainActor.run {
            XCTAssertEqual(viewModel.inProgressTemplateIDs, Set([template.id]))

            viewModel.updateDrawing(sampleDrawing)
            XCTAssertEqual(viewModel.inProgressTemplateIDs, Set([template.id]))

            viewModel.clearDrawing()
            XCTAssertEqual(
                viewModel.inProgressTemplateIDs,
                Set([template.id]),
                "Saved fill should keep the template in progress after strokes are cleared."
            )

            viewModel.clearFills()
            XCTAssertTrue(viewModel.inProgressTemplateIDs.isEmpty)

            viewModel.selectedCategoryFilter = TemplateCategory.inProgressCategory.id
            XCTAssertTrue(viewModel.filteredTemplates.isEmpty)
        }
    }

    func testAddLayerCreatesNewActiveLayerAndPreservesExistingDrawing() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
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
        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }

        await MainActor.run {
            viewModel.updateDrawing(sampleDrawing)
            let originalLayerID = viewModel.currentLayerStack.activeLayerID

            viewModel.addLayer()

            XCTAssertEqual(viewModel.currentLayerStack.layers.count, 2)
            XCTAssertNotEqual(viewModel.currentLayerStack.activeLayerID, originalLayerID)
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.selectActiveLayer(originalLayerID)
            XCTAssertEqual(viewModel.currentDrawing.strokes.count, sampleDrawing.strokes.count)
        }
    }

    func testDeleteActiveLayerRestoresPreviousLayerDrawing() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
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
        let firstDrawing = await MainActor.run { makeSampleTemplateDrawing() }
        let secondDrawing = await MainActor.run { makeSampleTemplateDrawing() }

        await MainActor.run {
            viewModel.updateDrawing(firstDrawing)
            let originalLayerID = viewModel.currentLayerStack.activeLayerID

            viewModel.addLayer()
            let activeLayerID = viewModel.currentLayerStack.activeLayerID
            viewModel.updateDrawing(secondDrawing)

            viewModel.deleteLayer(activeLayerID)

            XCTAssertEqual(viewModel.currentLayerStack.layers.count, 1)
            XCTAssertEqual(viewModel.currentLayerStack.activeLayerID, originalLayerID)
            XCTAssertEqual(viewModel.currentDrawing.strokes.count, firstDrawing.strokes.count)
        }
    }

    func testDeleteUserCategoryClearsAssignmentAndResetsFilter() async {
        let template = Self.makeTemplate(
            id: "imported-1",
            title: "Imported One",
            source: .imported
        )
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template], importedCount: 1),
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
            viewModel.createUserCategory(name: "Favorites")
            guard let categoryID = viewModel.userCategories.first?.id else {
                XCTFail("Expected created category.")
                return
            }

            viewModel.assignTemplate(template.id, toCategoryID: categoryID)
            viewModel.selectedCategoryFilter = categoryID

            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [template.id])

            viewModel.deleteUserCategory(categoryID)

            XCTAssertEqual(viewModel.selectedCategoryFilter, TemplateCategory.allCategory.id)
            XCTAssertTrue(viewModel.userCategories.isEmpty)
            XCTAssertNil(viewModel.categoryAssignments[template.id])
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), [template.id])
        }
    }

    func testLoadCategoriesRestoresPersistedUserCategoriesAssignmentsAndOrder() async throws {
        let templates = [
            Self.makeTemplate(id: "builtin-bridge", title: "Brooklyn Bridge"),
            Self.makeTemplate(id: "imported-1", title: "Imported One", source: .imported)
        ]
        let categoryStore = StubCategoryStore()
        let userCategory = TemplateCategory(id: "user-favorites", name: "Favorites", isUserCreated: true)

        try await categoryStore.saveUserCategories([userCategory])
        try await categoryStore.saveCategoryAssignments(["imported-1": userCategory.id])
        try await categoryStore.saveCategoryOrder([userCategory.id])

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: templates, importedCount: 1),
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: categoryStore,
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        await MainActor.run {
            viewModel.loadCategoriesIfNeeded()
        }

        let categoriesLoaded = await waitForCondition {
            await MainActor.run {
                viewModel.userCategories.contains(where: { $0.id == userCategory.id })
                    && viewModel.categoryAssignments["imported-1"] == userCategory.id
                    && viewModel.reorderableCategories.first?.id == userCategory.id
            }
        }

        XCTAssertTrue(categoriesLoaded)

        await MainActor.run {
            viewModel.selectedCategoryFilter = userCategory.id
            XCTAssertEqual(viewModel.filteredTemplates.map(\.id), ["imported-1"])
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

    func testTemplateLibraryServiceImportsRenamesAndDeletesTemplateLocally() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let service = TemplateLibraryService(
            documentsDirectoryURLProvider: { documentsURL },
            ubiquityContainerURLProvider: { _ in nil }
        )

        let importedTemplate = try await service.importTemplate(
            imageData: sampleTemplateImageData,
            preferredName: "Aurora Sketch"
        )

        XCTAssertEqual(importedTemplate.source, .imported)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedTemplate.filePath))

        let renamedTemplate = try await service.renameImportedTemplate(
            id: importedTemplate.id,
            newTitle: "Golden Hour"
        )

        XCTAssertNotEqual(renamedTemplate.id, importedTemplate.id)
        XCTAssertEqual(renamedTemplate.title, "Golden Hour")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedTemplate.filePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedTemplate.filePath))

        try await service.deleteImportedTemplate(id: renamedTemplate.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedTemplate.filePath))
    }

    func testTemplateLibraryServiceRejectsInvalidImageData() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let service = TemplateLibraryService(
            documentsDirectoryURLProvider: { documentsURL },
            ubiquityContainerURLProvider: { _ in nil }
        )

        do {
            _ = try await service.importTemplate(
                imageData: Data("not-an-image".utf8),
                preferredName: "Broken"
            )
            XCTFail("Expected invalid image data error.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                TemplateLibraryService.LibraryError.invalidImageData.localizedDescription
            )
        }
    }

    func testBrushPresetStoreServicePersistsPresetsAcrossInstances() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let firstStore = makeRealBrushPresetStore(documentsURL: documentsURL)
        let secondStore = makeRealBrushPresetStore(documentsURL: documentsURL)
        let presets = [
            BrushPreset(
                id: "custom-1",
                name: "Studio Ink",
                inkType: .pen,
                width: 6.5,
                opacity: 0.8,
                isBuiltIn: false
            )
        ]

        try await firstStore.saveUserPresets(presets)

        let loadedPresets = try await secondStore.loadUserPresets()

        XCTAssertEqual(loadedPresets, presets)
    }

    func testTemplateCategoryStoreServicePersistsCategoriesAssignmentsAndOrder() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let firstStore = makeRealCategoryStore(documentsURL: documentsURL)
        let secondStore = makeRealCategoryStore(documentsURL: documentsURL)
        let categories = [
            TemplateCategory(id: "user-1", name: "Favorites", isUserCreated: true),
            TemplateCategory(id: "user-2", name: "Portrait Ideas", isUserCreated: true)
        ]
        let assignments = [
            "imported-1": "user-1",
            "imported-2": "user-2"
        ]
        let categoryOrder = ["user-2", "user-1"]

        try await firstStore.saveUserCategories(categories)
        try await firstStore.saveCategoryAssignments(assignments)
        try await firstStore.saveCategoryOrder(categoryOrder)

        let loadedCategories = try await secondStore.loadUserCategories()
        let loadedAssignments = try await secondStore.loadCategoryAssignments()
        let loadedOrder = try await secondStore.loadCategoryOrder()

        XCTAssertEqual(loadedCategories, categories)
        XCTAssertEqual(loadedAssignments, assignments)
        XCTAssertEqual(loadedOrder, categoryOrder)
    }

    func testGalleryStoreServiceSavesLoadsAndDeletesArtworkLocally() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let galleryURL = documentsURL.appendingPathComponent("GalleryTest", isDirectory: true)
        let store = makeRealGalleryStore(galleryURL: galleryURL)
        let imageData = await MainActor.run {
            solidColorTemplateImageData(.orange, size: CGSize(width: 32, height: 20))
        }

        let entry = try await store.saveArtwork(
            imageData: imageData,
            sourceTemplateID: "builtin-1",
            sourceTemplateName: "Template One"
        )

        let entriesAfterSave = try await store.loadEntries()
        let fullImageURL = galleryURL.appendingPathComponent(entry.fullImageFilename)
        let thumbnailURL = galleryURL.appendingPathComponent(entry.thumbnailFilename)

        XCTAssertEqual(entriesAfterSave.count, 1)
        XCTAssertEqual(entriesAfterSave.first?.id, entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullImageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))

        try await store.deleteEntry(entry.id)

        let entriesAfterDelete = try await store.loadEntries()
        XCTAssertTrue(entriesAfterDelete.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fullImageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
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
            XCTAssertFalse(viewModel.canUndoEdit)
            XCTAssertFalse(viewModel.canRedoEdit)
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplyFirstFill = await waitForCondition {
            await MainActor.run {
                self.imageSignature(from: viewModel.currentFillImage) != nil
                    && viewModel.canUndoEdit
                    && !viewModel.canRedoEdit
            }
        }
        XCTAssertTrue(didApplyFirstFill, "Expected first fill overlay to be applied.")

        guard let firstSignature = await MainActor.run(body: {
            imageSignature(from: viewModel.currentFillImage)
        }) else {
            XCTFail("Expected first fill signature.")
            return
        }

        await MainActor.run {
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplySecondFill = await waitForCondition {
            await MainActor.run {
                guard let currentSignature = self.imageSignature(from: viewModel.currentFillImage) else {
                    return false
                }

                return currentSignature != firstSignature
                    && viewModel.canUndoEdit
                    && !viewModel.canRedoEdit
            }
        }
        XCTAssertTrue(didApplySecondFill, "Expected second fill overlay to be applied.")

        guard let secondSignature = await MainActor.run(body: {
            imageSignature(from: viewModel.currentFillImage)
        }) else {
            XCTFail("Expected second fill signature.")
            return
        }

        await MainActor.run {
            XCTAssertNotEqual(firstSignature, secondSignature)
            XCTAssertTrue(viewModel.canUndoEdit)
            XCTAssertFalse(viewModel.canRedoEdit)

            viewModel.undoLastEdit()
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), firstSignature)
            XCTAssertTrue(viewModel.canUndoEdit)
            XCTAssertTrue(viewModel.canRedoEdit)

            viewModel.undoLastEdit()
            XCTAssertNil(viewModel.currentFillImage)
            XCTAssertFalse(viewModel.canUndoEdit)
            XCTAssertTrue(viewModel.canRedoEdit)

            viewModel.redoLastEdit()
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), firstSignature)
            XCTAssertTrue(viewModel.canUndoEdit)
            XCTAssertTrue(viewModel.canRedoEdit)

            viewModel.redoLastEdit()
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), secondSignature)
            XCTAssertTrue(viewModel.canUndoEdit)
            XCTAssertFalse(viewModel.canRedoEdit)
        }
    }

    func testHandleFillTapDoesNothingWhenFillModeIsDisabled() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let templateImageData = await MainActor.run {
            solidColorTemplateImageData(.white, size: CGSize(width: 8, height: 8))
        }
        let floodFillService = StubFloodFillService(images: [await MainActor.run {
            solidColorTemplateImage(.red, size: CGSize(width: 8, height: 8))
        }])
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(
                    templates: [template],
                    imageDataSequence: [templateImageData]
                ),
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
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
            XCTAssertNil(viewModel.currentFillImage)
            XCTAssertFalse(viewModel.canUndoEdit)
        }
    }

    func testFillEraseClearsFilledRegionAndSupportsUndo() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let templateImageData = await MainActor.run {
            solidColorTemplateImageData(.white, size: CGSize(width: 8, height: 8))
        }
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(
                    templates: [template],
                    imageDataSequence: [templateImageData]
                ),
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
            viewModel.isFillModeActive = true
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplyFill = await waitForCondition {
            await MainActor.run {
                viewModel.currentFillImage != nil
            }
        }
        XCTAssertTrue(didApplyFill, "Expected fill overlay to be applied before erase.")

        guard let filledSignature = await MainActor.run(body: {
            imageSignature(from: viewModel.currentFillImage)
        }) else {
            XCTFail("Expected fill signature.")
            return
        }

        await MainActor.run {
            XCTAssertEqual(viewModel.inProgressTemplateIDs, Set([template.id]))

            viewModel.isFillModeActive = false
            viewModel.handleFillErase(at: CGPoint(x: 0.5, y: 0.5))

            XCTAssertNil(viewModel.currentFillImage)
            XCTAssertTrue(viewModel.canUndoEdit)
            XCTAssertTrue(viewModel.inProgressTemplateIDs.isEmpty)

            viewModel.undoLastEdit()
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), filledSignature)
            XCTAssertEqual(viewModel.inProgressTemplateIDs, Set([template.id]))
        }
    }

    func testSelectingFilledTemplateRestoresFillFromInMemoryState() async {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let templateImageData = await MainActor.run {
            solidColorTemplateImageData(.white, size: CGSize(width: 8, height: 8))
        }
        let filledImage = await MainActor.run {
            solidColorTemplateImage(.red, size: CGSize(width: 8, height: 8))
        }

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(
                    templates: [firstTemplate, secondTemplate],
                    imageDataSequence: [templateImageData, templateImageData]
                ),
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: StubFloodFillService(images: [filledImage]),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()

        await MainActor.run {
            viewModel.isFillModeActive = true
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplyFill = await waitForCondition {
            await MainActor.run {
                viewModel.currentFillImage != nil
            }
        }
        XCTAssertTrue(didApplyFill, "Expected fill overlay to be applied before switching templates.")

        guard let filledSignature = await MainActor.run(body: {
            imageSignature(from: viewModel.currentFillImage)
        }) else {
            XCTFail("Expected fill signature.")
            return
        }

        await MainActor.run {
            viewModel.selectTemplate(secondTemplate.id)
            XCTAssertNil(viewModel.currentFillImage)

            viewModel.selectTemplate(firstTemplate.id)
            XCTAssertEqual(imageSignature(from: viewModel.currentFillImage), filledSignature)
        }
    }

    func testLoadBrushPresetsIfNeededLoadsUserPresets() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let brushStore = StubBrushPresetStore()
        let customPreset = BrushPreset(
            id: "custom-loaded",
            name: "Loaded Brush",
            inkType: .pen,
            width: 7,
            opacity: 0.7,
            isBuiltIn: false
        )
        try? await brushStore.saveUserPresets([customPreset])

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: brushStore,
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await MainActor.run {
            viewModel.loadBrushPresetsIfNeeded()
        }

        let didLoadPresets = await waitForCondition {
            await MainActor.run {
                viewModel.userBrushPresets.contains(where: { $0.id == customPreset.id })
            }
        }

        XCTAssertTrue(didLoadPresets)
    }

    func testDeleteCustomPresetFallsBackToDefaultBuiltInPreset() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
                exportService: StubTemplateExportService(),
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await MainActor.run {
            viewModel.saveCurrentAsPreset(name: "Artist Brush")
            guard let customPreset = viewModel.userBrushPresets.first else {
                XCTFail("Expected saved custom preset.")
                return
            }

            viewModel.selectBrushPreset(customPreset)
            viewModel.deleteCustomPreset(customPreset.id)

            XCTAssertTrue(viewModel.userBrushPresets.isEmpty)
            XCTAssertEqual(viewModel.activeBrushPreset.id, BrushPreset.builtInPresets[0].id)
        }
    }

    func testExportCurrentTemplateSavesArtworkToGallery() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let templateImageData = await MainActor.run {
            solidColorTemplateImageData(.white, size: CGSize(width: 16, height: 16))
        }
        let exportedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        let exportService = CapturingFileWritingTemplateExportService(resultURL: exportedURL)
        let galleryStore = await MainActor.run { StubGalleryStore() }

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(
                    templates: [template],
                    imageDataSequence: [templateImageData, templateImageData]
                ),
                exportService: exportService,
                drawingStore: StubTemplateDrawingStore(),
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: galleryStore
            )
        }
        addTeardownBlock {
            try? FileManager.default.removeItem(at: exportedURL)
        }

        await viewModel.loadTemplatesIfNeeded()
        await viewModel.exportCurrentTemplate()

        let saveRequest = await MainActor.run { galleryStore.lastSaveRequest }
        XCTAssertNotNil(saveRequest)
        XCTAssertEqual(saveRequest?.sourceTemplateID, template.id)
        XCTAssertEqual(saveRequest?.sourceTemplateName, template.title)
        XCTAssertTrue((saveRequest?.imageData.isEmpty ?? true) == false)
    }

    func testTemplateArtworkExportServiceRejectsInvalidTemplateData() async {
        let service = TemplateArtworkExportService()

        do {
            _ = try await service.exportPNG(
                templateData: Data("invalid".utf8),
                drawingData: Data(),
                fillLayerData: nil,
                compositedLayersImageData: nil,
                canvasSize: CGSize(width: 16, height: 16),
                templateID: "invalid"
            )
            XCTFail("Expected invalid template error.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                TemplateArtworkExportService.ExportError.invalidTemplate.localizedDescription
            )
        }
    }

    func testTemplateArtworkExportServiceWritesPNGFile() async throws {
        let service = TemplateArtworkExportService()
        let templateData = await MainActor.run {
            solidColorTemplateImageData(.white, size: CGSize(width: 10, height: 10))
        }
        let fillData = await MainActor.run {
            solidColorTemplateImageData(.red, size: CGSize(width: 10, height: 10))
        }

        let exportedURL = try await service.exportPNG(
            templateData: templateData,
            drawingData: Data(),
            fillLayerData: fillData,
            compositedLayersImageData: nil,
            canvasSize: CGSize(width: 10, height: 10),
            templateID: "export-test"
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: exportedURL)
        }

        let exportedData = try Data(contentsOf: exportedURL)
        XCTAssertFalse(exportedData.isEmpty)

        let signature = Array(exportedData.prefix(8))
        XCTAssertEqual(signature, [137, 80, 78, 71, 13, 10, 26, 10])
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

            let synchronizedDrawing = localDrawing.stableColorDrawing(using: canvasView.traitCollection)

            XCTAssertEqual(drawingState.drawing.strokes.count, synchronizedDrawing.strokes.count)
            XCTAssertFalse(
                coordinator.shouldApplyExternalDrawing(
                    synchronizedDrawing,
                    currentCanvasDrawing: initialDrawing
                )
            )

            coordinator.resetLocalDrawingSyncTracking()

            XCTAssertTrue(
                coordinator.shouldApplyExternalDrawing(
                    synchronizedDrawing,
                    currentCanvasDrawing: initialDrawing
                )
            )
        }
    }

    func testPencilCanvasCoordinatorClearsPendingSyncWhenBindingCatchesUp() async {
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
            let synchronizedDrawing = drawingState.drawing

            XCTAssertFalse(
                coordinator.shouldApplyExternalDrawing(
                    initialDrawing,
                    currentCanvasDrawing: canvasView.drawing
                )
            )

            XCTAssertFalse(
                coordinator.shouldApplyExternalDrawing(
                    synchronizedDrawing,
                    currentCanvasDrawing: canvasView.drawing
                )
            )

            XCTAssertTrue(
                coordinator.shouldApplyExternalDrawing(
                    initialDrawing,
                    currentCanvasDrawing: canvasView.drawing
                )
            )
        }
    }

    func testPencilCanvasCoordinatorSkipsReapplyWhenBindingMatchesLatestLocalData() async {
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

            XCTAssertFalse(
                coordinator.shouldApplyExternalDrawing(
                    localDrawing,
                    currentCanvasDrawing: initialDrawing
                )
            )
        }
    }

    func testPencilCanvasCoordinatorAllowsForcedDrawingReapplyDuringLocalSync() async {
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

            XCTAssertTrue(
                coordinator.shouldApplyExternalDrawing(
                    initialDrawing,
                    currentCanvasDrawing: canvasView.drawing,
                    forceExternalUpdate: true
                )
            )
        }
    }

    func testCanvasDrivenStrokeEnablesUndoHistory() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
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
        let sampleDrawing = await MainActor.run { makeSampleTemplateDrawing() }

        await MainActor.run {
            let view = PencilCanvasView(
                templateImage: solidColorTemplateImage(.white),
                templateID: viewModel.selectedTemplateID,
                drawing: Binding(
                    get: { viewModel.currentDrawing },
                    set: { viewModel.currentDrawing = $0 }
                ),
                onDrawingChanged: { drawing in
                    viewModel.updateDrawing(drawing)
                }
            )

            let coordinator = view.makeCoordinator()
            let canvasView = PKCanvasView()
            canvasView.drawing = sampleDrawing

            coordinator.canvasViewDrawingDidChange(canvasView)

            XCTAssertTrue(viewModel.canUndoEdit)

            viewModel.undoLastEdit()

            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)
        }
    }

    func testRestoredFillDoesNotSeedUndoHistory() async throws {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let drawingStore = StubTemplateDrawingStore()
        let fillData = await MainActor.run {
            solidColorTemplateImage(.red, size: CGSize(width: 8, height: 8)).pngData()
        }
        try await drawingStore.saveFillData(XCTUnwrap(fillData), for: template.id)

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [template]),
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
                floodFillService: FloodFillService(),
                layerCompositor: LayerCompositorService(),
                brushPresetStore: StubBrushPresetStore(),
                categoryStore: StubCategoryStore(),
                galleryStore: StubGalleryStore()
            )
        }

        await viewModel.loadTemplatesIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)

        await MainActor.run {
            XCTAssertNotNil(viewModel.currentFillImage)
            XCTAssertFalse(viewModel.canUndoEdit)
            XCTAssertFalse(viewModel.canRedoEdit)

            viewModel.undoLastEdit()
            XCTAssertNotNil(viewModel.currentFillImage)
            XCTAssertFalse(viewModel.canRedoEdit)
        }
    }

    func testRefreshTemplatesFromStoragePreservesSelectionAcrossReload() async {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let thirdTemplate = Self.makeTemplate(id: "imported-1", title: "Imported One", source: .imported)
        let library = StubTemplateLibrary(templates: [firstTemplate, secondTemplate])

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
            viewModel.selectTemplate(secondTemplate.id)
        }

        await library.replaceTemplates(
            [firstTemplate, secondTemplate, thirdTemplate],
            importedCount: 1
        )

        await viewModel.refreshTemplatesFromStorage()

        await MainActor.run {
            XCTAssertEqual(viewModel.selectedTemplateID, secondTemplate.id)
            XCTAssertEqual(viewModel.selectedTemplate?.title, secondTemplate.title)
            XCTAssertTrue(viewModel.templates.contains(where: { $0.id == thirdTemplate.id }))
        }
    }

    @MainActor
    func testStableDisplayImageStripsTraitBasedAssetVariants() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let lightImage = solidColorTemplateImage(.red, size: CGSize(width: 6, height: 6))
        let darkImage = solidColorTemplateImage(.blue, size: CGSize(width: 6, height: 6))
        let asset = UIImageAsset()
        asset.register(lightImage, with: lightTraits)
        asset.register(darkImage, with: darkTraits)

        let adaptiveImage = asset.image(with: lightTraits)
        let stabilizedImage = adaptiveImage.stableDisplayImage()

        XCTAssertEqual(stabilizedImage.renderingMode, .alwaysOriginal)
        XCTAssertEqual(imageSignature(from: stabilizedImage), imageSignature(from: lightImage))
    }

    @MainActor
    func testZoomableCanvasContainerPinsArtworkSurfaceToLightAppearance() {
        let container = ZoomableCanvasContainerView()

        XCTAssertEqual(container.contentView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(container.imageView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(container.fillImageView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(container.belowLayerImageView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(container.canvasView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(container.aboveLayerImageView.overrideUserInterfaceStyle, .light)
        XCTAssertTrue(container.contentView.backgroundColor?.isEqual(UIColor.white) == true)
    }

    func testStableResolvedColorPreservesMonochromeChannelValues() {
        let monochromeBlack = UIColor(cgColor: CGColor(gray: 0, alpha: 1))
        XCTAssertEqual(monochromeBlack.cgColor.colorSpace?.model, .monochrome)

        let stabilizedBlack = monochromeBlack.stableResolvedColor(using: nil)
        assertColorComponents(
            stabilizedBlack,
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )

        let semiTransparentWhite = UIColor(cgColor: CGColor(gray: 1, alpha: 0.5))
        XCTAssertEqual(semiTransparentWhite.cgColor.colorSpace?.model, .monochrome)

        let stabilizedWhite = semiTransparentWhite.stableResolvedColor(using: nil)
        assertColorComponents(
            stabilizedWhite,
            red: 1,
            green: 1,
            blue: 1,
            alpha: 0.5
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

    private func assertColorComponents(
        _ color: UIColor,
        red expectedRed: CGFloat,
        green expectedGreen: CGFloat,
        blue expectedBlue: CGFloat,
        alpha expectedAlpha: CGFloat,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0

        XCTAssertTrue(
            color.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha),
            file: file,
            line: line
        )
        XCTAssertEqual(actualRed, expectedRed, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: accuracy, file: file, line: line)
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

    private func makeRealBrushPresetStore(documentsURL: URL) -> BrushPresetStoreService {
        BrushPresetStoreService(
            documentsDirectoryURLProvider: { documentsURL }
        )
    }

    private func makeRealCategoryStore(documentsURL: URL) -> TemplateCategoryStoreService {
        TemplateCategoryStoreService(
            documentsDirectoryURLProvider: { documentsURL }
        )
    }

    private func makeRealGalleryStore(galleryURL: URL) -> GalleryStoreService {
        GalleryStoreService(
            galleryDirectoryURLProvider: { galleryURL }
        )
    }
}

@MainActor
private final class DrawingStateBox {
    var drawing = PKDrawing()
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

    func replaceTemplates(_ templates: [ColoringTemplate], importedCount: Int = 0) {
        let clampedImportedCount = max(0, min(importedCount, templates.count))
        let builtInCount = templates.count - clampedImportedCount
        builtInTemplates = Array(templates.prefix(builtInCount))
        importedTemplates = Array(templates.suffix(clampedImportedCount))
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

private actor CapturingFileWritingTemplateExportService: TemplateArtworkExporting {
    let resultURL: URL

    init(resultURL: URL) {
        self.resultURL = resultURL
    }

    func exportPNG(
        templateData _: Data,
        drawingData _: Data,
        fillLayerData _: Data?,
        compositedLayersImageData _: Data?,
        canvasSize _: CGSize,
        templateID _: String
    ) async throws -> URL {
        let data = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/w8AAgMBgGd9mKsAAAAASUVORK5CYII="
        )!
        try data.write(to: resultURL, options: .atomic)
        return resultURL
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

private final class StubFloodFillService: FloodFillProviding, @unchecked Sendable {
    private let images: [CGImage]
    private let lock = NSLock()
    private var index = 0

    init(images: [UIImage]) {
        self.images = images.compactMap(\.cgImage)
    }

    nonisolated func floodFill(
        image _: CGImage,
        at _: CGPoint,
        with _: UIColor,
        tolerance _: Int
    ) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }

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
    private var favorites: Set<String> = []
    private var completed: Set<String> = []
    private var recent: [String] = []

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

    func loadFavoriteTemplateIDs() throws -> Set<String> {
        favorites
    }

    func saveFavoriteTemplateIDs(_ templateIDs: Set<String>) throws {
        favorites = templateIDs
    }

    func loadCompletedTemplateIDs() throws -> Set<String> {
        completed
    }

    func saveCompletedTemplateIDs(_ templateIDs: Set<String>) throws {
        completed = templateIDs
    }

    func loadRecentTemplateIDs() throws -> [String] {
        recent
    }

    func saveRecentTemplateIDs(_ templateIDs: [String]) throws {
        recent = templateIDs
    }
}

@MainActor
private final class StubGalleryStore: GalleryStoreProviding {
    struct SaveRequest {
        let imageData: Data
        let sourceTemplateID: String
        let sourceTemplateName: String
    }

    private var entries: [ArtworkEntry] = []
    private(set) var lastSaveRequest: SaveRequest?

    func loadEntries() throws -> [ArtworkEntry] {
        entries
    }

    func saveArtwork(imageData: Data, sourceTemplateID: String, sourceTemplateName: String) throws -> ArtworkEntry {
        lastSaveRequest = SaveRequest(
            imageData: imageData,
            sourceTemplateID: sourceTemplateID,
            sourceTemplateName: sourceTemplateName
        )
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
