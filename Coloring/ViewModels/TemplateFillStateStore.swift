import Foundation
import UIKit

final class TemplateFillStateStore {
    private var fillDataByTemplateID: [String: Data] = [:]
    private var cachedImageByTemplateID: [String: UIImage] = [:]
    private var cachedImageDataByTemplateID: [String: Data] = [:]

    func retainEntries(for templateIDs: Set<String>) {
        fillDataByTemplateID = fillDataByTemplateID.filter { templateIDs.contains($0.key) }
        cachedImageByTemplateID = cachedImageByTemplateID.filter { templateIDs.contains($0.key) }
        cachedImageDataByTemplateID = cachedImageDataByTemplateID.filter { templateIDs.contains($0.key) }
    }

    func rename(from oldTemplateID: String, to newTemplateID: String) {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let fillData = fillDataByTemplateID.removeValue(forKey: oldTemplateID) {
            fillDataByTemplateID[newTemplateID] = fillData
        }
        if let cachedImage = cachedImageByTemplateID.removeValue(forKey: oldTemplateID) {
            cachedImageByTemplateID[newTemplateID] = cachedImage
        }
        if let cachedData = cachedImageDataByTemplateID.removeValue(forKey: oldTemplateID) {
            cachedImageDataByTemplateID[newTemplateID] = cachedData
        }
    }

    func fillData(for templateID: String) -> Data? {
        fillDataByTemplateID[templateID]
    }

    func setFillData(_ fillData: Data?, for templateID: String) {
        if let fillData {
            fillDataByTemplateID[templateID] = fillData
        } else {
            fillDataByTemplateID.removeValue(forKey: templateID)
        }
    }

    func removeAll(for templateID: String) {
        fillDataByTemplateID.removeValue(forKey: templateID)
        cachedImageByTemplateID.removeValue(forKey: templateID)
        cachedImageDataByTemplateID.removeValue(forKey: templateID)
    }

    func clearCachedImage(for templateID: String) {
        cachedImageByTemplateID.removeValue(forKey: templateID)
        cachedImageDataByTemplateID.removeValue(forKey: templateID)
    }

    func cachedImage(for templateID: String, matching fillData: Data) -> UIImage? {
        guard cachedImageDataByTemplateID[templateID] == fillData else {
            return nil
        }

        return cachedImageByTemplateID[templateID]
    }

    func cacheImage(_ image: UIImage, data: Data, for templateID: String) {
        cachedImageByTemplateID[templateID] = image
        cachedImageDataByTemplateID[templateID] = data
    }
}
