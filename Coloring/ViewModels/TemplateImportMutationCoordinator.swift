import Foundation

final class TemplateImportMutationCoordinator {
    private let templateLibrary: any TemplateLibraryProviding
    private let drawingStore: any TemplateDrawingStoreProviding

    init(
        templateLibrary: any TemplateLibraryProviding,
        drawingStore: any TemplateDrawingStoreProviding
    ) {
        self.templateLibrary = templateLibrary
        self.drawingStore = drawingStore
    }

    func importTemplate(imageData: Data, suggestedName: String?) async throws -> ColoringTemplate {
        try await templateLibrary.importTemplate(imageData: imageData, preferredName: suggestedName)
    }

    func renameTemplate(templateID: String, newTitle: String) async throws -> ColoringTemplate {
        let renamedTemplate = try await templateLibrary.renameImportedTemplate(
            id: templateID,
            newTitle: newTitle
        )
        try await drawingStore.renameDrawingData(from: templateID, to: renamedTemplate.id)
        try await drawingStore.renameFillData(from: templateID, to: renamedTemplate.id)
        try await drawingStore.renameLayerStackData(from: templateID, to: renamedTemplate.id)
        return renamedTemplate
    }

    func deleteTemplate(templateID: String) async throws {
        try await templateLibrary.deleteImportedTemplate(id: templateID)
        try await drawingStore.deleteDrawingData(for: templateID)
        try await drawingStore.deleteFillData(for: templateID)
        try await drawingStore.deleteLayerStackData(for: templateID)
    }

    func deleteAllImportedTemplates(templateIDs: [String]) async throws {
        try await templateLibrary.deleteAllImportedTemplates()
        for templateID in templateIDs {
            try await drawingStore.deleteDrawingData(for: templateID)
            try await drawingStore.deleteFillData(for: templateID)
            try await drawingStore.deleteLayerStackData(for: templateID)
        }
    }
}
