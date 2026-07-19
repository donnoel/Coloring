import Foundation

struct ColoringWidgetCurrentArtwork: Codable, Equatable, Sendable {
    let templateID: String
    let title: String
    let progress: Double
    let imageData: Data

    var destinationURL: URL? {
        ColoringWidgetDestination.studio(templateID: templateID)
    }
}

struct ColoringWidgetGalleryArtwork: Codable, Equatable, Sendable {
    let entryID: String
    let title: String
    let createdAt: Date
    let imageData: Data

    var destinationURL: URL? {
        ColoringWidgetDestination.gallery(entryID: entryID)
    }
}

struct ColoringWidgetSnapshot: Codable, Equatable, Sendable {
    static let empty = ColoringWidgetSnapshot(
        currentArtwork: nil,
        latestGalleryArtwork: nil,
        updatedAt: .distantPast
    )

    var currentArtwork: ColoringWidgetCurrentArtwork?
    var latestGalleryArtwork: ColoringWidgetGalleryArtwork?
    var updatedAt: Date
}

enum ColoringWidgetSnapshotStore {
    static let appGroupIdentifier = "group.dn.coloring"
    static let widgetKind = "ColoringRoomMediumWidget"
    static let filename = "coloring-widget-snapshot.json"

    static func sharedFileURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(filename, isDirectory: false)
    }

    static func load(from fileURL: URL?) -> ColoringWidgetSnapshot {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              let snapshot = try? JSONDecoder().decode(ColoringWidgetSnapshot.self, from: data)
        else {
            return .empty
        }

        return snapshot
    }
}

enum ColoringWidgetDestination {
    static func studio(templateID: String) -> URL? {
        makeURL(host: "studio", queryName: "templateID", queryValue: templateID)
    }

    static func gallery(entryID: String) -> URL? {
        makeURL(host: "gallery", queryName: "entryID", queryValue: entryID)
    }

    private static func makeURL(host: String, queryName: String, queryValue: String) -> URL? {
        var components = URLComponents()
        components.scheme = "coloringroom"
        components.host = host
        components.queryItems = [URLQueryItem(name: queryName, value: queryValue)]
        return components.url
    }
}
