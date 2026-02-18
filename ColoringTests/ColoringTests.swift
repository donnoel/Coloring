import CoreGraphics
import Foundation
import PencilKit
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
                exportService: StubTemplateExportService()
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
                exportService: StubTemplateExportService()
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

    func testTemplateRenameKeepsTemplateSelected() async {
        let importedTemplate = Self.makeTemplate(
            id: "imported-1",
            title: "Old Name",
            source: .imported
        )
        let library = StubTemplateLibrary(templates: [importedTemplate])
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService()
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
        let library = StubTemplateLibrary(templates: [builtInTemplate, importedTemplate])
        let viewModel = await MainActor.run {
            TemplateStudioViewModel(
                templateLibrary: library,
                exportService: StubTemplateExportService()
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
    private var templates: [ColoringTemplate]

    init(templates: [ColoringTemplate]) {
        self.templates = templates
    }

    func loadTemplates() throws -> [ColoringTemplate] {
        templates
    }

    func imageData(for _: ColoringTemplate) throws -> Data {
        sampleTemplateImageData
    }

    func importTemplate(imageData _: Data, preferredName: String?) throws -> ColoringTemplate {
        let filenameTitle = preferredName ?? "Imported Drawing"
        let imported = ColoringTemplate(
            id: "imported-\(templates.count + 1)",
            title: filenameTitle,
            category: "Imported",
            source: .imported,
            filePath: "/tmp/imported-\(templates.count + 1).png"
        )
        templates.append(imported)
        return imported
    }

    func renameImportedTemplate(id: String, newTitle: String) throws -> ColoringTemplate {
        guard let index = templates.firstIndex(where: { $0.id == id && $0.source == .imported }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let renamed = ColoringTemplate(
            id: id,
            title: newTitle,
            category: "Imported",
            source: .imported,
            filePath: "/tmp/\(id)-renamed.png"
        )
        templates[index] = renamed
        return renamed
    }

    func deleteImportedTemplate(id: String) throws {
        guard let index = templates.firstIndex(where: { $0.id == id && $0.source == .imported }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        templates.remove(at: index)
    }
}

private let sampleTemplateImageData = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/w8AAgMBgGd9mKsAAAAASUVORK5CYII="
)!

private struct StubTemplateExportService: TemplateArtworkExporting {
    func exportPNG(
        templateData _: Data,
        drawingData _: Data,
        canvasSize _: CGSize,
        templateID _: String
    ) async throws -> URL {
        URL(fileURLWithPath: "/tmp/template-export.png")
    }
}
