import CoreGraphics
import Foundation

struct TemplateExportRequest {
    let templateData: Data
    let drawingData: Data
    let fillLayerData: Data?
    let compositedLayersImageData: Data?
    let canvasSize: CGSize
    let templateID: String
    let templateName: String
}

struct TemplateExportState: Equatable {
    var statusMessage: String?
    var errorMessage: String?
    var exportedFileURL: URL?
    var isExporting: Bool = false
}

@MainActor
final class TemplateExportCoordinator {
    enum StartResult {
        case alreadyExporting
        case missingTemplate
        case started(ColoringTemplate)
    }

    private let exportService: any TemplateArtworkExporting
    private let galleryStore: any GalleryStoreProviding
    private(set) var state = TemplateExportState()

    init(
        exportService: any TemplateArtworkExporting,
        galleryStore: any GalleryStoreProviding
    ) {
        self.exportService = exportService
        self.galleryStore = galleryStore
    }

    func beginExport(selectedTemplate: ColoringTemplate?) -> StartResult {
        guard !state.isExporting else {
            return .alreadyExporting
        }

        guard let selectedTemplate else {
            state.errorMessage = "No template selected to export."
            return .missingTemplate
        }

        state.isExporting = true
        state.errorMessage = nil
        return .started(selectedTemplate)
    }

    func completeExportSuccess(exportedURL: URL) {
        state.isExporting = false
        state.exportedFileURL = exportedURL
        state.statusMessage = "Template export is ready to share."
        state.errorMessage = nil
    }

    func completeExportFailure(_ error: Error) {
        state.isExporting = false
        state.errorMessage = error.localizedDescription
        state.statusMessage = nil
        state.exportedFileURL = nil
    }

    func invalidate() {
        state.exportedFileURL = nil
        state.statusMessage = nil
        state.errorMessage = nil
    }

    func performExport(using request: TemplateExportRequest) async throws -> URL {
        let exportedURL = try await exportService.exportPNG(
            templateData: request.templateData,
            drawingData: request.drawingData,
            fillLayerData: request.fillLayerData,
            compositedLayersImageData: request.compositedLayersImageData,
            canvasSize: request.canvasSize,
            templateID: request.templateID
        )

        // Gallery save is best-effort; don't fail the export.
        do {
            let exportImageData = try Data(contentsOf: exportedURL)
            _ = try await galleryStore.saveArtwork(
                imageData: exportImageData,
                sourceTemplateID: request.templateID,
                sourceTemplateName: request.templateName
            )
        } catch {
            // Intentionally ignored.
        }

        return exportedURL
    }

    nonisolated func cleanUpStaleExportFiles() {
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
}
