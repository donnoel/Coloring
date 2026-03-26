import Foundation
import PencilKit

enum TemplatePersistedDrawingLoadResult {
    case none
    case layerStack(LayerStack)
    case migratedLegacyDrawing(drawing: PKDrawing, layerStack: LayerStack)
    case corruptedLayerStack
    case corruptedLegacyDrawing
    case drawingReadFailed
}

enum TemplatePersistedDrawingLoader {
    static func load(
        for templateID: String,
        drawingStore: any TemplateDrawingStoreProviding
    ) async -> TemplatePersistedDrawingLoadResult {
        do {
            if let layerStackData = try await drawingStore.loadLayerStackData(for: templateID) {
                guard let layerStack = try? JSONDecoder().decode(LayerStack.self, from: layerStackData) else {
                    return .corruptedLayerStack
                }

                return .layerStack(layerStack)
            }
        } catch {
            // Fall through to legacy loading.
        }

        do {
            guard let drawingData = try await drawingStore.loadDrawingData(for: templateID) else {
                return .none
            }

            guard let drawing = try? PKDrawing(data: drawingData) else {
                return .corruptedLegacyDrawing
            }

            return .migratedLegacyDrawing(
                drawing: drawing,
                layerStack: LayerStack.singleLayer(drawingData: drawingData)
            )
        } catch {
            return .drawingReadFailed
        }
    }
}
