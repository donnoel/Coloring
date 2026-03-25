import Foundation

actor TemplateColoringPersistenceCoordinator {
    private let drawingStore: any TemplateDrawingStoreProviding
    private var latestLayerRevisionByTemplateID: [String: Int] = [:]
    private var latestFillRevisionByTemplateID: [String: Int] = [:]

    init(drawingStore: any TemplateDrawingStoreProviding) {
        self.drawingStore = drawingStore
    }

    func persistLayerStackData(_ data: Data, for templateID: String, revision: Int) async {
        guard shouldPersistLayerRevision(revision, for: templateID) else {
            return
        }

        try? await drawingStore.saveLayerStackData(data, for: templateID)
    }

    func persistFillData(_ fillData: Data?, for templateID: String, revision: Int) async {
        guard shouldPersistFillRevision(revision, for: templateID) else {
            return
        }

        let persistedFillData = fillData ?? Data()
        try? await drawingStore.saveFillData(persistedFillData, for: templateID)
    }

    func renameTracking(from oldTemplateID: String, to newTemplateID: String) {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let previousLayerRevision = latestLayerRevisionByTemplateID.removeValue(forKey: oldTemplateID) {
            latestLayerRevisionByTemplateID[newTemplateID] = max(
                latestLayerRevisionByTemplateID[newTemplateID] ?? 0,
                previousLayerRevision
            )
        }

        if let previousFillRevision = latestFillRevisionByTemplateID.removeValue(forKey: oldTemplateID) {
            latestFillRevisionByTemplateID[newTemplateID] = max(
                latestFillRevisionByTemplateID[newTemplateID] ?? 0,
                previousFillRevision
            )
        }
    }

    func removeTracking(for templateID: String) {
        latestLayerRevisionByTemplateID.removeValue(forKey: templateID)
        latestFillRevisionByTemplateID.removeValue(forKey: templateID)
    }

    private func shouldPersistLayerRevision(_ revision: Int, for templateID: String) -> Bool {
        guard !templateID.isEmpty, revision > 0 else {
            return false
        }

        let latestRevision = latestLayerRevisionByTemplateID[templateID] ?? 0
        guard revision >= latestRevision else {
            return false
        }

        latestLayerRevisionByTemplateID[templateID] = revision
        return true
    }

    private func shouldPersistFillRevision(_ revision: Int, for templateID: String) -> Bool {
        guard !templateID.isEmpty, revision > 0 else {
            return false
        }

        let latestRevision = latestFillRevisionByTemplateID[templateID] ?? 0
        guard revision >= latestRevision else {
            return false
        }

        latestFillRevisionByTemplateID[templateID] = revision
        return true
    }
}
