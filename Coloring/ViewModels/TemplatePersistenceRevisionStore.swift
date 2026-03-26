import Foundation

struct TemplatePersistenceRevisionStore {
    private var layerRevisionsByTemplateID: [String: Int] = [:]
    private var fillRevisionsByTemplateID: [String: Int] = [:]

    mutating func retainRevisions(for templateIDs: Set<String>) {
        layerRevisionsByTemplateID = layerRevisionsByTemplateID.filter { templateIDs.contains($0.key) }
        fillRevisionsByTemplateID = fillRevisionsByTemplateID.filter { templateIDs.contains($0.key) }
    }

    mutating func renameRevisions(from oldTemplateID: String, to newTemplateID: String) {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let layerRevision = layerRevisionsByTemplateID.removeValue(forKey: oldTemplateID) {
            layerRevisionsByTemplateID[newTemplateID] = layerRevision
        }
        if let fillRevision = fillRevisionsByTemplateID.removeValue(forKey: oldTemplateID) {
            fillRevisionsByTemplateID[newTemplateID] = fillRevision
        }
    }

    mutating func removeRevisions(for templateID: String) {
        layerRevisionsByTemplateID.removeValue(forKey: templateID)
        fillRevisionsByTemplateID.removeValue(forKey: templateID)
    }

    mutating func nextLayerRevision(for templateID: String) -> Int {
        let nextRevision = (layerRevisionsByTemplateID[templateID] ?? 0) + 1
        layerRevisionsByTemplateID[templateID] = nextRevision
        return nextRevision
    }

    mutating func nextFillRevision(for templateID: String) -> Int {
        let nextRevision = (fillRevisionsByTemplateID[templateID] ?? 0) + 1
        fillRevisionsByTemplateID[templateID] = nextRevision
        return nextRevision
    }
}
