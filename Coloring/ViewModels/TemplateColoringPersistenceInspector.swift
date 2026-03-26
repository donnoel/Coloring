import Foundation
import PencilKit

actor TemplateColoringPersistenceInspector {
    private let drawingStore: any TemplateDrawingStoreProviding

    init(drawingStore: any TemplateDrawingStoreProviding) {
        self.drawingStore = drawingStore
    }

    func hasPersistedColoring(for templateID: String) async -> Bool {
        do {
            if let layerStackData = try await drawingStore.loadLayerStackData(for: templateID),
               let layerStack = try? JSONDecoder().decode(LayerStack.self, from: layerStackData),
               Self.hasStrokeColoring(layerStack: layerStack, drawing: nil)
            {
                return true
            }

            if let drawingData = try await drawingStore.loadDrawingData(for: templateID),
               Self.drawingDataContainsVisibleStrokes(drawingData)
            {
                return true
            }

            if let fillData = try await drawingStore.loadFillData(for: templateID) {
                return !fillData.isEmpty
            }
        } catch {
            return false
        }

        return false
    }

    static func hasColoring(
        layerStack: LayerStack?,
        drawing: PKDrawing?,
        fillData: Data?
    ) -> Bool {
        hasStrokeColoring(layerStack: layerStack, drawing: drawing)
            || hasFillColoring(fillData: fillData)
    }

    static func hasStrokeColoring(layerStack: LayerStack?, drawing: PKDrawing?) -> Bool {
        if let layerStack {
            return layerStack.layers.contains { drawingDataContainsVisibleStrokes($0.drawingData) }
        }

        if let drawing {
            return !drawing.strokes.isEmpty
        }

        return false
    }

    static func hasFillColoring(fillData: Data?) -> Bool {
        guard let fillData else {
            return false
        }

        return !fillData.isEmpty
    }

    static func drawingDataContainsVisibleStrokes(_ drawingData: Data) -> Bool {
        guard !drawingData.isEmpty else {
            return false
        }

        guard let drawing = try? PKDrawing(data: drawingData) else {
            return true
        }

        return !drawing.strokes.isEmpty
    }
}
