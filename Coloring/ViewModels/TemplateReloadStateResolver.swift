import Foundation

struct TemplateReloadResolution {
    let validTemplateIDs: Set<String>
    let builtInCategoryNamesByTemplateID: [String: Set<String>]
    let builtInCategories: [TemplateCategory]
    let filteredRecentTemplateIDs: [String]
    let selectedTemplateID: String
}

enum TemplateReloadStateResolver {
    private static func defaultVisibleSelectionID(from visibleTemplates: [ColoringTemplate]) -> String {
        visibleTemplates
            .sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return lhs.source == .imported
                }

                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .first?
            .id ?? ""
    }

    static func resolve(
        loadedTemplates: [ColoringTemplate],
        hiddenTemplateIDs: Set<String>,
        currentSelectedTemplateID: String,
        lastSelectedTemplateID: String?,
        recentTemplateIDs: [String]
    ) -> TemplateReloadResolution {
        let validTemplateIDs = Set(loadedTemplates.map(\.id))
        let visibleTemplates = loadedTemplates.filter { !hiddenTemplateIDs.contains($0.id) }
        let visibleTemplateIDs = Set(visibleTemplates.map(\.id))
        let builtInCategoryNamesByTemplateID = Dictionary(
            uniqueKeysWithValues: loadedTemplates.map { template in
                (template.id, TemplateCategory.builtInCategoryNames(for: template))
            }
        )
        let builtInCategories = Set(
            visibleTemplates.flatMap { template in
                builtInCategoryNamesByTemplateID[template.id] ?? []
            }
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
           visibleTemplateIDs.contains(currentSelectedTemplateID)
        {
            selectedTemplateID = currentSelectedTemplateID
        } else if let lastSelectedTemplateID,
                  !lastSelectedTemplateID.isEmpty,
                  visibleTemplateIDs.contains(lastSelectedTemplateID)
        {
            selectedTemplateID = lastSelectedTemplateID
        } else {
            selectedTemplateID = defaultVisibleSelectionID(from: visibleTemplates)
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
