import Foundation

struct TemplateCategorySanitizedState {
    let favoriteTemplateIDs: Set<String>
    let completedTemplateIDs: Set<String>
    let recentTemplateIDs: [String]
    let hiddenTemplateIDs: Set<String>
}

enum TemplateCategoryStateSanitizer {
    static func sanitizeStoredState(
        favoriteTemplateIDs: Set<String>,
        completedTemplateIDs: Set<String>,
        recentTemplateIDs: [String],
        hiddenTemplateIDs: Set<String>,
        validTemplateIDs: Set<String>
    ) -> TemplateCategorySanitizedState {
        TemplateCategorySanitizedState(
            favoriteTemplateIDs: favoriteTemplateIDs.intersection(validTemplateIDs),
            completedTemplateIDs: completedTemplateIDs.intersection(validTemplateIDs),
            recentTemplateIDs: recentTemplateIDs.filter { validTemplateIDs.contains($0) },
            hiddenTemplateIDs: hiddenTemplateIDs.intersection(validTemplateIDs)
        )
    }

    static func markedRecentTemplateIDs(
        templateID: String,
        availableTemplateIDs: Set<String>,
        recentTemplateIDs: [String],
        maxRecentTemplates: Int
    ) -> [String]? {
        guard !templateID.isEmpty,
              availableTemplateIDs.contains(templateID)
        else {
            return nil
        }

        var updatedRecentTemplateIDs = recentTemplateIDs
        updatedRecentTemplateIDs.removeAll { $0 == templateID }
        updatedRecentTemplateIDs.insert(templateID, at: 0)
        if updatedRecentTemplateIDs.count > maxRecentTemplates {
            updatedRecentTemplateIDs.removeLast(updatedRecentTemplateIDs.count - maxRecentTemplates)
        }

        guard recentTemplateIDs != updatedRecentTemplateIDs else {
            return nil
        }

        return updatedRecentTemplateIDs
    }
}
