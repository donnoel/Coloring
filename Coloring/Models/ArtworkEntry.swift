import Foundation

struct ArtworkEntry: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let sourceTemplateID: String
    let sourceTemplateName: String
    let createdAt: Date
    let fullImageFilename: String
    let thumbnailFilename: String

    var fullImagePath: String {
        GalleryStoreService.galleryDirectoryURL
            .appendingPathComponent(fullImageFilename).path
    }

    var thumbnailPath: String {
        GalleryStoreService.galleryDirectoryURL
            .appendingPathComponent(thumbnailFilename).path
    }
}
