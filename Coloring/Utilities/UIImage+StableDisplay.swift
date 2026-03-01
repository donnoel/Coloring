import UIKit

extension UIImage {
    nonisolated func stableDisplayImage() -> UIImage {
        if renderingMode == .alwaysOriginal, imageAsset == nil {
            return self
        }

        if let cgImage {
            return UIImage(
                cgImage: cgImage,
                scale: scale,
                orientation: imageOrientation
            )
            .withRenderingMode(.alwaysOriginal)
        }

        guard size.width > 0, size.height > 0 else {
            return withRenderingMode(.alwaysOriginal)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}
