import PencilKit
import UIKit

struct PencilDrawingRenderCacheRequest: @unchecked Sendable {
    let drawing: PKDrawing
    let canvasSize: CGSize
    var maximumLongEdge: CGFloat = 2_048
}

protocol PencilDrawingRenderCacheRendering: Sendable {
    func image(for request: PencilDrawingRenderCacheRequest) async -> UIImage?
}

actor PencilDrawingRenderCacheService: PencilDrawingRenderCacheRendering {
    private static let maximumLongEdge: CGFloat = 2_048

    nonisolated static func supportsCaching(_ drawing: PKDrawing) -> Bool {
        // Textured pencil shading must stay on the native renderer until cached
        // and live appearance can be verified to match.
        !drawing.strokes.contains { $0.ink.inkType == .pencil }
    }

    func image(for request: PencilDrawingRenderCacheRequest) -> UIImage? {
        autoreleasepool {
            guard !Task.isCancelled,
                  !request.drawing.strokes.isEmpty,
                  Self.supportsCaching(request.drawing),
                  request.canvasSize.width.isFinite,
                  request.canvasSize.height.isFinite,
                  request.canvasSize.width > 0,
                  request.canvasSize.height > 0,
                  request.maximumLongEdge.isFinite,
                  request.maximumLongEdge >= 1
            else {
                return nil
            }

            // Both intermediate and final images stay within 2048 squared pixels.
            // The final standard 8-bit RGBA image needs at most 16 MiB.
            let maximumLongEdge = min(request.maximumLongEdge, Self.maximumLongEdge)
            let scale = min(maximumLongEdge / max(request.canvasSize.width, request.canvasSize.height), 1)
            let outputSize = CGSize(
                width: max(1, floor(request.canvasSize.width * scale)),
                height: max(1, floor(request.canvasSize.height * scale))
            )
            let sourceRect = CGRect(origin: .zero, size: request.canvasSize)
            let outputRect = CGRect(origin: .zero, size: outputSize)
            let drawing = request.drawing.stableColorDrawing(
                using: UITraitCollection(userInterfaceStyle: .light)
            )
            guard !Task.isCancelled else {
                return nil
            }

            let strokesImage = drawing.image(from: sourceRect, scale: scale)
            guard !Task.isCancelled else {
                return nil
            }

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
                strokesImage.stableDisplayImage().draw(in: outputRect)
            }

            return Task.isCancelled ? nil : image
        }
    }
}
