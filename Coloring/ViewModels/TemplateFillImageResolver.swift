import UIKit

enum TemplateFillImageResolver {
    static func resolveDisplayImage(
        fillData: Data,
        cachedImage: UIImage?,
        decodeImage: (Data) -> UIImage?,
        cacheImage: (UIImage) -> Void
    ) -> UIImage? {
        if let cachedImage {
            return cachedImage
        }

        guard let decodedImage = decodeImage(fillData) else {
            return nil
        }
        cacheImage(decodedImage)
        return decodedImage
    }
}
