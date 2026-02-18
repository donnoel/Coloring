import Foundation
import SwiftUI
import UIKit

protocol ArtworkExporting: Sendable {
    func exportPNG(scene: ColoringScene, regionColors: [String: ColoringColor], canvasSize: CGSize) async throws -> URL
}

actor ArtworkExportService: ArtworkExporting {
    enum ExportError: LocalizedError {
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                return "Could not render the artwork. Please try again."
            }
        }
    }

    func exportPNG(scene: ColoringScene, regionColors: [String: ColoringColor], canvasSize: CGSize) async throws -> URL {
        let data = try await MainActor.run {
            let exportView = ColoringCanvasView(
                scene: scene,
                regionColors: regionColors,
                isInteractive: false,
                onRegionTapped: nil
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(Color.white)

            let renderer = ImageRenderer(content: exportView)
            renderer.scale = 2.0

            guard let image = renderer.uiImage, let pngData = image.pngData() else {
                throw ExportError.renderFailed
            }

            return pngData
        }

        let outputURL = makeOutputURL(sceneID: scene.id)
        try data.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private func makeOutputURL(sceneID: String) -> URL {
        let sanitizedID = sceneID.replacingOccurrences(of: " ", with: "-")
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(sanitizedID)-\(timestamp).png"

        return FileManager.default
            .temporaryDirectory
            .appendingPathComponent(filename)
    }
}
