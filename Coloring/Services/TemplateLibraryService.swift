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

    private struct ManifestEntry: Decodable {
        let fileName: String
        let title: String
        let category: String
    }

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
        let localFileURLs = try pngFileURLs(in: localDirectoryURL)
        for fileURL in localFileURLs {
            try fileManager.removeItem(at: fileURL)
        }

        if let cloudDirectoryURL = cloudImportedDirectoryURL() {
            let cloudFileURLs = try pngFileURLs(in: cloudDirectoryURL)
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

        return entries.compactMap { entry in
            guard let fileURL = builtInTemplateResourceURL(fileName: entry.fileName) else {
                logger.error("Missing built-in template file \(entry.fileName, privacy: .public)")
                return nil
            }

            return ColoringTemplate(
                id: "builtin-\(entry.fileName)",
                title: entry.title,
                category: entry.category,
                source: .builtIn,
                filePath: fileURL.path
            )
        }
    }

    private func manifestResourceURL() -> URL? {
        bundle.url(forResource: "template_manifest", withExtension: "json", subdirectory: "Templates")
            ?? bundle.url(forResource: "template_manifest", withExtension: "json", subdirectory: "Resources/Templates")
            ?? bundle.url(forResource: "template_manifest", withExtension: "json")
    }

    private func builtInTemplateResourceURL(fileName: String) -> URL? {
        if let url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: "Templates/BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: "Resources/Templates/BuiltIn") {
            return url
        }

        if let url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: "BuiltIn") {
            return url
        }

        let nsFileName = fileName as NSString
        let resourceName = nsFileName.deletingPathExtension
        let resourceExtension = nsFileName.pathExtension
        let resolvedExtension: String? = resourceExtension.isEmpty ? nil : resourceExtension

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

        return bundle.url(forResource: fileName, withExtension: nil)
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
        guard let cloudRootURL = ubiquityContainerURLProvider(cloudContainerIdentifier) else {
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

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func pngFileURLs(in directoryURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "png" }
    }

    private func synchronizeImportedTemplatesWithCloud(localDirectoryURL: URL) {
        guard let cloudDirectoryURL = cloudImportedDirectoryURL() else {
            return
        }

        do {
            let localFiles = try pngFileURLs(in: localDirectoryURL)
            let cloudFiles = try pngFileURLs(in: cloudDirectoryURL)

            let localByName = Dictionary(uniqueKeysWithValues: localFiles.map { ($0.lastPathComponent, $0) })
            let cloudByName = Dictionary(uniqueKeysWithValues: cloudFiles.map { ($0.lastPathComponent, $0) })

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
        let newCloudURL = cloudDirectoryURL.appendingPathComponent(newFileName)

        do {
            if fileManager.fileExists(atPath: oldCloudURL.path) {
                if fileManager.fileExists(atPath: newCloudURL.path) {
                    try fileManager.removeItem(at: newCloudURL)
                }
                try fileManager.moveItem(at: oldCloudURL, to: newCloudURL)
            }
        } catch {
            logger.error("Failed to sync rename to iCloud: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncDeleteFromCloudIfNeeded(filename: String) {
        guard let cloudDirectoryURL = cloudImportedDirectoryURL() else {
            return
        }

        let cloudFileURL = cloudDirectoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: cloudFileURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: cloudFileURL)
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

        let sourceData = try Data(contentsOf: sourceURL)
        try sourceData.write(to: destinationURL, options: [.atomic])
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
