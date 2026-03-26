import Foundation

struct TemplateReloadResolution {
    let validTemplateIDs: Set<String>
    let builtInCategoryNamesByTemplateID: [String: Set<String>]
    let builtInCategories: [TemplateCategory]
    let filteredRecentTemplateIDs: [String]
    let selectedTemplateID: String
}

enum TemplateReloadStateResolver {
    static func resolve(
        loadedTemplates: [ColoringTemplate],
        currentSelectedTemplateID: String,
        lastSelectedTemplateID: String?,
        recentTemplateIDs: [String]
    ) -> TemplateReloadResolution {
        let validTemplateIDs = Set(loadedTemplates.map(\.id))
        let builtInCategoryNamesByTemplateID = Dictionary(
            uniqueKeysWithValues: loadedTemplates.map { template in
                (template.id, TemplateCategory.builtInCategoryNames(for: template))
            }
        )
        let builtInCategories = Set(
            builtInCategoryNamesByTemplateID.values.flatMap(\.self)
        )
        .sorted()
        .map { name in
            TemplateCategory(
                id: TemplateCategory.builtInCategoryID(for: name),
                name: name,
                isUserCreated: false
            )
        }

        let filteredRecentTemplateIDs = recentTemplateIDs.filter { validTemplateIDs.contains($0) }

        let selectedTemplateID: String
        if !currentSelectedTemplateID.isEmpty,
           validTemplateIDs.contains(currentSelectedTemplateID)
        {
            selectedTemplateID = currentSelectedTemplateID
        } else if let lastSelectedTemplateID,
                  !lastSelectedTemplateID.isEmpty,
                  validTemplateIDs.contains(lastSelectedTemplateID)
        {
            selectedTemplateID = lastSelectedTemplateID
        } else {
            selectedTemplateID = loadedTemplates.first?.id ?? ""
        }

        return TemplateReloadResolution(
            validTemplateIDs: validTemplateIDs,
            builtInCategoryNamesByTemplateID: builtInCategoryNamesByTemplateID,
            builtInCategories: builtInCategories,
            filteredRecentTemplateIDs: filteredRecentTemplateIDs,
            selectedTemplateID: selectedTemplateID
        )
    }
}
