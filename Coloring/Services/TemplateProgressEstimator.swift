import CoreGraphics
import Foundation
import PencilKit
import UIKit

actor TemplateProgressEstimator {
    private static let sampleSize = CGSize(width: 32, height: 32)
    private static let maxEstimatedProgress = 0.99
    private static let minimumVisibleAlpha: UInt8 = 8
    // Coloring pages often have large paper/background areas that should not make finished work look barely started.
    private static let expectedCompleteVisibleCoverage = 0.28

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

        let coverageProgress = Self.coverageProgress(
            layerStack: layerStack,
            fallbackDrawingData: fallbackDrawingData,
            fillData: fillData,
            canvasSize: canvasSize
        )
        guard coverageProgress > 0 else {
            return 0.01
        }

        return min(max(coverageProgress, 0.01), Self.maxEstimatedProgress)
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

    private static func coverageProgress(
        layerStack: LayerStack?,
        fallbackDrawingData: Data?,
        fillData: Data?,
        canvasSize: CGSize
    ) -> Double {
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

        var visiblePixelCount = 0
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
                let alpha = bytes[offset + 3]
                if alpha >= Self.minimumVisibleAlpha {
                    visiblePixelCount += 1
                }
            }
        }

        let totalSampleCount = cgImage.width * cgImage.height
        guard totalSampleCount > 0, visiblePixelCount > 0 else {
            return 0
        }
        let visibleCoverage = Double(visiblePixelCount) / Double(totalSampleCount)
        return min(visibleCoverage / Self.expectedCompleteVisibleCoverage, 1)
    }
}
