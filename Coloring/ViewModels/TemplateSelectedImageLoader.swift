import UIKit

enum TemplateSelectedImageLoadResult {
    case success(UIImage?)
    case failure(message: String)
}

enum TemplateSelectedImageLoader {
    static func loadImage(
        for template: ColoringTemplate,
        using templateLibrary: any TemplateLibraryProviding
    ) async -> TemplateSelectedImageLoadResult {
        do {
            let templateData = try await templateLibrary.imageData(for: template)
            let image = UIImage(data: templateData)?.stableDisplayImage()
            return .success(image)
        } catch {
            return .failure(message: "Could not load selected template image.")
        }
    }
}
