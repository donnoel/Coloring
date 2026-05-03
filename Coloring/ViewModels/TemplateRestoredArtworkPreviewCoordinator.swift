import PencilKit
import UIKit

enum TemplateRestoredArtworkPreviewCoordinator {
    static let previewHoldNanoseconds: UInt64 = 1_200_000_000

    struct RenderInput {
        let templateImage: UIImage
        let drawing: PKDrawing
        let fillImage: UIImage?
        let belowLayerImage: UIImage?
        let aboveLayerImage: UIImage?
        let canvasSize: CGSize
    }

    static func makePreview(from input: RenderInput) -> UIImage? {
        guard input.canvasSize.width > 0, input.canvasSize.height > 0 else {
            return nil
        }

        let canvasRect = CGRect(origin: .zero, size: input.canvasSize)
        let exportTraitCollection = UITraitCollection(userInterfaceStyle: .light)
        let normalizedDrawing = input.drawing.stableColorDrawing(using: exportTraitCollection)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: input.canvasSize, format: format)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(canvasRect)
            input.templateImage.stableDisplayImage().draw(in: canvasRect)
            input.fillImage?.stableDisplayImage().draw(in: canvasRect)
            input.belowLayerImage?.stableDisplayImage().draw(in: canvasRect)
            let drawingImage = normalizedDrawing.image(from: canvasRect, scale: 2.0)
            drawingImage.draw(in: canvasRect)
            input.aboveLayerImage?.stableDisplayImage().draw(in: canvasRect)
        }
    }
}
