import Foundation
import PencilKit

struct TemplateEditSnapshot: Equatable {
    let layerStack: LayerStack
    let fillData: Data?
}

enum TemplateEditSnapshotResolver {
    static func makeSnapshot(
        templateID: String,
        selectedTemplateID: String,
        currentLayerStack: LayerStack,
        layerStacksByTemplateID: [String: LayerStack],
        drawingsByTemplateID: [String: PKDrawing],
        fillData: Data?,
        serializeDrawing: (PKDrawing) -> Data
    ) -> TemplateEditSnapshot? {
        guard !templateID.isEmpty else {
            return nil
        }

        let layerStack = layerStacksByTemplateID[templateID]
            ?? {
                if templateID == selectedTemplateID {
                    return currentLayerStack
                }

                let drawingData = serializeDrawing(drawingsByTemplateID[templateID] ?? PKDrawing())
                return LayerStack.singleLayer(drawingData: drawingData)
            }()

        return TemplateEditSnapshot(
            layerStack: layerStack,
            fillData: fillData
        )
    }

    static func drawing(from layerStack: LayerStack) -> PKDrawing {
        guard let activeLayer = layerStack.activeLayer,
              !activeLayer.drawingData.isEmpty,
              let drawing = try? PKDrawing(data: activeLayer.drawingData)
        else {
            return PKDrawing()
        }

        return drawing
    }
}
