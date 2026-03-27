import Foundation
import OSLog

protocol TemplateLibraryProviding: Actor {
    func loadTemplates() throws -> [ColoringTemplate]
    func imageData(for template: ColoringTemplate) throws -> Data
    func importTemplate(imageData: Data, preferredName: String?) throws -> ColoringTemplate
    func renameImportedTemplate(id: String, newTitle: String) throws -> ColoringTemplate
    func deleteImportedTemplate(id: String) throws
    func deleteAllImportedTemplates() throws
}

protocol TemplateDrawingStoreProviding: Actor {
    func loadDrawingData(for templateID: String) throws -> Data?
    func saveDrawingData(_ drawingData: Data, for templateID: String) throws
    func renameDrawingData(from oldTemplateID: String, to newTemplateID: String) throws
    func deleteDrawingData(for templateID: String) throws
    func loadFillData(for templateID: String) throws -> Data?
    func saveFillData(_ fillData: Data, for templateID: String) throws
    func renameFillData(from oldTemplateID: String, to newTemplateID: String) throws
    func deleteFillData(for templateID: String) throws
    func loadLayerStackData(for templateID: String) throws -> Data?
    func saveLayerStackData(_ data: Data, for templateID: String) throws
    func renameLayerStackData(from oldTemplateID: String, to newTemplateID: String) throws
    func deleteLayerStackData(for templateID: String) throws
}

actor TemplateDrawingStoreService: TemplateDrawingStoreProviding {
    private struct DataFingerprint: Equatable {
        let size: Int
        let hash: Int
    }

    private let fileManager: FileManager
    private let logger: Logger
    private let cloudContainerIdentifier: String?
    private let documentsDirectoryURLProvider: @Sendable () throws -> URL
    private let ubiquityContainerURLProvider: @Sendable (String?) -> URL?
    private var lastCloudSyncedFingerprintByFilename: [String: DataFingerprint] = [:]

    init(
        fileManager: FileManager = .default,
        logger: Logger = Logger(subsystem: "Coloring", category: "TemplateDrawingStore"),
        cloudContainerIdentifier: String? = "iCloud.dn.coloring",
        documentsDirectoryURLProvider: @escaping @Sendable () throws -> URL = {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            return documentsURL
        },
        ubiquityContainerURLProvider: @escaping @Sendable (String?) -> URL? = {
            FileManager.default.url(forUbiquityContainerIdentifier: $0)
        }
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.cloudContainerIdentifier = cloudContainerIdentifier
        self.documentsDirectoryURLProvider = documentsDirectoryURLProvider
        self.ubiquityContainerURLProvider = ubiquityContainerURLProvider
    }

    func loadDrawingData(for templateID: String) throws -> Data? {
        let drawingFilename = Self.drawingFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: drawingFilename)
        if fileManager.fileExists(atPath: localURL.path) {
            let localData = try Data(contentsOf: localURL)
            syncDrawingDataToCloudIfNeeded(localData, filename: drawingFilename)
            return localData
        }

        guard let cloudFileURL = cloudDrawingFileURLIfExists(forFilename: drawingFilename) else {
            return nil
        }

        let cloudData = try readDrawingData(from: cloudFileURL)
        try cloudData.write(to: localURL, options: [.atomic])
        return cloudData
    }

    func saveDrawingData(_ drawingData: Data, for templateID: String) throws {
        let drawingFilename = Self.drawingFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: drawingFilename)
        try drawingData.write(to: localURL, options: [.atomic])
        syncDrawingDataToCloudIfNeeded(drawingData, filename: drawingFilename)
    }

    func renameDrawingData(from oldTemplateID: String, to newTemplateID: String) throws {
        guard oldTemplateID != newTemplateID else {
            return
        }

        let oldFilename = Self.drawingFilename(for: oldTemplateID)
        let newFilename = Self.drawingFilename(for: newTemplateID)
        let oldLocalURL = try localDrawingURL(forFilename: oldFilename)
        let newLocalURL = try localDrawingURL(forFilename: newFilename)

        if fileManager.fileExists(atPath: oldLocalURL.path) {
            if fileManager.fileExists(atPath: newLocalURL.path) {
                try fileManager.removeItem(at: newLocalURL)
            }
            try fileManager.moveItem(at: oldLocalURL, to: newLocalURL)
        }

        syncRenameInCloudIfNeeded(from: oldFilename, to: newFilename)
    }

    func deleteDrawingData(for templateID: String) throws {
        let drawingFilename = Self.drawingFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: drawingFilename)
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        deleteCloudDrawingIfNeeded(filename: drawingFilename)
    }

    func loadFillData(for templateID: String) throws -> Data? {
        let fillFilename = Self.fillFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: fillFilename)
        if fileManager.fileExists(atPath: localURL.path) {
            let localData = try Data(contentsOf: localURL)
            syncDrawingDataToCloudIfNeeded(localData, filename: fillFilename)
            return localData
        }

        guard let cloudFileURL = cloudDrawingFileURLIfExists(forFilename: fillFilename) else {
            return nil
        }

        let cloudData = try readDrawingData(from: cloudFileURL)
        try cloudData.write(to: localURL, options: [.atomic])
        return cloudData
    }

    func saveFillData(_ fillData: Data, for templateID: String) throws {
        let fillFilename = Self.fillFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: fillFilename)
        try fillData.write(to: localURL, options: [.atomic])
        syncDrawingDataToCloudIfNeeded(fillData, filename: fillFilename)
    }

    func renameFillData(from oldTemplateID: String, to newTemplateID: String) throws {
        guard oldTemplateID != newTemplateID else {
            return
        }

        let oldFilename = Self.fillFilename(for: oldTemplateID)
        let newFilename = Self.fillFilename(for: newTemplateID)
        let oldLocalURL = try localDrawingURL(forFilename: oldFilename)
        let newLocalURL = try localDrawingURL(forFilename: newFilename)

        if fileManager.fileExists(atPath: oldLocalURL.path) {
            if fileManager.fileExists(atPath: newLocalURL.path) {
                try fileManager.removeItem(at: newLocalURL)
            }
            try fileManager.moveItem(at: oldLocalURL, to: newLocalURL)
        }

        syncRenameInCloudIfNeeded(from: oldFilename, to: newFilename)
    }

    func deleteFillData(for templateID: String) throws {
        let fillFilename = Self.fillFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: fillFilename)
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        deleteCloudDrawingIfNeeded(filename: fillFilename)
    }

    private func localDrawingURL(forFilename filename: String) throws -> URL {
        let directoryURL = try localDrawingsDirectoryURL()
        return directoryURL.appendingPathComponent(filename)
    }

    private func localDrawingsDirectoryURL() throws -> URL {
        let documentsURL = try documentsDirectoryURLProvider()
        let directoryURL = documentsURL.appendingPathComponent("TemplateDrawings", isDirectory: true)
        try ensureDirectoryExists(at: directoryURL)
        return directoryURL
    }

    private func cloudDrawingsDirectoryURL() -> URL? {
        guard let cloudRootURL = cloudContainerRootURL() else {
            return nil
        }

        let directoryURL = cloudRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TemplateDrawings", isDirectory: true)
        do {
            try ensureDirectoryExists(at: directoryURL)
            return directoryURL
        } catch {
            logger.error("Could not access iCloud drawing folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cloudContainerRootURL() -> URL? {
        if let cloudRootURL = ubiquityContainerURLProvider(cloudContainerIdentifier) {
            return cloudRootURL
        }

        guard cloudContainerIdentifier != nil else {
            return nil
        }

        if let fallbackCloudRootURL = ubiquityContainerURLProvider(nil) {
            logger.log("Using default iCloud container fallback for drawing sync.")
            return fallbackCloudRootURL
        }

        return nil
    }

    private func syncDrawingDataToCloudIfNeeded(_ drawingData: Data, filename: String) {
        guard let cloudDirectoryURL = cloudDrawingsDirectoryURL() else {
            return
        }

        let newFingerprint = Self.fingerprint(for: drawingData)
        if lastCloudSyncedFingerprintByFilename[filename] == newFingerprint {
            return
        }

        let cloudFileURL = cloudDirectoryURL.appendingPathComponent(filename)
        let cloudPlaceholderURL = cloudDirectoryURL.appendingPathComponent("\(filename).icloud")
        do {
            if fileManager.fileExists(atPath: cloudFileURL.path),
               cloudFileMatches(drawingData, existingFileURL: cloudFileURL)
            {
                lastCloudSyncedFingerprintByFilename[filename] = newFingerprint
                return
            }

            if fileManager.fileExists(atPath: cloudPlaceholderURL.path) {
                try fileManager.removeItem(at: cloudPlaceholderURL)
            }
            if fileManager.fileExists(atPath: cloudFileURL.path) {
                try fileManager.removeItem(at: cloudFileURL)
            }

            try drawingData.write(to: cloudFileURL, options: [.atomic])
            lastCloudSyncedFingerprintByFilename[filename] = newFingerprint
        } catch {
            logger.error("Failed to sync drawing to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncRenameInCloudIfNeeded(from oldFilename: String, to newFilename: String) {
        guard oldFilename != newFilename,
              let cloudDirectoryURL = cloudDrawingsDirectoryURL()
        else {
            return
        }

        let oldCloudURL = cloudDirectoryURL.appendingPathComponent(oldFilename)
        let oldCloudPlaceholderURL = cloudDirectoryURL.appendingPathComponent("\(oldFilename).icloud")
        let newCloudURL = cloudDirectoryURL.appendingPathComponent(newFilename)
        let newCloudPlaceholderURL = cloudDirectoryURL.appendingPathComponent("\(newFilename).icloud")
        do {
            if fileManager.fileExists(atPath: newCloudPlaceholderURL.path) {
                try fileManager.removeItem(at: newCloudPlaceholderURL)
            }
            if fileManager.fileExists(atPath: newCloudURL.path) {
                try fileManager.removeItem(at: newCloudURL)
            }

            if fileManager.fileExists(atPath: oldCloudURL.path) {
                try fileManager.moveItem(at: oldCloudURL, to: newCloudURL)
                if let oldFingerprint = lastCloudSyncedFingerprintByFilename.removeValue(forKey: oldFilename) {
                    lastCloudSyncedFingerprintByFilename[newFilename] = oldFingerprint
                } else {
                    lastCloudSyncedFingerprintByFilename.removeValue(forKey: newFilename)
                }
            } else if fileManager.fileExists(atPath: oldCloudPlaceholderURL.path) {
                try fileManager.removeItem(at: oldCloudPlaceholderURL)
            }
        } catch {
            logger.error("Failed to sync drawing rename to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteCloudDrawingIfNeeded(filename: String) {
        guard let cloudDirectoryURL = cloudDrawingsDirectoryURL() else {
            return
        }

        let cloudFileURL = cloudDirectoryURL.appendingPathComponent(filename)
        let cloudPlaceholderURL = cloudDirectoryURL.appendingPathComponent("\(filename).icloud")
        do {
            if fileManager.fileExists(atPath: cloudFileURL.path) {
                try fileManager.removeItem(at: cloudFileURL)
            }
            if fileManager.fileExists(atPath: cloudPlaceholderURL.path) {
                try fileManager.removeItem(at: cloudPlaceholderURL)
            }
            lastCloudSyncedFingerprintByFilename.removeValue(forKey: filename)
        } catch {
            logger.error("Failed to delete drawing from iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cloudFileMatches(_ drawingData: Data, existingFileURL: URL) -> Bool {
        do {
            let values = try existingFileURL.resourceValues(forKeys: [.fileSizeKey])
            guard values.fileSize == drawingData.count else {
                return false
            }

            return try Data(contentsOf: existingFileURL) == drawingData
        } catch {
            return false
        }
    }

    private func cloudDrawingFileURLIfExists(forFilename filename: String) -> URL? {
        guard let cloudDirectoryURL = cloudDrawingsDirectoryURL() else {
            return nil
        }

        let cloudURL = cloudDirectoryURL.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: cloudURL.path) {
            return cloudURL
        }

        let placeholderURL = cloudDirectoryURL.appendingPathComponent("\(filename).icloud")
        if fileManager.fileExists(atPath: placeholderURL.path) {
            return placeholderURL
        }

        return nil
    }

    private func readDrawingData(from sourceURL: URL) throws -> Data {
        let fallbackDownloadedURL = fallbackDownloadedURLIfPlaceholder(for: sourceURL)
        do {
            return try Data(contentsOf: sourceURL)
        } catch {
            if let fallbackDownloadedURL,
               let fallbackData = try? Data(contentsOf: fallbackDownloadedURL) {
                return fallbackData
            }

            requestUbiquitousDownloadIfNeeded(at: sourceURL)
            if let fallbackDownloadedURL {
                requestUbiquitousDownloadIfNeeded(at: fallbackDownloadedURL)
            }

            var lastError: Error = error
            for _ in 0..<8 {
                // Use a shorter sleep to reduce actor blocking time.
                // Total worst-case: 8 × 100ms = 800ms (down from 8 × 250ms = 2s).
                Thread.sleep(forTimeInterval: 0.1)
                do {
                    return try Data(contentsOf: sourceURL)
                } catch {
                    lastError = error
                }

                if let fallbackDownloadedURL {
                    do {
                        return try Data(contentsOf: fallbackDownloadedURL)
                    } catch {
                        lastError = error
                    }
                }
            }

            throw lastError
        }
    }

    private func fallbackDownloadedURLIfPlaceholder(for sourceURL: URL) -> URL? {
        guard isICloudPlaceholderFile(sourceURL) else {
            return nil
        }

        return sourceURL.deletingPathExtension()
    }

    private func requestUbiquitousDownloadIfNeeded(at sourceURL: URL) {
        do {
            try fileManager.startDownloadingUbiquitousItem(at: sourceURL)
        } catch {
            // Non-ubiquitous local files throw here; ignore and keep local read behavior.
        }
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func isICloudPlaceholderFile(_ fileURL: URL) -> Bool {
        fileURL.pathExtension.lowercased() == "icloud"
    }

    nonisolated private static func drawingFilename(for templateID: String) -> String {
        "\(encodedTemplateID(templateID)).drawing"
    }

    nonisolated private static func fillFilename(for templateID: String) -> String {
        "\(encodedTemplateID(templateID)).fill"
    }

    nonisolated private static func layerStackFilename(for templateID: String) -> String {
        "\(encodedTemplateID(templateID)).layers"
    }

    func loadLayerStackData(for templateID: String) throws -> Data? {
        let filename = Self.layerStackFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: filename)
        if fileManager.fileExists(atPath: localURL.path) {
            let localData = try Data(contentsOf: localURL)
            syncDrawingDataToCloudIfNeeded(localData, filename: filename)
            return localData
        }

        guard let cloudFileURL = cloudDrawingFileURLIfExists(forFilename: filename) else {
            return nil
        }

        let cloudData = try readDrawingData(from: cloudFileURL)
        try cloudData.write(to: localURL, options: [.atomic])
        return cloudData
    }

    func saveLayerStackData(_ data: Data, for templateID: String) throws {
        let filename = Self.layerStackFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: filename)
        try data.write(to: localURL, options: [.atomic])
        syncDrawingDataToCloudIfNeeded(data, filename: filename)
    }

    func renameLayerStackData(from oldTemplateID: String, to newTemplateID: String) throws {
        guard oldTemplateID != newTemplateID else {
            return
        }

        let oldFilename = Self.layerStackFilename(for: oldTemplateID)
        let newFilename = Self.layerStackFilename(for: newTemplateID)
        let oldLocalURL = try localDrawingURL(forFilename: oldFilename)
        let newLocalURL = try localDrawingURL(forFilename: newFilename)

        if fileManager.fileExists(atPath: oldLocalURL.path) {
            if fileManager.fileExists(atPath: newLocalURL.path) {
                try fileManager.removeItem(at: newLocalURL)
            }
            try fileManager.moveItem(at: oldLocalURL, to: newLocalURL)
        }

        syncRenameInCloudIfNeeded(from: oldFilename, to: newFilename)
    }

    func deleteLayerStackData(for templateID: String) throws {
        let filename = Self.layerStackFilename(for: templateID)
        let localURL = try localDrawingURL(forFilename: filename)
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        deleteCloudDrawingIfNeeded(filename: filename)
    }

    nonisolated private static func encodedTemplateID(_ templateID: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return templateID.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            ?? templateID.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    }

    nonisolated private static func fingerprint(for data: Data) -> DataFingerprint {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data)
        return DataFingerprint(size: data.count, hash: hasher.finalize())
    }
}

actor TemplateLibraryService: TemplateLibraryProviding {
    enum LibraryError: LocalizedError {
        case invalidImageData
        case missingBundleResource
        case importedTemplateOnly
        case templateNotFound
        case invalidTemplateName

        var errorDescription: String? {
            switch self {
            case .invalidImageData:
                return "The selected file is not a valid image."
            case .missingBundleResource:
                return "Built-in templates are unavailable in this build."
            case .importedTemplateOnly:
                return "Only imported drawings can be changed."
            case .templateNotFound:
                return "Could not find the selected drawing."
            case .invalidTemplateName:
                return "Please enter a valid drawing name."
            }
        }
    }

    struct ManifestEntry: Decodable {
        let id: String?
        let file: String?
        let fileName: String?
        let title: String
        let category: String
        let complexity: String?
        let orientation: ColoringTemplate.CanvasOrientation?
        let mood: [String]?
        let session: String?
        let lineWeight: String?
        let featured: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case file
            case fileName
            case title
            case category
            case complexity
            case orientation
            case mood
            case session
            case lineWeight
            case featured
        }

        var resolvedFileName: String? {
            let value = (file ?? fileName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }

        var resolvedTemplateID: String? {
            if let normalizedID = normalizedIdentifier(id) {
                return normalizedID
            }

            guard let fileName = resolvedFileName else {
                return nil
            }

            return normalizedIdentifier(
                URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            )
        }

        var resolvedShelfCategory: String {
            let normalized = normalizedKey(category)
            if TemplateLibraryService.shelfCategoryDisplayNameByKey.keys.contains(normalized) {
                return normalized
            }
            return normalized
        }

        var resolvedComplexity: String {
            let normalized = normalizedKey(complexity)
            if TemplateLibraryService.complexityDisplayNameByKey.keys.contains(normalized) {
                return normalized
            }
            return "medium"
        }

        var resolvedMood: [String] {
            (mood ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var resolvedSession: String {
            let normalized = normalizedKey(session)
            return normalized.isEmpty ? "standard" : normalized
        }

        var resolvedLineWeight: String {
            let normalized = normalizedKey(lineWeight)
            return normalized.isEmpty ? "balanced" : normalized
        }

        var resolvedFeatured: Bool {
            featured ?? false
        }

        private func normalizedKey(_ value: String?) -> String {
            guard let value else {
                return ""
            }
            return value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        private func normalizedIdentifier(_ value: String?) -> String? {
            let normalized = normalizedKey(value)
            guard !normalized.isEmpty else {
                return nil
            }
            return normalized.replacingOccurrences(
                of: "[^a-z0-9._-]+",
                with: "-",
                options: .regularExpression
            )
        }
    }

    private static let shelfCategoryDisplayNameByKey: [String: String] = [
        "cozy": "Cozy",
        "nature": "Nature",
        "animals": "Animals",
        "fantasy": "Fantasy",
        "patterns": "Patterns",
        "seasonal": "Seasonal",
        "motorsport": "Motorsport",
        "scifi": "Sci-Fi"
    ]

    private static let complexityDisplayNameByKey: [String: String] = [
        "easy": "Easy",
        "medium": "Medium",
        "detailed": "Detailed",
        "dense": "Dense"
    ]

    private let bundle: Bundle
    private let fileManager: FileManager
    private let logger: Logger
    private let cloudContainerIdentifier: String?
    private let documentsDirectoryURLProvider: @Sendable () throws -> URL
    private let ubiquityContainerURLProvider: @Sendable (String?) -> URL?

    init(
        bundle: Bundle = .main,
        logger: Logger = Logger(subsystem: "Coloring", category: "TemplateLibrary"),
        fileManager: FileManager = .default,
        cloudContainerIdentifier: String? = "iCloud.dn.coloring",
        documentsDirectoryURLProvider: @escaping @Sendable () throws -> URL = {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            return documentsURL
        },
        ubiquityContainerURLProvider: @escaping @Sendable (String?) -> URL? = {
            FileManager.default.url(forUbiquityContainerIdentifier: $0)
        }
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.logger = logger
        self.cloudContainerIdentifier = cloudContainerIdentifier
        self.documentsDirectoryURLProvider = documentsDirectoryURLProvider
        self.ubiquityContainerURLProvider = ubiquityContainerURLProvider
    }

    func loadTemplates() throws -> [ColoringTemplate] {
        let importedTemplates = try loadImportedTemplates()
        let builtInTemplates: [ColoringTemplate]
        do {
            builtInTemplates = try loadBuiltInTemplates()
        } catch {
            logger.error("Built-in templates unavailable: \(error.localizedDescription, privacy: .public)")
            builtInTemplates = []
        }

        return builtInTemplates + importedTemplates
    }

    func imageData(for template: ColoringTemplate) throws -> Data {
        try Data(contentsOf: template.fileURL)
    }

    func importTemplate(imageData: Data, preferredName: String?) throws -> ColoringTemplate {
        guard imageData.isLikelyImage else {
            throw LibraryError.invalidImageData
        }

        let sanitizedName = Self.sanitizedFilename(preferredName ?? "Imported Drawing")
        let filename = "\(sanitizedName)-\(UUID().uuidString.lowercased()).png"
        let destinationURL = try importedDirectoryURL().appendingPathComponent(filename)

        try imageData.write(to: destinationURL, options: [.atomic])
        syncLocalImportedFileToCloudIfNeeded(destinationURL)
        logger.log("Imported template saved to \(destinationURL.path, privacy: .public)")

        return ColoringTemplate(
            id: "imported-\(filename)",
            title: Self.humanReadableTitle(from: filename),
            category: "Imported",
            source: .imported,
            filePath: destinationURL.path
        )
    }

    func renameImportedTemplate(id: String, newTitle: String) throws -> ColoringTemplate {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw LibraryError.invalidTemplateName
        }

        let existingTemplate = try importedTemplate(matchingID: id)
        let sourceURL = existingTemplate.fileURL
        let directoryURL = try importedDirectoryURL()
        let sourceStem = sourceURL.deletingPathExtension().lastPathComponent
        let suffix = Self.uuidSuffix(from: sourceStem) ?? "-\(UUID().uuidString.lowercased())"
        let preferredFileName = "\(Self.sanitizedFilename(trimmedTitle))\(suffix).png"
        let destinationURL = uniqueDestinationURL(
            in: directoryURL,
            preferredFileName: preferredFileName,
            excluding: sourceURL
        )

        if sourceURL != destinationURL {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            syncRenameToCloudIfNeeded(from: sourceURL.lastPathComponent, to: destinationURL.lastPathComponent)
            syncLocalImportedFileToCloudIfNeeded(destinationURL)
        }

        logger.log("Imported template renamed to \(destinationURL.lastPathComponent, privacy: .public)")

        let filename = destinationURL.lastPathComponent
        return ColoringTemplate(
            id: "imported-\(filename)",
            title: Self.humanReadableTitle(from: filename),
            category: "Imported",
            source: .imported,
            filePath: destinationURL.path
        )
    }

    func deleteImportedTemplate(id: String) throws {
        let template = try importedTemplate(matchingID: id)
        try fileManager.removeItem(at: template.fileURL)
        syncDeleteFromCloudIfNeeded(filename: template.fileURL.lastPathComponent)
        logger.log("Imported template deleted: \(template.fileURL.lastPathComponent, privacy: .public)")
    }

    func deleteAllImportedTemplates() throws {
        let localDirectoryURL = try importedDirectoryURL()
        let localFileURLs = try importedTemplateFileURLs(in: localDirectoryURL)
        for fileURL in localFileURLs {
            try fileManager.removeItem(at: fileURL)
        }

        if let cloudDirectoryURL = cloudImportedDirectoryURL() {
            let cloudFileURLs = try importedTemplateFileURLs(in: cloudDirectoryURL)
            for fileURL in cloudFileURLs {
                try fileManager.removeItem(at: fileURL)
            }
        }

        logger.log("All imported templates deleted.")
    }

    private func loadBuiltInTemplates() throws -> [ColoringTemplate] {
        guard let manifestURL = manifestResourceURL() else {
            throw LibraryError.missingBundleResource
        }

        let data = try Data(contentsOf: manifestURL)
        let entries = try JSONDecoder().decode([ManifestEntry].self, from: data)

        return entries.compactMap { entry -> ColoringTemplate? in
            guard let fileName = entry.resolvedFileName else {
                logger.error("Skipping built-in template with missing file name: \(entry.title, privacy: .public)")
                return nil
            }

            guard let fileURL = builtInTemplateResourceURL(fileName: fileName) else {
                logger.error("Missing built-in template file \(fileName, privacy: .public)")
                return nil
            }

            let shelfCategory = entry.resolvedShelfCategory
            let categoryDisplayName = Self.shelfCategoryDisplayNameByKey[shelfCategory] ?? entry.category

            return ColoringTemplate(
                id: "builtin-\(entry.resolvedTemplateID ?? fileName)",
                title: entry.title,
                category: categoryDisplayName,
                source: .builtIn,
                filePath: fileURL.path,
                canvasOrientation: entry.orientation ?? .any,
                shelfCategory: shelfCategory,
                complexity: entry.resolvedComplexity,
                mood: entry.resolvedMood,
                session: entry.resolvedSession,
                lineWeight: entry.resolvedLineWeight,
                featured: entry.resolvedFeatured
            )
        }
    }

    private func manifestResourceURL() -> URL? {
        bundle.url(forResource: "template_manifest", withExtension: "json", subdirectory: "Templates")
            ?? bundle.url(forResource: "template_manifest", withExtension: "json", subdirectory: "Resources/Templates")
            ?? bundle.url(forResource: "template_manifest", withExtension: "json")
    }

    private func builtInTemplateResourceURL(fileName: String) -> URL? {
        let normalizedPath = fileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.isEmpty else {
            return nil
        }

        let normalizedPathNSString = normalizedPath as NSString
        let leafFileName = normalizedPathNSString.lastPathComponent
        let directoryPath = normalizedPathNSString.deletingLastPathComponent
        let leafFileNameNSString = leafFileName as NSString
        let resourceName = leafFileNameNSString.deletingPathExtension
        let resourceExtension = leafFileNameNSString.pathExtension
        let resolvedExtension: String? = resourceExtension.isEmpty ? nil : resourceExtension

        if let resourceRootURL = bundle.resourceURL {
            let directResourceURL = resourceRootURL.appendingPathComponent(normalizedPath)
            if fileManager.fileExists(atPath: directResourceURL.path) {
                return directResourceURL
            }

            let resourcesPrefixedURL = resourceRootURL.appendingPathComponent("Resources").appendingPathComponent(normalizedPath)
            if fileManager.fileExists(atPath: resourcesPrefixedURL.path) {
                return resourcesPrefixedURL
            }

            // Some bundle copy phases flatten resources to bundle root.
            let flattenedResourceURL = resourceRootURL.appendingPathComponent(leafFileName)
            if fileManager.fileExists(atPath: flattenedResourceURL.path) {
                return flattenedResourceURL
            }

            let flattenedResourcesPrefixedURL = resourceRootURL.appendingPathComponent("Resources").appendingPathComponent(leafFileName)
            if fileManager.fileExists(atPath: flattenedResourcesPrefixedURL.path) {
                return flattenedResourcesPrefixedURL
            }
        }

        if !directoryPath.isEmpty {
            if let url = bundle.url(forResource: leafFileName, withExtension: nil, subdirectory: directoryPath) {
                return url
            }

            if let url = bundle.url(forResource: resourceName, withExtension: resolvedExtension, subdirectory: directoryPath) {
                return url
            }

            let resourcesDirectoryPath = "Resources/\(directoryPath)"
            if let url = bundle.url(forResource: leafFileName, withExtension: nil, subdirectory: resourcesDirectoryPath) {
                return url
            }

            if let url = bundle.url(forResource: resourceName, withExtension: resolvedExtension, subdirectory: resourcesDirectoryPath) {
                return url
            }
        }

        if let url = bundle.url(forResource: leafFileName, withExtension: nil, subdirectory: "Templates/BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: leafFileName, withExtension: nil, subdirectory: "Resources/Templates/BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: leafFileName, withExtension: nil, subdirectory: "BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: resourceName, withExtension: resolvedExtension, subdirectory: "Templates/BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: resourceName, withExtension: resolvedExtension, subdirectory: "Resources/Templates/BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: resourceName, withExtension: resolvedExtension, subdirectory: "BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: resourceName, withExtension: resolvedExtension) {
            return url
        }

        return bundle.url(forResource: leafFileName, withExtension: nil)
    }

    private func loadImportedTemplates() throws -> [ColoringTemplate] {
        let directoryURL = try importedDirectoryURL()
        synchronizeImportedTemplatesWithCloud(localDirectoryURL: directoryURL)
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return fileURLs
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { fileURL in
                let filename = fileURL.lastPathComponent
                return ColoringTemplate(
                    id: "imported-\(filename)",
                    title: Self.humanReadableTitle(from: filename),
                    category: "Imported",
                    source: .imported,
                    filePath: fileURL.path
                )
            }
    }

    private func importedDirectoryURL() throws -> URL {
        let documentsURL = try documentsDirectoryURLProvider()
        let directoryURL = documentsURL.appendingPathComponent("ImportedTemplates", isDirectory: true)
        try ensureDirectoryExists(at: directoryURL)
        return directoryURL
    }

    private func cloudImportedDirectoryURL() -> URL? {
        guard let cloudRootURL = cloudContainerRootURL() else {
            return nil
        }

        let directoryURL = cloudRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("ImportedTemplates", isDirectory: true)
        do {
            try ensureDirectoryExists(at: directoryURL)
            return directoryURL
        } catch {
            logger.error("Could not access iCloud template folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cloudContainerRootURL() -> URL? {
        if let cloudRootURL = ubiquityContainerURLProvider(cloudContainerIdentifier) {
            return cloudRootURL
        }

        guard cloudContainerIdentifier != nil else {
            return nil
        }

        if let fallbackCloudRootURL = ubiquityContainerURLProvider(nil) {
            logger.log("Using default iCloud container fallback for imported template sync.")
            return fallbackCloudRootURL
        }

        return nil
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func importedTemplateFileURLs(in directoryURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { logicalPNGFilename(for: $0) != nil }
    }

    private func pngFilesByLogicalName(in directoryURL: URL) throws -> [String: URL] {
        var filesByLogicalName: [String: URL] = [:]
        let files = try importedTemplateFileURLs(in: directoryURL)
        for fileURL in files {
            guard let logicalFileName = logicalPNGFilename(for: fileURL) else {
                continue
            }

            guard let existingURL = filesByLogicalName[logicalFileName] else {
                filesByLogicalName[logicalFileName] = fileURL
                continue
            }

            if isICloudPlaceholderFile(existingURL), !isICloudPlaceholderFile(fileURL) {
                filesByLogicalName[logicalFileName] = fileURL
            }
        }

        return filesByLogicalName
    }

    private func logicalPNGFilename(for fileURL: URL) -> String? {
        let extensionName = fileURL.pathExtension.lowercased()
        if extensionName == "png" {
            return fileURL.lastPathComponent
        }

        guard extensionName == "icloud" else {
            return nil
        }

        let ubiquitousFileURL = fileURL.deletingPathExtension()
        guard ubiquitousFileURL.pathExtension.lowercased() == "png" else {
            return nil
        }

        return ubiquitousFileURL.lastPathComponent
    }

    private func isICloudPlaceholderFile(_ fileURL: URL) -> Bool {
        fileURL.pathExtension.lowercased() == "icloud"
    }

    private func synchronizeImportedTemplatesWithCloud(localDirectoryURL: URL) {
        guard let cloudDirectoryURL = cloudImportedDirectoryURL() else {
            return
        }

        do {
            let localByName = try pngFilesByLogicalName(in: localDirectoryURL)
            let cloudByName = try pngFilesByLogicalName(in: cloudDirectoryURL)

            for (filename, cloudURL) in cloudByName where localByName[filename] == nil {
                let localURL = localDirectoryURL.appendingPathComponent(filename)
                try writeImageData(from: cloudURL, to: localURL)
            }

            for (filename, localURL) in localByName where cloudByName[filename] == nil {
                let cloudURL = cloudDirectoryURL.appendingPathComponent(filename)
                try writeImageData(from: localURL, to: cloudURL)
            }
        } catch {
            logger.error("Template iCloud sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncLocalImportedFileToCloudIfNeeded(_ localFileURL: URL) {
        guard let cloudDirectoryURL = cloudImportedDirectoryURL() else {
            return
        }

        let cloudFileURL = cloudDirectoryURL.appendingPathComponent(localFileURL.lastPathComponent)
        do {
            try writeImageData(from: localFileURL, to: cloudFileURL)
        } catch {
            logger.error("Failed to sync imported file to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncRenameToCloudIfNeeded(from oldFileName: String, to newFileName: String) {
        guard oldFileName != newFileName,
              let cloudDirectoryURL = cloudImportedDirectoryURL()
        else {
            return
        }

        let oldCloudURL = cloudDirectoryURL.appendingPathComponent(oldFileName)
        let oldCloudPlaceholderURL = cloudDirectoryURL.appendingPathComponent("\(oldFileName).icloud")
        let newCloudURL = cloudDirectoryURL.appendingPathComponent(newFileName)
        let newCloudPlaceholderURL = cloudDirectoryURL.appendingPathComponent("\(newFileName).icloud")

        // Coordinate the rename to prevent races with concurrent sync operations.
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: oldCloudURL,
            options: .forMoving,
            writingItemAt: newCloudURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { coordOldURL, coordNewURL in
            do {
                if fileManager.fileExists(atPath: newCloudPlaceholderURL.path) {
                    try fileManager.removeItem(at: newCloudPlaceholderURL)
                }
                if fileManager.fileExists(atPath: coordNewURL.path) {
                    try fileManager.removeItem(at: coordNewURL)
                }

                if fileManager.fileExists(atPath: coordOldURL.path) {
                    try fileManager.moveItem(at: coordOldURL, to: coordNewURL)
                } else if fileManager.fileExists(atPath: oldCloudPlaceholderURL.path) {
                    try fileManager.removeItem(at: oldCloudPlaceholderURL)
                }
            } catch {
                logger.error("Failed to sync rename to iCloud: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let coordinatorError {
            logger.error("File coordination failed during cloud rename: \(coordinatorError.localizedDescription, privacy: .public)")
        }
    }

    private func syncDeleteFromCloudIfNeeded(filename: String) {
        guard let cloudDirectoryURL = cloudImportedDirectoryURL() else {
            return
        }

        do {
            let cloudFileURL = cloudDirectoryURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: cloudFileURL.path) {
                try fileManager.removeItem(at: cloudFileURL)
            }

            let cloudPlaceholderURL = cloudDirectoryURL.appendingPathComponent("\(filename).icloud")
            if fileManager.fileExists(atPath: cloudPlaceholderURL.path) {
                try fileManager.removeItem(at: cloudPlaceholderURL)
            }
        } catch {
            logger.error("Failed to delete iCloud template file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeImageData(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }

        if sourceURL.hasDirectoryPath {
            return
        }

        let sourceData = try readImageData(from: sourceURL)

        // Use NSFileCoordinator for safe iCloud writes to avoid race conditions
        // when renames or other sync operations happen concurrently.
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { coordURL in
            do {
                try sourceData.write(to: coordURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }
        if let writeError {
            throw writeError
        }
    }

    private func readImageData(from sourceURL: URL) throws -> Data {
        let fallbackDownloadedURL = fallbackDownloadedURLIfPlaceholder(for: sourceURL)
        do {
            return try Data(contentsOf: sourceURL)
        } catch {
            if let fallbackDownloadedURL,
               let fallbackData = try? Data(contentsOf: fallbackDownloadedURL) {
                return fallbackData
            }

            requestUbiquitousDownloadIfNeeded(at: sourceURL)
            if let fallbackDownloadedURL {
                requestUbiquitousDownloadIfNeeded(at: fallbackDownloadedURL)
            }
            var lastError: Error = error
            for _ in 0..<8 {
                // Use a shorter sleep to reduce actor blocking time.
                // Total worst-case: 8 × 100ms = 800ms (down from 8 × 250ms = 2s).
                Thread.sleep(forTimeInterval: 0.1)
                do {
                    return try Data(contentsOf: sourceURL)
                } catch {
                    lastError = error
                }

                if let fallbackDownloadedURL {
                    do {
                        return try Data(contentsOf: fallbackDownloadedURL)
                    } catch {
                        lastError = error
                    }
                }
            }

            throw lastError
        }
    }

    private func fallbackDownloadedURLIfPlaceholder(for sourceURL: URL) -> URL? {
        guard isICloudPlaceholderFile(sourceURL) else {
            return nil
        }

        return sourceURL.deletingPathExtension()
    }

    private func requestUbiquitousDownloadIfNeeded(at sourceURL: URL) {
        do {
            try fileManager.startDownloadingUbiquitousItem(at: sourceURL)
        } catch {
            // Non-ubiquitous local files throw here; ignore and keep local read behavior.
        }
    }

    private func importedTemplate(matchingID id: String) throws -> ColoringTemplate {
        guard id.hasPrefix("imported-") else {
            throw LibraryError.importedTemplateOnly
        }

        let templates = try loadImportedTemplates()
        guard let template = templates.first(where: { $0.id == id }) else {
            throw LibraryError.templateNotFound
        }

        return template
    }

    private func uniqueDestinationURL(
        in directoryURL: URL,
        preferredFileName: String,
        excluding existingURL: URL
    ) -> URL {
        let existingFileName = existingURL.lastPathComponent
        if preferredFileName == existingFileName {
            return existingURL
        }

        let preferredURL = directoryURL.appendingPathComponent(preferredFileName)
        if !fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let stem = (preferredFileName as NSString).deletingPathExtension
        var suffix = 2
        while true {
            let candidateFileName = "\(stem)-\(suffix).png"
            let candidateURL = directoryURL.appendingPathComponent(candidateFileName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }

    nonisolated private static func sanitizedFilename(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let filteredScalars = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let normalized = String(filteredScalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")

        return normalized.isEmpty ? "imported-drawing" : normalized
    }

    nonisolated private static func uuidSuffix(from fileStem: String) -> String? {
        let pattern = "-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        guard let range = fileStem.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(fileStem[range])
    }

    nonisolated private static func humanReadableTitle(from filename: String) -> String {
        var stem = filename
            .replacingOccurrences(of: ".png", with: "")
        if let uuidRange = stem.range(
            of: "-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            options: .regularExpression
        ) {
            stem.removeSubrange(uuidRange)
        }

        let normalized = stem.replacingOccurrences(of: "-", with: " ")

        return normalized.capitalized
    }
}

private extension Data {
    nonisolated var isLikelyImage: Bool {
        guard !isEmpty else {
            return false
        }

        if count >= 8 {
            let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
            if Array(prefix(8)) == pngSignature {
                return true
            }
        }

        if count >= 3 {
            let jpegSignature: [UInt8] = [255, 216, 255]
            if Array(prefix(3)) == jpegSignature {
                return true
            }
        }

        if count >= 6 {
            let gif87a = Array("GIF87a".utf8)
            let gif89a = Array("GIF89a".utf8)
            let header = Array(prefix(6))
            if header == gif87a || header == gif89a {
                return true
            }
        }

        if count >= 12 {
            let start = index(startIndex, offsetBy: 4)
            let end = index(start, offsetBy: 4)
            let ftypHeader = Array(self[start..<end])
            let ftypSignature = Array("ftyp".utf8)
            if ftypHeader == ftypSignature {
                return true
            }
        }

        return false
    }
}
