import Foundation
import PencilKit
import SwiftUI
import UIKit

protocol TemplateArtworkExporting: Sendable {
    func exportPNG(
        templateData: Data,
        drawingData: Data,
        fillLayerData: Data?,
        compositedLayersImageData: Data?,
        canvasSize: CGSize,
        templateID: String
    ) async throws -> URL
}

extension TemplateArtworkExporting {
    func exportPNG(
        templateData: Data,
        drawingData: Data,
        fillLayerData: Data? = nil,
        canvasSize: CGSize,
        templateID: String
    ) async throws -> URL {
        try await exportPNG(
            templateData: templateData,
            drawingData: drawingData,
            fillLayerData: fillLayerData,
            compositedLayersImageData: nil,
            canvasSize: canvasSize,
            templateID: templateID
        )
    }
}

actor TemplateArtworkExportService: TemplateArtworkExporting {
    enum ExportError: LocalizedError {
        case invalidTemplate
        case invalidDrawing
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .invalidTemplate:
                return "Could not load the selected template image."
            case .invalidDrawing:
                return "Could not render the current drawing strokes."
            case .renderFailed:
                return "Could not render the artwork. Please try again."
            }
        }
    }

    func exportPNG(
        templateData: Data,
        drawingData: Data,
        fillLayerData: Data?,
        compositedLayersImageData: Data?,
        canvasSize: CGSize,
        templateID: String
    ) async throws -> URL {
        let pngData = try await MainActor.run {
            guard let templateImage = UIImage(data: templateData) else {
                throw ExportError.invalidTemplate
            }

            let fillImage: UIImage? = if let fillLayerData {
                UIImage(data: fillLayerData)
            } else {
                nil
            }

            let canvasRect = CGRect(origin: .zero, size: canvasSize)
            let renderer = UIGraphicsImageRenderer(size: canvasSize)

            return renderer.pngData { context in
                UIColor.white.setFill()
                context.fill(canvasRect)

                templateImage.draw(in: canvasRect)

                if let fillImage {
                    fillImage.draw(in: canvasRect)
                }

                // Use pre-composited layers image if available, otherwise fall back to single drawing.
                if let compositedLayersImageData,
                   let layersImage = UIImage(data: compositedLayersImageData)
                {
                    layersImage.draw(in: canvasRect)
                } else if let drawing = try? PKDrawing(data: drawingData) {
                    let drawingImage = drawing.image(from: canvasRect, scale: 2.0)
                    drawingImage.draw(in: canvasRect)
                }
            }
        }

        guard !pngData.isEmpty else {
            throw ExportError.renderFailed
        }

        let outputURL = makeOutputURL(templateID: templateID)
        try pngData.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private func makeOutputURL(templateID: String) -> URL {
        let sanitizedID = templateID.replacingOccurrences(of: " ", with: "-")
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "template-\(sanitizedID)-\(timestamp).png"

        return FileManager.default
            .temporaryDirectory
            .appendingPathComponent(filename)
    }
}
