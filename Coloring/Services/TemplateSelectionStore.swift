import Foundation

protocol TemplateSelectionStoreProviding {
    func loadSelectedTemplateID() -> String?
    func saveSelectedTemplateID(_ templateID: String?)
}

struct TemplateSelectionStore: TemplateSelectionStoreProviding {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "TemplateStudio.LastSelectedTemplateID"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func loadSelectedTemplateID() -> String? {
        guard let value = userDefaults.string(forKey: storageKey),
              !value.isEmpty
        else {
            return nil
        }

        return value
    }

    func saveSelectedTemplateID(_ templateID: String?) {
        let normalizedTemplateID = templateID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedTemplateID, !normalizedTemplateID.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }

        userDefaults.set(normalizedTemplateID, forKey: storageKey)
    }
}
