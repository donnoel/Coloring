import Foundation
import PencilKit
import UIKit

protocol LayerCompositing {
    func compositeLayersBelow(
        layers: [DrawingLayer],
        activeLayerID: UUID,
        canvasSize: CGSize
    ) -> UIImage?

    func compositeLayersAbove(
        layers: [DrawingLayer],
        activeLayerID: UUID,
        canvasSize: CGSize
    ) -> UIImage?

    func compositeAllVisibleLayers(
        layers: [DrawingLayer],
        canvasSize: CGSize
    ) -> UIImage?
}

struct LayerCompositorService: LayerCompositing {
    func compositeLayersBelow(
        layers: [DrawingLayer],
        activeLayerID: UUID,
        canvasSize: CGSize
    ) -> UIImage? {
        let sorted = layers.sorted { $0.order < $1.order }
        let belowLayers = sorted.prefix(while: { $0.id != activeLayerID })
            .filter(\.isVisible)
            .filter { !$0.drawingData.isEmpty }

        return compositeLayers(Array(belowLayers), canvasSize: canvasSize)
    }

    func compositeLayersAbove(
        layers: [DrawingLayer],
        activeLayerID: UUID,
        canvasSize: CGSize
    ) -> UIImage? {
        let sorted = layers.sorted { $0.order < $1.order }
        guard let activeIndex = sorted.firstIndex(where: { $0.id == activeLayerID }) else {
            return nil
        }

        let aboveLayers = sorted.suffix(from: sorted.index(after: activeIndex))
            .filter(\.isVisible)
            .filter { !$0.drawingData.isEmpty }

        return compositeLayers(Array(aboveLayers), canvasSize: canvasSize)
    }

    func compositeAllVisibleLayers(
        layers: [DrawingLayer],
        canvasSize: CGSize
    ) -> UIImage? {
        let sorted = layers.sorted { $0.order < $1.order }
            .filter(\.isVisible)
            .filter { !$0.drawingData.isEmpty }

        return compositeLayers(sorted, canvasSize: canvasSize)
    }

    private func compositeLayers(_ layers: [DrawingLayer], canvasSize: CGSize) -> UIImage? {
        guard !layers.isEmpty else {
            return nil
        }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)

        return renderer.image { _ in
            for layer in layers {
                guard let drawing = try? PKDrawing(data: layer.drawingData) else {
                    continue
                }

                let drawingImage = drawing.image(from: canvasRect, scale: 2.0)
                drawingImage.draw(in: canvasRect)
            }
        }
    }
}
