import Foundation
import PencilKit
import SwiftUI
import UIKit

protocol TemplateArtworkExporting: Sendable {
    func exportPNG(
        templateData: Data,
        drawingData: Data,
        canvasSize: CGSize,
        templateID: String
    ) async throws -> URL
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
        canvasSize: CGSize,
        templateID: String
    ) async throws -> URL {
        let pngData = try await MainActor.run {
            guard let templateImage = UIImage(data: templateData) else {
                throw ExportError.invalidTemplate
            }

            guard let drawing = try? PKDrawing(data: drawingData) else {
                throw ExportError.invalidDrawing
            }

            let canvasRect = CGRect(origin: .zero, size: canvasSize)
            let renderer = UIGraphicsImageRenderer(size: canvasSize)

            return renderer.pngData { context in
                UIColor.white.setFill()
                context.fill(canvasRect)

                templateImage.draw(in: canvasRect)

                let drawingImage = drawing.image(from: canvasRect, scale: 2.0)
                drawingImage.draw(in: canvasRect)
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
