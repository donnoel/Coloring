import Combine
import Foundation
import PencilKit
import UIKit

@MainActor
final class TemplateStudioViewModel: ObservableObject {
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

    private var drawingsByTemplateID: [String: PKDrawing] = [:]
    private let templateLibrary: any TemplateLibraryProviding
    private let exportService: any TemplateArtworkExporting
    private var hasLoadedTemplates = false

    init(
        templateLibrary: any TemplateLibraryProviding,
        exportService: any TemplateArtworkExporting
    ) {
        self.templateLibrary = templateLibrary
        self.exportService = exportService
        self.currentDrawing = PKDrawing()
    }

    convenience init() {
        self.init(
            templateLibrary: TemplateLibraryService(),
            exportService: TemplateArtworkExportService()
        )
    }

    var selectedTemplate: ColoringTemplate? {
        templates.first { $0.id == selectedTemplateID }
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

    func loadTemplatesIfNeeded() async {
        guard !hasLoadedTemplates else {
            return
        }

        hasLoadedTemplates = true
        await reloadTemplates()
    }

    func reloadTemplates() async {
        do {
            let loadedTemplates = try await templateLibrary.loadTemplates()
            templates = loadedTemplates
            importErrorMessage = nil

            if selectedTemplateID.isEmpty || !templates.contains(where: { $0.id == selectedTemplateID }) {
                selectedTemplateID = templates.first?.id ?? ""
            }

            restoreDrawingForSelectedTemplate()
            await loadSelectedTemplateImage()
        } catch {
            importErrorMessage = "Could not load templates: \(error.localizedDescription)"
        }
    }

    func selectTemplate(_ templateID: String) {
        guard templates.contains(where: { $0.id == templateID }) else {
            return
        }

        persistCurrentDrawing()
        selectedTemplateID = templateID

        if let savedDrawing = drawingsByTemplateID[templateID] {
            currentDrawing = savedDrawing
        } else {
            currentDrawing = PKDrawing()
        }

        Task {
            await loadSelectedTemplateImage()
        }

        invalidateExport()
    }

    func updateDrawing(_ drawing: PKDrawing) {
        currentDrawing = drawing
        drawingsByTemplateID[selectedTemplateID] = drawing
        invalidateExport()
    }

    func clearDrawing() {
        currentDrawing = PKDrawing()
        drawingsByTemplateID[selectedTemplateID] = currentDrawing
        invalidateExport()
    }

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

            if let drawing = drawingsByTemplateID.removeValue(forKey: templateID) {
                drawingsByTemplateID[renamedTemplate.id] = drawing
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
            drawingsByTemplateID.removeValue(forKey: templateID)

            await reloadTemplates()
            invalidateExport()
            importStatusMessage = "Drawing deleted."
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func reportImportFailure(_ message: String) {
        importErrorMessage = message
        importStatusMessage = nil
    }

    func exportCurrentTemplate() async {
        guard !isExporting else {
            return
        }

        guard let selectedTemplate else {
            exportErrorMessage = "No template selected to export."
            return
        }

        do {
            let templateData = try await templateLibrary.imageData(for: selectedTemplate)
            isExporting = true
            exportErrorMessage = nil

            let canvasSize = bestExportSize(for: selectedTemplateImage)
            let drawingData = currentDrawing.dataRepresentation()

            let exportedURL = try await exportService.exportPNG(
                templateData: templateData,
                drawingData: drawingData,
                canvasSize: canvasSize,
                templateID: selectedTemplate.id
            )

            exportedFileURL = exportedURL
            exportStatusMessage = "Template export is ready to share."
        } catch {
            exportErrorMessage = error.localizedDescription
            exportStatusMessage = nil
            exportedFileURL = nil
        }

        isExporting = false
    }

    private func loadSelectedTemplateImage() async {
        guard let selectedTemplate else {
            selectedTemplateImage = nil
            return
        }

        do {
            let templateData = try await templateLibrary.imageData(for: selectedTemplate)
            selectedTemplateImage = UIImage(data: templateData)
        } catch {
            selectedTemplateImage = nil
            importErrorMessage = "Could not load selected template image."
        }
    }

    private func persistCurrentDrawing() {
        guard !selectedTemplateID.isEmpty else {
            return
        }

        drawingsByTemplateID[selectedTemplateID] = currentDrawing
    }

    private func restoreDrawingForSelectedTemplate() {
        guard !selectedTemplateID.isEmpty else {
            currentDrawing = PKDrawing()
            return
        }

        currentDrawing = drawingsByTemplateID[selectedTemplateID] ?? PKDrawing()
    }

    private func bestExportSize(for image: UIImage?) -> CGSize {
        guard let image else {
            return CGSize(width: 2048, height: 1536)
        }

        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: 2048, height: 1536)
        }

        if size.width >= size.height {
            return CGSize(width: 2048, height: max(1536, (2048 / (size.width / size.height)).rounded()))
        }

        return CGSize(width: max(1536, (2048 * (size.width / size.height)).rounded()), height: 2048)
    }

    private func invalidateExport() {
        exportedFileURL = nil
        exportStatusMessage = nil
        exportErrorMessage = nil
    }
}
