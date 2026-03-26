import Foundation
import PencilKit
import UIKit

enum TemplateColorNormalization {
    static func normalizedDrawingData(_ drawingData: Data, using traitCollection: UITraitCollection?) -> Data {
        guard !drawingData.isEmpty,
              let drawing = try? PKDrawing(data: drawingData)
        else {
            return drawingData
        }

        let normalizedDrawing = drawing.stableColorDrawing(using: traitCollection)
        guard normalizedDrawing != drawing else {
            return drawingData
        }

        return normalizedDrawing.dataRepresentation()
    }

    static func normalizedLayerStack(_ layerStack: LayerStack, using traitCollection: UITraitCollection?) -> LayerStack {
        var normalizedLayerStack = layerStack
        var didChange = false

        normalizedLayerStack.layers = layerStack.layers.map { layer in
            let normalizedDrawingData = normalizedDrawingData(layer.drawingData, using: traitCollection)
            guard normalizedDrawingData != layer.drawingData else {
                return layer
            }

            didChange = true
            var normalizedLayer = layer
            normalizedLayer.drawingData = normalizedDrawingData
            return normalizedLayer
        }

        return didChange ? normalizedLayerStack : layerStack
    }
}
