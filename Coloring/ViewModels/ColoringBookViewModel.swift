import CoreGraphics
import Combine
import Foundation

@MainActor
final class ColoringBookViewModel: ObservableObject {
    @Published private(set) var scenes: [ColoringScene]
    @Published var selectedSceneID: String
    @Published var selectedColorID: String
    @Published private(set) var sceneColorsBySceneID: [String: [String: ColoringColor]]
    @Published private(set) var exportedFileURL: URL?
    @Published private(set) var exportStatusMessage: String?
    @Published private(set) var exportErrorMessage: String?
    @Published private(set) var isExporting: Bool

    let palette: [ColoringColor]

    private let exportService: any ArtworkExporting

    init(
        sceneCatalog: any SceneCatalogProviding,
        exportService: any ArtworkExporting,
        palette: [ColoringColor]
    ) {
        let loadedScenes = sceneCatalog.loadScenes()
        self.scenes = loadedScenes
        self.selectedSceneID = loadedScenes.first?.id ?? ""
        self.palette = palette
        self.selectedColorID = palette.first?.id ?? ColoringColor.defaultColorID
        self.sceneColorsBySceneID = [:]
        self.exportedFileURL = nil
        self.exportStatusMessage = nil
        self.exportErrorMessage = nil
        self.isExporting = false
        self.exportService = exportService
    }

    convenience init() {
        self.init(
            sceneCatalog: SceneCatalogService(),
            exportService: ArtworkExportService(),
            palette: ColoringColor.palette
        )
    }

    var selectedScene: ColoringScene? {
        scenes.first { $0.id == selectedSceneID }
    }

    var selectedColor: ColoringColor? {
        palette.first { $0.id == selectedColorID }
    }

    var currentSceneRegionColors: [String: ColoringColor] {
        sceneColorsBySceneID[selectedSceneID] ?? [:]
    }

    var canClearCurrentScene: Bool {
        !currentSceneRegionColors.isEmpty
    }

    func selectScene(_ sceneID: String) {
        guard scenes.contains(where: { $0.id == sceneID }) else {
            return
        }

        selectedSceneID = sceneID
        invalidateCurrentExport()
    }

    func selectColor(_ colorID: String) {
        guard palette.contains(where: { $0.id == colorID }) else {
            return
        }

        selectedColorID = colorID
    }

    func applyColor(to regionID: String) {
        guard let selectedColor else {
            return
        }

        var colors = sceneColorsBySceneID[selectedSceneID] ?? [:]
        colors[regionID] = selectedColor
        sceneColorsBySceneID[selectedSceneID] = colors
        invalidateCurrentExport()
    }

    func colorForRegion(_ regionID: String) -> ColoringColor? {
        currentSceneRegionColors[regionID]
    }

    func clearCurrentScene() {
        sceneColorsBySceneID[selectedSceneID] = [:]
        invalidateCurrentExport()
    }

    func exportCurrentScene() async {
        await exportCurrentScene(canvasSize: ColoringScene.defaultExportSize)
    }

    func exportCurrentScene(canvasSize: CGSize) async {
        guard !isExporting else {
            return
        }

        guard let selectedScene else {
            exportErrorMessage = "No scene selected to export."
            return
        }

        isExporting = true
        exportErrorMessage = nil

        do {
            let url = try await exportService.exportPNG(
                scene: selectedScene,
                regionColors: currentSceneRegionColors,
                canvasSize: canvasSize
            )
            exportedFileURL = url
            exportStatusMessage = "Export is ready to share."
        } catch {
            exportErrorMessage = error.localizedDescription
            exportStatusMessage = nil
            exportedFileURL = nil
        }

        isExporting = false
    }

    private func invalidateCurrentExport() {
        exportedFileURL = nil
        exportStatusMessage = nil
        exportErrorMessage = nil
    }
}
