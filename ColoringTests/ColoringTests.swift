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

    func testManifestDrivenBuiltInCategoriesAppearFromTemplateMetadata() async {
        let templates = [
            Self.makeTemplate(
                id: "builtin-cats",
                title: "Cats",
                category: "Animals",
                shelfCategory: "animals",
                complexity: "easy",
                canvasOrientation: .landscape
            ),
            Self.makeTemplate(
                id: "builtin-forest",
                title: "Forest Trail",
                category: "Nature",
                shelfCategory: "nature",
                complexity: "medium",
                canvasOrientation: .landscape
            ),
            Self.makeTemplate(
                id: "builtin-neon",
                title: "Neon Rush",
                category: "Fantasy",
                shelfCategory: "fantasy",
                complexity: "detailed",
                canvasOrientation: .portrait
            ),
            Self.makeTemplate(
                id: "builtin-gp",
                title: "Grand Prix",
                category: "Motorsport",
                shelfCategory: "motorsport",
                complexity: "dense",
                canvasOrientation: .landscape
            ),
            Self.makeTemplate(
                id: "builtin-orbit",
                title: "Orbital Dock",
                category: "Sci-Fi",
                shelfCategory: "scifi",
                complexity: "dense",
                canvasOrientation: .portrait
            )
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
            XCTAssertTrue(categoryNames.contains("Animals"))
            XCTAssertTrue(categoryNames.contains("Nature"))
            XCTAssertTrue(categoryNames.contains("Fantasy"))
            XCTAssertTrue(categoryNames.contains("Motorsport"))
            XCTAssertTrue(categoryNames.contains("Sci-Fi"))
            XCTAssertTrue(categoryNames.contains("Easy"))
            XCTAssertTrue(categoryNames.contains("Medium"))
            XCTAssertTrue(categoryNames.contains("Detailed"))
            XCTAssertTrue(categoryNames.contains("Dense"))
            XCTAssertTrue(categoryNames.contains("Landscape"))
            XCTAssertTrue(categoryNames.contains("Portrait"))
            XCTAssertFalse(categoryNames.contains("Action & Motion"))
        }
    }

    func testManifestDrivenBuiltInCategoriesAllowMultipleFolderMembership() async {
        let neon = Self.makeTemplate(
            id: "builtin-neon",
            title: "Neon City Racing",
            category: "Fantasy",
            shelfCategory: "fantasy",
            complexity: "detailed",
            canvasOrientation: .portrait
        )
        let bridge = Self.makeTemplate(
            id: "builtin-bridge",
            title: "Brooklyn Bridge",
            category: "Cozy",
            shelfCategory: "cozy",
            complexity: "detailed",
            canvasOrientation: .landscape
        )
        let ocean = Self.makeTemplate(
            id: "builtin-ocean",
            title: "Ocean View",
            category: "Nature",
            shelfCategory: "nature",
            complexity: "medium",
            canvasOrientation: .portrait
        )
        let library = StubTemplateLibrary(templates: [neon, bridge, ocean])
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
            guard let fantasyCategoryID = viewModel.allCategories.first(where: { $0.name == "Fantasy" })?.id else {
                XCTFail("Expected Fantasy category.")
                return
            }
            guard let detailedCategoryID = viewModel.allCategories.first(where: { $0.name == "Detailed" })?.id else {
                XCTFail("Expected Detailed category.")
                return
            }
            guard let portraitCategoryID = viewModel.allCategories.first(where: { $0.name == "Portrait" })?.id else {
                XCTFail("Expected Portrait category.")
                return
            }

            viewModel.selectedCategoryFilter = fantasyCategoryID
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([neon.id]))

            viewModel.selectedCategoryFilter = detailedCategoryID
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([neon.id, bridge.id]))

            viewModel.selectedCategoryFilter = portraitCategoryID
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([neon.id, ocean.id]))
        }
    }

    func testMoveCategoriesReordersFolderChips() async {
        let templates = [
            Self.makeTemplate(
                id: "builtin-bridge",
                title: "Brooklyn Bridge",
                category: "Cozy",
                shelfCategory: "cozy",
                complexity: "detailed",
                canvasOrientation: .landscape
            ),
            Self.makeTemplate(
                id: "builtin-cats",
                title: "Cats",
                category: "Animals",
                shelfCategory: "animals",
                complexity: "easy",
                canvasOrientation: .landscape
            ),
            Self.makeTemplate(
                id: "builtin-wheelie",
                title: "Wheelie",
                category: "Fantasy",
                shelfCategory: "fantasy",
                complexity: "medium",
                canvasOrientation: .landscape
            )
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
            guard let sourceIndex = folderNames.firstIndex(of: "Landscape") else {
                XCTFail("Expected Landscape folder.")
                return
            }

            viewModel.moveCategories(from: IndexSet(integer: sourceIndex), to: 0)

            XCTAssertEqual(viewModel.reorderableCategories.first?.name, "Landscape")
            XCTAssertEqual(viewModel.allCategories[1], TemplateCategory.inProgressCategory)
            XCTAssertEqual(viewModel.allCategories[2], TemplateCategory.favoritesCategory)
            XCTAssertEqual(viewModel.allCategories[3], TemplateCategory.recentCategory)
            XCTAssertEqual(viewModel.allCategories[4], TemplateCategory.completedCategory)
            XCTAssertEqual(viewModel.allCategories[5].name, "Landscape")
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

    func testHideTemplateRemovesItFromMainLibraryAndBuiltInCategories() async {
        let scifiTemplate = Self.makeTemplate(
            id: "builtin-scifi",
            title: "Orbital Lab",
            category: "Sci-Fi",
            shelfCategory: "scifi",
            complexity: "dense",
            canvasOrientation: .landscape
        )
        let natureTemplate = Self.makeTemplate(
            id: "builtin-nature",
            title: "Forest Path",
            category: "Nature",
            shelfCategory: "nature",
            complexity: "medium",
            canvasOrientation: .portrait
        )
        let library = StubTemplateLibrary(templates: [scifiTemplate, natureTemplate])
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
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([scifiTemplate.id, natureTemplate.id]))
            XCTAssertTrue(Set(viewModel.builtInCategories.map(\.name)).contains("Sci-Fi"))

            viewModel.hideTemplate(scifiTemplate.id)

            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([natureTemplate.id]))
            XCTAssertEqual(Set(viewModel.hiddenTemplates.map(\.id)), Set([scifiTemplate.id]))
            XCTAssertFalse(Set(viewModel.builtInCategories.map(\.name)).contains("Sci-Fi"))
        }
    }

    func testUnhideTemplateAndUnhideAllRestoreVisibility() async {
        let builtInTemplate = Self.makeTemplate(
            id: "builtin-1",
            title: "Built In",
            shelfCategory: "motorsport",
            complexity: "dense"
        )
        let importedTemplate = Self.makeTemplate(
            id: "imported-1",
            title: "Imported One",
            source: .imported
        )
        let library = StubTemplateLibrary(templates: [builtInTemplate, importedTemplate])
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
            viewModel.hideTemplate(builtInTemplate.id)
            viewModel.hideTemplate(importedTemplate.id)

            XCTAssertTrue(viewModel.filteredTemplates.isEmpty)
            XCTAssertEqual(Set(viewModel.hiddenTemplates.map(\.id)), Set([builtInTemplate.id, importedTemplate.id]))

            viewModel.unhideTemplate(importedTemplate.id)
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([importedTemplate.id]))
            XCTAssertEqual(Set(viewModel.hiddenTemplates.map(\.id)), Set([builtInTemplate.id]))

            viewModel.unhideAllTemplates()
            XCTAssertEqual(Set(viewModel.filteredTemplates.map(\.id)), Set([builtInTemplate.id, importedTemplate.id]))
            XCTAssertTrue(viewModel.hiddenTemplates.isEmpty)
        }
    }

    func testPersistedHiddenTemplateIDsAreAppliedOnLoad() async throws {
        let hiddenTemplate = Self.makeTemplate(
            id: "builtin-hidden",
            title: "Hidden Template",
            shelfCategory: "scifi",
            complexity: "dense"
        )
        let visibleTemplate = Self.makeTemplate(id: "builtin-visible", title: "Visible Template")
        let categoryStore = StubCategoryStore()
        try await categoryStore.saveHiddenTemplateIDs([hiddenTemplate.id])

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [hiddenTemplate, visibleTemplate]),
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

        let didApplyHiddenState = await waitForCondition(timeout: 3.0) {
            await MainActor.run {
                Set(viewModel.filteredTemplates.map(\.id)) == Set([visibleTemplate.id]) &&
                Set(viewModel.hiddenTemplates.map(\.id)) == Set([hiddenTemplate.id])
            }
        }
        XCTAssertTrue(didApplyHiddenState)
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

    func testUndoRemovesOneStrokeWhenStrokeProducesMultipleDrawingUpdates() async {
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

        let stroke1Partial = await MainActor.run { makeSampleTemplateDrawing(color: .black) }
        let stroke1Final = await MainActor.run { makeSampleTemplateDrawing(color: .blue) }
        let stroke2Partial = await MainActor.run {
            let secondStroke = makeSampleTemplateDrawing(color: .red).strokes.first!
            return PKDrawing(strokes: stroke1Final.strokes + [secondStroke])
        }
        let stroke2Final = await MainActor.run {
            let secondStroke = makeSampleTemplateDrawing(color: .green).strokes.first!
            return PKDrawing(strokes: stroke1Final.strokes + [secondStroke])
        }

        await MainActor.run {
            viewModel.updateStrokeInteraction(isActive: true)
            viewModel.updateDrawing(stroke1Partial)
            viewModel.updateDrawing(stroke1Final)
            viewModel.updateStrokeInteraction(isActive: false)

            viewModel.updateStrokeInteraction(isActive: true)
            viewModel.updateDrawing(stroke2Partial)
            viewModel.updateDrawing(stroke2Final)
            viewModel.updateStrokeInteraction(isActive: false)

            XCTAssertEqual(viewModel.currentDrawing.strokes.count, 2)
            XCTAssertTrue(viewModel.canUndoEdit)

            viewModel.undoLastEdit()
            XCTAssertEqual(viewModel.currentDrawing, stroke1Final)
            XCTAssertEqual(viewModel.currentDrawing.strokes.count, 1)

            viewModel.undoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)
        }
    }

    func testUndoRemainsSingleStepWhenStrokeEndCallbackIsMissedAcrossStrokes() async {
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

        let stroke1Final = await MainActor.run { makeSampleTemplateDrawing(color: .blue) }
        let stroke2Final = await MainActor.run {
            let secondStroke = makeSampleTemplateDrawing(color: .green).strokes.first!
            return PKDrawing(strokes: stroke1Final.strokes + [secondStroke])
        }

        await MainActor.run {
            // Simulate rapid drawing where the gesture-end callback is not delivered.
            viewModel.updateStrokeInteraction(isActive: true)
            viewModel.updateDrawing(stroke1Final)
            viewModel.updateDrawing(stroke2Final)

            XCTAssertEqual(viewModel.currentDrawing.strokes.count, 2)

            viewModel.undoLastEdit()
            XCTAssertEqual(viewModel.currentDrawing, stroke1Final)

            viewModel.undoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)
        }
    }

    func testUndoRemainsSingleStepWhenStrokeGestureIsInterrupted() async {
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
            // Simulate interrupted lifecycle: began + drawing updates, but no ended callback.
            viewModel.updateStrokeInteraction(isActive: true)
            viewModel.updateDrawing(sampleDrawing)

            // Another edit action should force-finalize the pending stroke snapshot.
            viewModel.clearDrawing()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            // Undo should step back only one edit (the clear), not multiple edits.
            viewModel.undoLastEdit()
            XCTAssertEqual(viewModel.currentDrawing, sampleDrawing)
            XCTAssertEqual(viewModel.currentDrawing.strokes.count, sampleDrawing.strokes.count)

            // Second undo removes the stroke itself.
            viewModel.undoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)
        }
    }

    func testUndoRedoMixedStrokeFillTimelineOrder() async {
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
            viewModel.isFillModeActive = true
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplyFill = await waitForCondition {
            await MainActor.run { viewModel.currentFillImage != nil }
        }
        XCTAssertTrue(didApplyFill, "Expected fill overlay to be applied.")

        await MainActor.run {
            viewModel.undoLastEdit()
            XCTAssertNil(viewModel.currentFillImage)
            XCTAssertEqual(viewModel.currentDrawing, sampleDrawing)

            viewModel.undoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.redoLastEdit()
            XCTAssertEqual(viewModel.currentDrawing, sampleDrawing)
            XCTAssertNil(viewModel.currentFillImage)

            viewModel.redoLastEdit()
            XCTAssertNotNil(viewModel.currentFillImage)
        }
    }

    func testUndoRedoMixedLayerAndStrokeTimelineOrder() async {
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
        let layerOneStroke = await MainActor.run { makeSampleTemplateDrawing(color: .black) }
        let layerTwoStroke = await MainActor.run { makeSampleTemplateDrawing(color: .blue) }

        await MainActor.run {
            let baseLayerID = viewModel.currentLayerStack.activeLayerID
            XCTAssertEqual(viewModel.currentLayerStack.layers.count, 1)

            viewModel.updateDrawing(layerOneStroke)
            viewModel.addLayer()
            let topLayerID = viewModel.currentLayerStack.activeLayerID
            XCTAssertEqual(viewModel.currentLayerStack.layers.count, 2)
            XCTAssertNotEqual(topLayerID, baseLayerID)
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.updateDrawing(layerTwoStroke)
            XCTAssertEqual(viewModel.currentDrawing, layerTwoStroke)

            viewModel.undoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)
            XCTAssertEqual(viewModel.currentLayerStack.layers.count, 2)
            XCTAssertEqual(viewModel.currentLayerStack.activeLayerID, topLayerID)

            viewModel.undoLastEdit()
            XCTAssertEqual(viewModel.currentLayerStack.layers.count, 1)
            XCTAssertEqual(viewModel.currentLayerStack.activeLayerID, baseLayerID)
            XCTAssertEqual(viewModel.currentDrawing, layerOneStroke)

            viewModel.undoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.redoLastEdit()
            XCTAssertEqual(viewModel.currentDrawing, layerOneStroke)

            viewModel.redoLastEdit()
            XCTAssertEqual(viewModel.currentLayerStack.layers.count, 2)
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.redoLastEdit()
            XCTAssertEqual(viewModel.currentDrawing, layerTwoStroke)
        }
    }

    func testRedoStackClearsAfterBranchingEditInMixedTimeline() async {
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
            viewModel.isFillModeActive = true
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplyFill = await waitForCondition {
            await MainActor.run { viewModel.currentFillImage != nil }
        }
        XCTAssertTrue(didApplyFill, "Expected fill overlay to be applied.")

        await MainActor.run {
            viewModel.undoLastEdit()
            XCTAssertNil(viewModel.currentFillImage)
            XCTAssertTrue(viewModel.canRedoEdit)

            // New branch edit should clear redo history for the undone fill.
            viewModel.clearDrawing()
            XCTAssertFalse(viewModel.canRedoEdit)
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)

            viewModel.redoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)
            XCTAssertNil(viewModel.currentFillImage)
        }
    }

    func testInterruptedStrokeThenFillMaintainsUndoOrder() async {
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
            viewModel.updateStrokeInteraction(isActive: true)
            viewModel.updateDrawing(sampleDrawing)
            viewModel.isFillModeActive = true
            viewModel.handleFillTap(at: CGPoint(x: 0.5, y: 0.5))
        }

        let didApplyFill = await waitForCondition {
            await MainActor.run { viewModel.currentFillImage != nil }
        }
        XCTAssertTrue(didApplyFill, "Expected fill overlay to be applied.")

        await MainActor.run {
            viewModel.undoLastEdit()
            XCTAssertNil(viewModel.currentFillImage)
            XCTAssertEqual(viewModel.currentDrawing, sampleDrawing)

            viewModel.undoLastEdit()
            XCTAssertTrue(viewModel.currentDrawing.strokes.isEmpty)
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

    func testLayerStackMoveLayerReordersSortedLayersWithoutChangingActiveLayer() {
        var layerStack = LayerStack.singleLayer(name: "Layer 1")
        let baseLayerID = layerStack.activeLayerID
        let secondLayer = layerStack.addLayer(name: "Layer 2")
        let thirdLayer = layerStack.addLayer(name: "Layer 3")

        XCTAssertEqual(
            layerStack.sortedLayers.map(\.id),
            [baseLayerID, secondLayer.id, thirdLayer.id]
        )
        XCTAssertEqual(layerStack.activeLayerID, thirdLayer.id)

        layerStack.moveLayer(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(
            layerStack.sortedLayers.map(\.id),
            [thirdLayer.id, baseLayerID, secondLayer.id]
        )
        XCTAssertEqual(layerStack.activeLayerID, thirdLayer.id)
        XCTAssertEqual(layerStack.sortedLayers.map(\.order), [0, 1, 2])
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

    func testPersistenceRevisionStoreTracksLayerAndFillIndependently() {
        var store = TemplatePersistenceRevisionStore()
        let templateID = "template-1"

        XCTAssertEqual(store.nextLayerRevision(for: templateID), 1)
        XCTAssertEqual(store.nextLayerRevision(for: templateID), 2)
        XCTAssertEqual(store.nextFillRevision(for: templateID), 1)
        XCTAssertEqual(store.nextFillRevision(for: templateID), 2)
        XCTAssertEqual(store.nextLayerRevision(for: templateID), 3)
    }

    func testPersistenceRevisionStoreRenameRetainAndRemoveState() {
        var store = TemplatePersistenceRevisionStore()
        let oldTemplateID = "old-template"
        let renamedTemplateID = "renamed-template"
        let retainedTemplateID = "retained-template"
        let removedTemplateID = "removed-template"

        _ = store.nextLayerRevision(for: oldTemplateID)
        _ = store.nextFillRevision(for: oldTemplateID)
        _ = store.nextLayerRevision(for: retainedTemplateID)
        _ = store.nextFillRevision(for: removedTemplateID)

        store.renameRevisions(from: oldTemplateID, to: renamedTemplateID)
        XCTAssertEqual(store.nextLayerRevision(for: renamedTemplateID), 2)
        XCTAssertEqual(store.nextFillRevision(for: renamedTemplateID), 2)

        store.retainRevisions(for: Set([renamedTemplateID, retainedTemplateID]))
        XCTAssertEqual(store.nextLayerRevision(for: retainedTemplateID), 2)
        XCTAssertEqual(store.nextFillRevision(for: removedTemplateID), 1)

        store.removeRevisions(for: renamedTemplateID)
        XCTAssertEqual(store.nextLayerRevision(for: renamedTemplateID), 1)
        XCTAssertEqual(store.nextFillRevision(for: renamedTemplateID), 1)
    }

    @MainActor
    func testDeferredCloudRestoreRunnerStopsWhenReloadFails() async {
        var observedDelays: [UInt64] = []
        var reloadCount = 0

        await TemplateDeferredCloudRestoreRunner.performDeferredCloudRestore(
            retryDelays: [10, 20, 30],
            sleep: { delay in
                observedDelays.append(delay)
            },
            isCancelled: { false },
            reloadTemplates: {
                reloadCount += 1
                return false
            },
            hasImportedTemplates: { false }
        )

        XCTAssertEqual(observedDelays, [10])
        XCTAssertEqual(reloadCount, 1)
    }

    @MainActor
    func testDeferredCloudRestoreRunnerStopsWhenImportedTemplatesAppear() async {
        var observedDelays: [UInt64] = []
        var reloadCount = 0

        await TemplateDeferredCloudRestoreRunner.performDeferredCloudRestore(
            retryDelays: [10, 20, 30],
            sleep: { delay in
                observedDelays.append(delay)
            },
            isCancelled: { false },
            reloadTemplates: {
                reloadCount += 1
                return true
            },
            hasImportedTemplates: { reloadCount >= 2 }
        )

        XCTAssertEqual(observedDelays, [10, 20])
        XCTAssertEqual(reloadCount, 2)
    }

    func testReloadStateResolverKeepsCurrentSelectionWhenStillValid() {
        let templates = [
            Self.makeTemplate(id: "builtin-1", title: "Template One"),
            Self.makeTemplate(id: "builtin-2", title: "Template Two")
        ]

        let resolution = TemplateReloadStateResolver.resolve(
            loadedTemplates: templates,
            hiddenTemplateIDs: [],
            currentSelectedTemplateID: "builtin-2",
            lastSelectedTemplateID: "builtin-1",
            recentTemplateIDs: ["builtin-2", "missing-template"]
        )

        XCTAssertEqual(resolution.selectedTemplateID, "builtin-2")
        XCTAssertEqual(resolution.filteredRecentTemplateIDs, ["builtin-2"])
        XCTAssertEqual(resolution.validTemplateIDs, Set(["builtin-1", "builtin-2"]))
    }

    func testReloadStateResolverFallsBackToLastSelectedTemplate() {
        let templates = [
            Self.makeTemplate(id: "builtin-1", title: "Template One"),
            Self.makeTemplate(id: "builtin-2", title: "Template Two")
        ]

        let resolution = TemplateReloadStateResolver.resolve(
            loadedTemplates: templates,
            hiddenTemplateIDs: [],
            currentSelectedTemplateID: "missing-template",
            lastSelectedTemplateID: "builtin-1",
            recentTemplateIDs: []
        )

        XCTAssertEqual(resolution.selectedTemplateID, "builtin-1")
    }

    func testFillImageResolverUsesCachedImageWithoutDecoding() {
        let cachedImage = UIImage(data: sampleTemplateImageData)
        XCTAssertNotNil(cachedImage)

        var decodeCallCount = 0
        var cacheCallCount = 0
        let resolvedImage = TemplateFillImageResolver.resolveDisplayImage(
            fillData: Data("ignored".utf8),
            cachedImage: cachedImage,
            decodeImage: { _ in
                decodeCallCount += 1
                return nil
            },
            cacheImage: { _ in
                cacheCallCount += 1
            }
        )

        XCTAssertNotNil(resolvedImage)
        XCTAssertEqual(decodeCallCount, 0)
        XCTAssertEqual(cacheCallCount, 0)
    }

    func testFillImageResolverDecodesAndCachesWhenCacheIsEmpty() {
        var cacheCallCount = 0
        let resolvedImage = TemplateFillImageResolver.resolveDisplayImage(
            fillData: sampleTemplateImageData,
            cachedImage: nil,
            decodeImage: { data in
                UIImage(data: data)
            },
            cacheImage: { _ in
                cacheCallCount += 1
            }
        )

        XCTAssertNotNil(resolvedImage)
        XCTAssertEqual(cacheCallCount, 1)
    }

    func testBuiltInCategoryNamesComeFromManifestMetadataInsteadOfTitleHeuristics() {
        let template = Self.makeTemplate(
            id: "builtin-lake-como",
            title: "Lake Como",
            category: "Sci-Fi",
            shelfCategory: "scifi",
            complexity: "dense",
            canvasOrientation: .portrait
        )
        let categoryNames = TemplateCategory.builtInCategoryNames(for: template)
        XCTAssertEqual(categoryNames, Set(["Sci-Fi", "Dense", "Portrait"]))
        XCTAssertFalse(categoryNames.contains("Nature"))
    }

    func testPersistedDrawingLoaderReturnsLayerStackWhenAvailable() async throws {
        let drawingStore = StubTemplateDrawingStore()
        let templateID = "layer-template"
        let layerStack = LayerStack.singleLayer(drawingData: Data("layer-data".utf8))
        let encodedLayerStack = try JSONEncoder().encode(layerStack)
        try await drawingStore.saveLayerStackData(encodedLayerStack, for: templateID)

        let result = await TemplatePersistedDrawingLoader.load(
            for: templateID,
            drawingStore: drawingStore
        )

        guard case let .layerStack(restoredLayerStack) = result else {
            XCTFail("Expected layer-stack load result.")
            return
        }
        XCTAssertEqual(restoredLayerStack, layerStack)
    }

    func testPersistedDrawingLoaderFallsBackToLegacyDrawingData() async throws {
        let drawingStore = StubTemplateDrawingStore()
        let templateID = "legacy-template"
        let legacyDrawing = await MainActor.run { makeSampleTemplateDrawing() }
        let drawingData = legacyDrawing.dataRepresentation()
        try await drawingStore.saveDrawingData(drawingData, for: templateID)

        let result = await TemplatePersistedDrawingLoader.load(
            for: templateID,
            drawingStore: drawingStore
        )

        guard case let .migratedLegacyDrawing(restoredDrawing, restoredLayerStack) = result else {
            XCTFail("Expected legacy drawing migration result.")
            return
        }
        XCTAssertEqual(restoredDrawing.strokes.count, legacyDrawing.strokes.count)
        XCTAssertEqual(restoredLayerStack.activeLayer?.drawingData, drawingData)
    }

    func testPersistedDrawingLoaderStopsOnCorruptedLayerStackData() async throws {
        let drawingStore = StubTemplateDrawingStore()
        let templateID = "corrupted-layer-stack-template"
        try await drawingStore.saveLayerStackData(Data("invalid-json".utf8), for: templateID)

        let result = await TemplatePersistedDrawingLoader.load(
            for: templateID,
            drawingStore: drawingStore
        )

        guard case .corruptedLayerStack = result else {
            XCTFail("Expected corrupted layer-stack result.")
            return
        }
    }

    func testStrokeBoundaryResolverOnlySplitsWhenPendingStrokeCountIncreases() {
        XCTAssertTrue(
            TemplateStrokeBoundaryResolver.shouldSplitPendingStroke(
                hasPendingStroke: true,
                previousStrokeCount: 2,
                updatedStrokeCount: 3
            )
        )
        XCTAssertFalse(
            TemplateStrokeBoundaryResolver.shouldSplitPendingStroke(
                hasPendingStroke: false,
                previousStrokeCount: 2,
                updatedStrokeCount: 3
            )
        )
        XCTAssertFalse(
            TemplateStrokeBoundaryResolver.shouldSplitPendingStroke(
                hasPendingStroke: true,
                previousStrokeCount: 3,
                updatedStrokeCount: 3
            )
        )
    }

    func testLayerMergeServiceMergesUpperStrokesIntoLowerLayer() async {
        let lowerDrawing = await MainActor.run { makeSampleTemplateDrawing(color: .black) }
        let upperDrawing = await MainActor.run { makeSampleTemplateDrawing(color: .red) }
        var layerStack = LayerStack.singleLayer(drawingData: lowerDrawing.dataRepresentation())
        let upperLayer = layerStack.addLayer(name: "Layer 2")
        layerStack.updateDrawingData(upperDrawing.dataRepresentation(), for: upperLayer.id)
        guard let mergeSourceLayerID = layerStack.sortedLayers.first?.id else {
            XCTFail("Expected merge source layer.")
            return
        }

        guard let mergedLayerStack = TemplateLayerMergeService.mergeDown(
            in: layerStack,
            upperLayerID: mergeSourceLayerID
        ) else {
            XCTFail("Expected merge result.")
            return
        }

        XCTAssertEqual(mergedLayerStack.layers.count, 1)
        guard let mergedDrawingData = mergedLayerStack.activeLayer?.drawingData,
              let mergedDrawing = try? PKDrawing(data: mergedDrawingData)
        else {
            XCTFail("Expected merged drawing data.")
            return
        }

        XCTAssertEqual(
            mergedDrawing.strokes.count,
            lowerDrawing.strokes.count + upperDrawing.strokes.count
        )
    }

    func testManifestEntryDecodesNewKeysAndAppliesSafeDefaults() throws {
        let data = Data(
            """
            {
              "id": "cozy-room",
              "file": "landscape-99.png",
              "title": "Cozy Room",
              "category": "cozy"
            }
            """.utf8
        )

        let entry = try JSONDecoder().decode(TemplateLibraryService.ManifestEntry.self, from: data)

        XCTAssertEqual(entry.resolvedTemplateID, "cozy-room")
        XCTAssertEqual(entry.resolvedFileName, "landscape-99.png")
        XCTAssertEqual(entry.resolvedShelfCategory, "cozy")
        XCTAssertEqual(entry.resolvedComplexity, "medium")
        XCTAssertNil(entry.orientation)
        XCTAssertEqual(entry.resolvedMood, [])
        XCTAssertEqual(entry.resolvedSession, "standard")
        XCTAssertEqual(entry.resolvedLineWeight, "balanced")
        XCTAssertFalse(entry.resolvedFeatured)
    }

    func testManifestEntrySupportsLegacyFileNameAndGeneratedID() throws {
        let data = Data(
            """
            {
              "fileName": "portrait-24.png",
              "title": "Legacy Jacks",
              "category": "patterns",
              "complexity": "detailed",
              "orientation": "portrait",
              "mood": ["playful"],
              "session": "focus",
              "lineWeight": "fine",
              "featured": true
            }
            """.utf8
        )

        let entry = try JSONDecoder().decode(TemplateLibraryService.ManifestEntry.self, from: data)

        XCTAssertEqual(entry.resolvedTemplateID, "portrait-24")
        XCTAssertEqual(entry.resolvedFileName, "portrait-24.png")
        XCTAssertEqual(entry.resolvedShelfCategory, "patterns")
        XCTAssertEqual(entry.resolvedComplexity, "detailed")
        XCTAssertEqual(entry.orientation, .portrait)
        XCTAssertEqual(entry.resolvedMood, ["playful"])
        XCTAssertEqual(entry.resolvedSession, "focus")
        XCTAssertEqual(entry.resolvedLineWeight, "fine")
        XCTAssertTrue(entry.resolvedFeatured)
    }

    func testManifestEntryPreservesDenseComplexity() throws {
        let data = Data(
            """
            {
              "id": "scifi-test",
              "file": "Templates/BuiltIn/scifi/example.png",
              "title": "Sci-Fi Dense",
              "category": "scifi",
              "complexity": "dense"
            }
            """.utf8
        )

        let entry = try JSONDecoder().decode(TemplateLibraryService.ManifestEntry.self, from: data)

        XCTAssertEqual(entry.resolvedTemplateID, "scifi-test")
        XCTAssertEqual(entry.resolvedFileName, "Templates/BuiltIn/scifi/example.png")
        XCTAssertEqual(entry.resolvedShelfCategory, "scifi")
        XCTAssertEqual(entry.resolvedComplexity, "dense")
    }

    func testBuiltInManifestContainsExpectedExpanded80Pack() throws {
        let repoRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repoRootURL.appendingPathComponent("Coloring/Resources/Templates/template_manifest.json")
        let data = try Data(contentsOf: manifestURL)

        let rawManifest = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(rawManifest?.count, 80)

        let requiredKeys = Set(["id", "title", "category", "complexity", "orientation", "mood", "session", "lineWeight", "featured", "file"])
        rawManifest?.forEach { entry in
            XCTAssertEqual(Set(entry.keys), requiredKeys)
        }

        let decodedEntries = try JSONDecoder().decode([TemplateLibraryService.ManifestEntry].self, from: data)
        XCTAssertEqual(decodedEntries.count, 80)
        XCTAssertEqual(decodedEntries.first?.id, "cozy_001")
        XCTAssertEqual(decodedEntries.last?.id, "scifi_010")

        let categoryCounts = Dictionary(grouping: decodedEntries, by: \.category).mapValues(\.count)
        XCTAssertEqual(categoryCounts["cozy"], 10)
        XCTAssertEqual(categoryCounts["nature"], 10)
        XCTAssertEqual(categoryCounts["animals"], 10)
        XCTAssertEqual(categoryCounts["fantasy"], 10)
        XCTAssertEqual(categoryCounts["patterns"], 10)
        XCTAssertEqual(categoryCounts["seasonal"], 10)
        XCTAssertEqual(categoryCounts["motorsport"], 10)
        XCTAssertEqual(categoryCounts["scifi"], 10)
    }

    func testTemplateLibraryServiceResolvesManifestFilePathWhenBundleResourcesAreFlattened() async throws {
        let manifestData = Data(
            """
            [
              {
                "id": "fantasy_001",
                "title": "Mushroom Cottage",
                "category": "fantasy",
                "complexity": "easy",
                "orientation": "portrait",
                "mood": [],
                "session": "standard",
                "lineWeight": "balanced",
                "featured": false,
                "file": "Templates/BuiltIn/fantasy/fantasy_mushroom_cottage_easy_portrait.png"
              }
            ]
            """.utf8
        )
        let bundleURL = try makeTemporaryResourceBundle(
            resources: [
                ("template_manifest.json", manifestData),
                ("fantasy_mushroom_cottage_easy_portrait.png", sampleTemplateImageData)
            ]
        )
        guard let bundle = Bundle(url: bundleURL) else {
            XCTFail("Expected temporary test bundle.")
            return
        }

        let documentsURL = try makeTemporaryDocumentsDirectory()
        let service = TemplateLibraryService(
            bundle: bundle,
            documentsDirectoryURLProvider: { documentsURL },
            ubiquityContainerURLProvider: { _ in nil }
        )

        let templates = try await service.loadTemplates()
        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates.first?.id, "builtin-fantasy_001")
        XCTAssertEqual(templates.first?.title, "Mushroom Cottage")
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

    func testGalleryStoreServiceNormalizesTransparentArtworkToOpaqueWhite() async throws {
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let galleryURL = documentsURL.appendingPathComponent("GalleryTest", isDirectory: true)
        let store = makeRealGalleryStore(galleryURL: galleryURL)
        let transparentImageData = await MainActor.run {
            transparentTemplateImageData(size: CGSize(width: 24, height: 24))
        }

        let entry = try await store.saveArtwork(
            imageData: transparentImageData,
            sourceTemplateID: "builtin-1",
            sourceTemplateName: "Template One"
        )

        let fullImageURL = galleryURL.appendingPathComponent(entry.fullImageFilename)
        let thumbnailURL = galleryURL.appendingPathComponent(entry.thumbnailFilename)
        let fullImageData = try Data(contentsOf: fullImageURL)
        let thumbnailData = try Data(contentsOf: thumbnailURL)

        let fullSignature = await MainActor.run { imageSignature(from: fullImageData) }
        let thumbnailSignature = await MainActor.run { imageSignature(from: thumbnailData) }

        guard let fullSignature, fullSignature.count == 4 else {
            XCTFail("Expected full-size image signature.")
            return
        }
        guard let thumbnailSignature, thumbnailSignature.count == 4 else {
            XCTFail("Expected thumbnail image signature.")
            return
        }

        XCTAssertEqual(fullSignature[3], 255)
        XCTAssertGreaterThanOrEqual(fullSignature[0], 240)
        XCTAssertGreaterThanOrEqual(fullSignature[1], 240)
        XCTAssertGreaterThanOrEqual(fullSignature[2], 240)

        XCTAssertEqual(thumbnailSignature[3], 255)
        XCTAssertGreaterThanOrEqual(thumbnailSignature[0], 240)
        XCTAssertGreaterThanOrEqual(thumbnailSignature[1], 240)
        XCTAssertGreaterThanOrEqual(thumbnailSignature[2], 240)
    }

    func testGalleryStoreServiceSaveArtworkFailsClosedWhenManifestIsUnreadable() async throws {
        let fileManager = FileManager.default
        let documentsURL = try makeTemporaryDocumentsDirectory()
        let galleryURL = documentsURL.appendingPathComponent("GalleryTest", isDirectory: true)
        try fileManager.createDirectory(at: galleryURL, withIntermediateDirectories: true)

        let manifestURL = galleryURL.appendingPathComponent("manifest.json")
        let unreadableManifestData = Data("not valid json".utf8)
        try unreadableManifestData.write(to: manifestURL, options: .atomic)

        let store = makeRealGalleryStore(galleryURL: galleryURL)
        let imageData = await MainActor.run {
            solidColorTemplateImageData(.purple, size: CGSize(width: 32, height: 20))
        }

        do {
            _ = try await store.saveArtwork(
                imageData: imageData,
                sourceTemplateID: "builtin-1",
                sourceTemplateName: "Template One"
            )
            XCTFail("Expected saveArtwork to throw when manifest is unreadable.")
        } catch {
            // Expected.
        }

        let galleryItems = try fileManager.contentsOfDirectory(
            at: galleryURL,
            includingPropertiesForKeys: nil
        )
        let savedArtworkItems = galleryItems.filter { $0.pathExtension.lowercased() == "png" }
        XCTAssertTrue(savedArtworkItems.isEmpty, "Expected no newly saved artwork files.")

        let manifestDataAfterFailure = try Data(contentsOf: manifestURL)
        XCTAssertEqual(manifestDataAfterFailure, unreadableManifestData)
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

    func testStaleFillRestoreTaskDoesNotReapplyFillAfterErase() async {
        let template = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let templateImageData = await MainActor.run {
            solidColorTemplateImageData(.white, size: CGSize(width: 8, height: 8))
        }
        let initialFillData = await MainActor.run {
            solidColorTemplateImage(.red, size: CGSize(width: 8, height: 8)).pngData()
        }

        let drawingStore = StubTemplateDrawingStore()
        try? await drawingStore.saveFillData(XCTUnwrap(initialFillData), for: template.id)
        await drawingStore.enqueueFillLoadDelay(0.05)
        await drawingStore.enqueueFillLoadDelay(0.35)

        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(
                    templates: [template],
                    imageDataSequence: [templateImageData]
                ),
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
        Task {
            await viewModel.refreshTemplatesFromStorage()
        }

        let didRestoreFill = await waitForCondition(timeout: 1.0) {
            await MainActor.run {
                viewModel.currentFillImage != nil
            }
        }
        XCTAssertTrue(didRestoreFill, "Expected persisted fill to restore before erase.")

        await MainActor.run {
            viewModel.isFillModeActive = false
            viewModel.handleFillErase(at: CGPoint(x: 0.5, y: 0.5))
            XCTAssertNil(viewModel.currentFillImage)
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        await MainActor.run {
            XCTAssertNil(
                viewModel.currentFillImage,
                "Expected stale fill-restore work not to reapply erased fill."
            )
        }
    }

    func testColoringPersistenceCoordinatorSkipsStaleFillRevision() async throws {
        let templateID = "builtin-1"
        let store = StubTemplateDrawingStore()
        let coordinator = TemplateColoringPersistenceCoordinator(drawingStore: store)
        let newerFill = Data("newer-fill".utf8)
        let olderFill = Data("older-fill".utf8)

        await coordinator.persistFillData(newerFill, for: templateID, revision: 2)
        await coordinator.persistFillData(olderFill, for: templateID, revision: 1)

        let persistedFill = try await store.loadFillData(for: templateID)
        let fillSaveCount = await store.fillSaveCount(for: templateID)
        XCTAssertEqual(persistedFill, newerFill)
        XCTAssertEqual(fillSaveCount, 1)
    }

    func testClearingFillPersistsTombstoneAndDoesNotRestoreOldFillAfterSwitch() async {
        let firstTemplate = Self.makeTemplate(id: "builtin-1", title: "Template One")
        let secondTemplate = Self.makeTemplate(id: "builtin-2", title: "Template Two")
        let drawingStore = StubTemplateDrawingStore()
        let filledImage = await MainActor.run {
            solidColorTemplateImage(.red, size: CGSize(width: 8, height: 8))
        }
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: [firstTemplate, secondTemplate]),
                exportService: StubTemplateExportService(),
                drawingStore: drawingStore,
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
            await MainActor.run { viewModel.currentFillImage != nil }
        }
        XCTAssertTrue(didApplyFill, "Expected fill overlay before clear.")

        await MainActor.run {
            viewModel.clearFills()
            viewModel.selectTemplate(secondTemplate.id)
            viewModel.selectTemplate(firstTemplate.id)
        }

        let didPersistTombstone = await waitForCondition(timeout: 1.0) {
            (try? await drawingStore.loadFillData(for: firstTemplate.id)) == Data()
        }
        XCTAssertTrue(didPersistTombstone, "Expected cleared fill to persist as an empty-data tombstone.")

        let remainedClearedAfterSwitch = await waitForCondition(timeout: 1.0) {
            await MainActor.run {
                viewModel.selectedTemplateID == firstTemplate.id
                    && viewModel.currentFillImage == nil
                    && !viewModel.inProgressTemplateIDs.contains(firstTemplate.id)
            }
        }
        XCTAssertTrue(remainedClearedAfterSwitch, "Expected cleared fill to remain cleared after switching templates.")
        let fillDeleteCount = await drawingStore.fillDeleteCount(for: firstTemplate.id)
        XCTAssertEqual(fillDeleteCount, 0)
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

    func testExportCurrentTemplateWithoutSelectionSetsError() async {
        let exportService = CapturingTemplateExportService()
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: StubTemplateLibrary(templates: []),
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
        await viewModel.exportCurrentTemplate()

        let lastCanvasSize = await exportService.lastCanvasSize
        XCTAssertNil(lastCanvasSize)

        await MainActor.run {
            XCTAssertEqual(viewModel.exportErrorMessage, "No template selected to export.")
            XCTAssertFalse(viewModel.isExporting)
            XCTAssertNil(viewModel.exportedFileURL)
        }
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

    func testPencilCanvasCoordinatorUsesLightTraitsForDynamicStrokeNormalization() async {
        await MainActor.run {
            let drawingState = DrawingStateBox()
            drawingState.drawing = PKDrawing()

            let view = PencilCanvasView(
                templateImage: solidColorTemplateImage(.white),
                templateID: "builtin-1",
                drawing: Binding(
                    get: { drawingState.drawing },
                    set: { drawingState.drawing = $0 }
                )
            )

            let coordinator = view.makeCoordinator()
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                XCTFail("Expected a window scene for coordinator test host.")
                return
            }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
            window.overrideUserInterfaceStyle = .dark
            let hostController = UIViewController()
            window.rootViewController = hostController
            window.makeKeyAndVisible()

            let canvasView = PKCanvasView(frame: hostController.view.bounds)
            canvasView.overrideUserInterfaceStyle = .light
            hostController.view.addSubview(canvasView)
            hostController.view.layoutIfNeeded()

            canvasView.drawing = makeSampleTemplateDrawing(color: .label)
            coordinator.canvasViewDrawingDidChange(canvasView)

            guard let strokeColor = drawingState.drawing.strokes.first?.ink.color else {
                XCTFail("Expected a normalized stroke color.")
                window.isHidden = true
                return
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(strokeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            XCTAssertLessThan(
                luminance,
                0.3,
                "Expected dynamic label color to resolve using light-mode artwork traits."
            )

            window.isHidden = true
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

    func testDrawingExportSupportSelectedTemplateAspectRatioFallsBackForNilOrInvalidImage() {
        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.selectedTemplateAspectRatio(for: nil),
            4.0 / 3.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.selectedTemplateAspectRatio(for: UIImage()),
            4.0 / 3.0,
            accuracy: 0.0001
        )
    }

    func testDrawingExportSupportSelectedTemplateAspectRatioUsesImageDimensions() {
        let image = solidColorTemplateImage(.red, size: CGSize(width: 300, height: 150))

        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.selectedTemplateAspectRatio(for: image),
            2.0,
            accuracy: 0.0001
        )
    }

    func testDrawingExportSupportSerializedDrawingDataHandlesEmptyAndNonEmptyDrawings() {
        let emptyDrawing = PKDrawing()
        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.serializedDrawingData(for: emptyDrawing),
            Data()
        )

        let nonEmptyDrawing = makeSampleTemplateDrawing()
        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.serializedDrawingData(for: nonEmptyDrawing),
            nonEmptyDrawing.dataRepresentation()
        )
    }

    func testDrawingExportSupportBestExportSizeFallsBackAndPreservesSmallImages() {
        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.bestExportSize(for: nil),
            CGSize(width: 2048, height: 1536)
        )
        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.bestExportSize(for: UIImage()),
            CGSize(width: 2048, height: 1536)
        )

        let smallImage = solidColorTemplateImage(.blue, size: CGSize(width: 1200, height: 900))
        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.bestExportSize(for: smallImage),
            CGSize(width: 1200, height: 900)
        )
    }

    func testDrawingExportSupportBestExportSizeScalesDownLargeImagesToMaxLongEdge() {
        let largeImage = solidColorTemplateImage(.green, size: CGSize(width: 4096, height: 2048))

        XCTAssertEqual(
            TemplateStudioDrawingExportSupport.bestExportSize(for: largeImage),
            CGSize(width: 2048, height: 1024)
        )
    }

    func testImportedTemplateNamingSupportSanitizedFilenameNormalizesWhitespaceAndSymbols() {
        XCTAssertEqual(
            TemplateImportedTemplateNamingSupport.sanitizedFilename("  My   Cool*&% Drawing!!  "),
            "my-cool-drawing"
        )
        XCTAssertEqual(
            TemplateImportedTemplateNamingSupport.sanitizedFilename("!!!___"),
            "imported-drawing"
        )
    }

    func testImportedTemplateNamingSupportUUIDSuffixExtractionMatchesTrailingUUIDOnly() {
        XCTAssertEqual(
            TemplateImportedTemplateNamingSupport.uuidSuffix(
                from: "my-drawing-123e4567-e89b-12d3-a456-426614174000"
            ),
            "-123e4567-e89b-12d3-a456-426614174000"
        )
        XCTAssertNil(
            TemplateImportedTemplateNamingSupport.uuidSuffix(
                from: "my-drawing-123e4567-e89b-12d3-a456-426614174000-copy"
            )
        )
    }

    func testImportedTemplateNamingSupportHumanReadableTitleStripsUUIDAndExtension() {
        XCTAssertEqual(
            TemplateImportedTemplateNamingSupport.humanReadableTitle(
                from: "my-drawing-123e4567-e89b-12d3-a456-426614174000.png"
            ),
            "My Drawing"
        )
        XCTAssertEqual(
            TemplateImportedTemplateNamingSupport.humanReadableTitle(from: "line-art.png"),
            "Line Art"
        )
    }

    func testCategoryMutationSupportDeletingCategoryStateRemovesCategoryOrderAssignmentsAndSelectedFilter() {
        let firstCategory = TemplateCategory(id: "user-1", name: "One", isUserCreated: true)
        let secondCategory = TemplateCategory(id: "user-2", name: "Two", isUserCreated: true)
        let result = TemplateCategoryMutationSupport.deletingCategoryState(
            categoryID: "user-1",
            userCategories: [firstCategory, secondCategory],
            categoryOrder: ["user-1", "user-2", "builtin-landscape"],
            categoryAssignments: ["template-a": "user-1", "template-b": "user-2"],
            selectedCategoryFilter: "user-1"
        )

        XCTAssertEqual(result.userCategories.map(\.id), ["user-2"])
        XCTAssertEqual(result.categoryOrder, ["user-2", "builtin-landscape"])
        XCTAssertNil(result.categoryAssignments["template-a"])
        XCTAssertEqual(result.categoryAssignments["template-b"], "user-2")
        XCTAssertEqual(result.selectedCategoryFilter, TemplateCategory.allCategory.id)
    }

    func testCategoryMutationSupportDeletingCategoryStatePreservesUnrelatedSelectedFilter() {
        let firstCategory = TemplateCategory(id: "user-1", name: "One", isUserCreated: true)
        let secondCategory = TemplateCategory(id: "user-2", name: "Two", isUserCreated: true)
        let result = TemplateCategoryMutationSupport.deletingCategoryState(
            categoryID: "user-1",
            userCategories: [firstCategory, secondCategory],
            categoryOrder: ["user-1", "user-2"],
            categoryAssignments: ["template-a": "user-1"],
            selectedCategoryFilter: "user-2"
        )

        XCTAssertEqual(result.selectedCategoryFilter, "user-2")
        XCTAssertEqual(result.userCategories.map(\.id), ["user-2"])
    }

    func testCategoryMutationSupportMovedCategoryOrderHandlesMultiIndexMoveWithAdjustedDestination() {
        let categories = [
            TemplateCategory(id: "a", name: "A", isUserCreated: true),
            TemplateCategory(id: "b", name: "B", isUserCreated: true),
            TemplateCategory(id: "c", name: "C", isUserCreated: true),
            TemplateCategory(id: "d", name: "D", isUserCreated: true),
            TemplateCategory(id: "e", name: "E", isUserCreated: true)
        ]

        let reorderedIDs = TemplateCategoryMutationSupport.movedCategoryOrder(
            reorderableCategories: categories,
            source: IndexSet([1, 2]),
            destination: 4
        )

        XCTAssertEqual(reorderedIDs, ["a", "d", "b", "c", "e"])
    }

    func testCategoryMutationSupportAssigningTemplateAddsAndRemovesCategoryAssignment() {
        let startingAssignments = ["template-a": "user-1"]
        let assigned = TemplateCategoryMutationSupport.assigningTemplate(
            "template-b",
            to: "user-2",
            in: startingAssignments
        )
        XCTAssertEqual(assigned["template-a"], "user-1")
        XCTAssertEqual(assigned["template-b"], "user-2")

        let unassigned = TemplateCategoryMutationSupport.assigningTemplate(
            "template-a",
            to: nil,
            in: assigned
        )
        XCTAssertNil(unassigned["template-a"])
        XCTAssertEqual(unassigned["template-b"], "user-2")
    }

    func testCategoryMutationSupportToggledMembershipAddsThenRemovesTemplateID() {
        let added = TemplateCategoryMutationSupport.toggledMembership(
            of: "template-1",
            in: []
        )
        XCTAssertEqual(added, Set(["template-1"]))

        let removed = TemplateCategoryMutationSupport.toggledMembership(
            of: "template-1",
            in: added
        )
        XCTAssertTrue(removed.isEmpty)
    }

    func testCategoryMutationSupportHideTemplateSetMutationsInsertRemoveAndClearIDs() {
        let inserted = TemplateCategoryMutationSupport.insertingTemplateID("template-b", into: Set(["template-a"]))
        XCTAssertEqual(inserted, Set(["template-a", "template-b"]))

        let removed = TemplateCategoryMutationSupport.removingTemplateID("template-b", from: inserted)
        XCTAssertEqual(removed, Set(["template-a"]))

        let cleared = TemplateCategoryMutationSupport.clearingTemplateIDs()
        XCTAssertTrue(cleared.isEmpty)
    }

    private static func makeTemplate(
        id: String,
        title: String,
        source: ColoringTemplate.Source = .builtIn,
        category: String? = nil,
        shelfCategory: String? = nil,
        complexity: String? = nil,
        canvasOrientation: ColoringTemplate.CanvasOrientation = .any
    ) -> ColoringTemplate {
        let resolvedCategory = source == .builtIn ? (category ?? "Cozy") : "Imported"
        let resolvedShelfCategory = source == .builtIn ? (shelfCategory ?? "cozy") : nil
        let resolvedComplexity = source == .builtIn ? (complexity ?? "medium") : nil

        return ColoringTemplate(
            id: id,
            title: title,
            category: resolvedCategory,
            source: source,
            filePath: "/tmp/\(id).png",
            canvasOrientation: canvasOrientation,
            shelfCategory: resolvedShelfCategory,
            complexity: resolvedComplexity,
            mood: source == .builtIn ? [] : nil,
            session: source == .builtIn ? "standard" : nil,
            lineWeight: source == .builtIn ? "balanced" : nil,
            featured: source == .builtIn ? false : nil
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
    private func transparentTemplateImageData(
        size imageSize: CGSize = CGSize(width: 2, height: 2)
    ) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        let transparentImage = renderer.image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: imageSize))
        }
        return transparentImage.pngData() ?? sampleTemplateImageData
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
        makeSampleTemplateDrawing(color: .black)
    }

    @MainActor
    private func makeSampleTemplateDrawing(color: UIColor) -> PKDrawing {
        let ink = PKInk(.pen, color: color)
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

    private func makeTemporaryResourceBundle(resources: [(String, Data)]) throws -> URL {
        let rootDirectoryURL = try makeTemporaryDocumentsDirectory()
        let bundleURL = rootDirectoryURL.appendingPathComponent("TestResources.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "dn.coloring.tests.resources",
            "CFBundleName": "TestResources",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: bundleURL.appendingPathComponent("Info.plist"), options: [.atomic])

        for (relativePath, data) in resources {
            let destinationURL = bundleURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: [.atomic])
        }

        return bundleURL
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
    private var fillLoadDelays: [TimeInterval] = []
    private var fillSaveCountByTemplateID: [String: Int] = [:]
    private var fillDeleteCountByTemplateID: [String: Int] = [:]

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
        if !fillLoadDelays.isEmpty {
            let delay = fillLoadDelays.removeFirst()
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
        return fillDataByTemplateID[templateID]
    }

    func saveFillData(_ fillData: Data, for templateID: String) throws {
        fillDataByTemplateID[templateID] = fillData
        fillSaveCountByTemplateID[templateID, default: 0] += 1
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
        fillDeleteCountByTemplateID[templateID, default: 0] += 1
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

    func enqueueFillLoadDelay(_ delay: TimeInterval) {
        fillLoadDelays.append(delay)
    }

    func fillSaveCount(for templateID: String) -> Int {
        fillSaveCountByTemplateID[templateID, default: 0]
    }

    func fillDeleteCount(for templateID: String) -> Int {
        fillDeleteCountByTemplateID[templateID, default: 0]
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
    private var hidden: Set<String> = []

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

    func loadHiddenTemplateIDs() throws -> Set<String> {
        hidden
    }

    func saveHiddenTemplateIDs(_ templateIDs: Set<String>) throws {
        hidden = templateIDs
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
