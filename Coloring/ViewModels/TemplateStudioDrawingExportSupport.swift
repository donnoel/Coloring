import CoreGraphics
import Foundation
import PencilKit
import UIKit

enum TemplateStudioDrawingExportSupport {
    static func selectedTemplateAspectRatio(for image: UIImage?) -> CGFloat {
        guard let size = image?.size,
              size.width > 0,
              size.height > 0
        else {
            return 4.0 / 3.0
        }

        return size.width / size.height
    }

    static func serializedDrawingData(for drawing: PKDrawing) -> Data {
        guard !drawing.strokes.isEmpty else {
            return Data()
        }

        return drawing.dataRepresentation()
    }

    static func bestExportSize(for image: UIImage?) -> CGSize {
        guard let image else {
            return CGSize(width: 2048, height: 1536)
        }

        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: 2048, height: 1536)
        }

        let longEdge = max(size.width, size.height)
        guard longEdge > 2048 else {
            return size
        }

        let scale = 2048 / longEdge
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
