import PencilKit

enum TemplateLayerMergeService {
    static func mergeDown(in layerStack: LayerStack, upperLayerID: UUID) -> LayerStack? {
        var mergedLayerStack = layerStack
        guard let pair = mergedLayerStack.mergeDown(upperLayerID) else {
            return nil
        }

        if let mergedDrawingData = mergedDrawingData(
            lowerDrawingData: pair.lower.drawingData,
            upperDrawingData: pair.upper.drawingData
        ) {
            mergedLayerStack.updateDrawingData(mergedDrawingData, for: pair.lower.id)
        }

        mergedLayerStack.removeLayer(upperLayerID)
        return mergedLayerStack
    }

    private static func mergedDrawingData(
        lowerDrawingData: Data,
        upperDrawingData: Data
    ) -> Data? {
        guard let upperDrawing = try? PKDrawing(data: upperDrawingData),
              let lowerDrawing = try? PKDrawing(data: lowerDrawingData)
        else {
            return nil
        }

        var mergedStrokes = lowerDrawing.strokes
        mergedStrokes.append(contentsOf: upperDrawing.strokes)
        return PKDrawing(strokes: mergedStrokes).dataRepresentation()
    }
}
