import CoreGraphics
import Foundation
import PencilKit
import UIKit

actor TemplateProgressEstimator {
    private static let sampleSize = CGSize(width: 32, height: 32)
    private static let maxEstimatedProgress = 0.99

    func estimateProgress(
        layerStack: LayerStack?,
        fallbackDrawingData: Data?,
        fillData: Data?,
        canvasSize: CGSize
    ) -> Double? {
        let hasStrokeEdits = Self.hasVisibleStrokeEdits(
            layerStack: layerStack,
            fallbackDrawingData: fallbackDrawingData
        )
        let hasFillEdits = TemplateColoringPersistenceInspector.hasFillColoring(fillData: fillData)

        guard hasStrokeEdits || hasFillEdits else {
            return nil
        }

        let occupiedSampleCount = Self.occupiedSampleCount(
            layerStack: layerStack,
            fallbackDrawingData: fallbackDrawingData,
            fillData: fillData,
            canvasSize: canvasSize
        )
        let totalSampleCount = Int(Self.sampleSize.width * Self.sampleSize.height)
        guard totalSampleCount > 0, occupiedSampleCount > 0 else {
            return 0.01
        }

        let coverage = Double(occupiedSampleCount) / Double(totalSampleCount)
        return min(max(coverage, 0.01), Self.maxEstimatedProgress)
    }

    private static func hasVisibleStrokeEdits(
        layerStack: LayerStack?,
        fallbackDrawingData: Data?
    ) -> Bool {
        if let layerStack {
            return TemplateColoringPersistenceInspector.hasStrokeColoring(layerStack: layerStack, drawing: nil)
        }

        guard let fallbackDrawingData else {
            return false
        }

        return TemplateColoringPersistenceInspector.drawingDataContainsVisibleStrokes(fallbackDrawingData)
    }

    private static func occupiedSampleCount(
        layerStack: LayerStack?,
        fallbackDrawingData: Data?,
        fillData: Data?,
        canvasSize: CGSize
    ) -> Int {
        let renderSize = Self.sampleSize
        let sourceRect = CGRect(origin: .zero, size: canvasSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: renderSize, format: format).image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: renderSize))
            context.cgContext.scaleBy(
                x: renderSize.width / max(canvasSize.width, 1),
                y: renderSize.height / max(canvasSize.height, 1)
            )

            if let fillData,
               let fillImage = UIImage(data: fillData)
            {
                fillImage.draw(in: sourceRect)
            }

            let layerDrawingData = layerStack?.visibleLayers.map(\.drawingData) ?? [fallbackDrawingData].compactMap { $0 }
            for drawingData in layerDrawingData where !drawingData.isEmpty {
                guard let drawing = try? PKDrawing(data: drawingData) else {
                    continue
                }
                drawing.image(from: sourceRect, scale: 1).draw(in: sourceRect)
            }
        }

        guard let cgImage = image.cgImage,
              let providerData = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData)
        else {
            return 0
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else {
            return 0
        }

        var occupiedCount = 0
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
                let alpha = bytes[offset + 3]
                if alpha > 0 {
                    occupiedCount += 1
                }
            }
        }

        return occupiedCount
    }
}
