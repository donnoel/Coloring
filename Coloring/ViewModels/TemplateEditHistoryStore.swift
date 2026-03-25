import Foundation

final class TemplateEditHistoryStore<Snapshot: Equatable> {
    private struct History {
        var undo: [Snapshot] = []
        var redo: [Snapshot] = []
    }

    private var histories: [String: History] = [:]
    private var pendingStrokeSnapshots: [String: Snapshot] = [:]
    private let maxSteps: Int

    init(maxSteps: Int) {
        self.maxSteps = max(1, maxSteps)
    }

    func retainHistories(for templateIDs: Set<String>) {
        histories = histories.filter { templateIDs.contains($0.key) }
        pendingStrokeSnapshots = pendingStrokeSnapshots.filter { templateIDs.contains($0.key) }
    }

    func renameHistory(from oldTemplateID: String, to newTemplateID: String) {
        guard oldTemplateID != newTemplateID else {
            return
        }

        if let history = histories.removeValue(forKey: oldTemplateID) {
            histories[newTemplateID] = history
        }
        if let pending = pendingStrokeSnapshots.removeValue(forKey: oldTemplateID) {
            pendingStrokeSnapshots[newTemplateID] = pending
        }
    }

    func removeHistory(for templateID: String) {
        histories.removeValue(forKey: templateID)
        pendingStrokeSnapshots.removeValue(forKey: templateID)
    }

    func hasPendingStroke(for templateID: String) -> Bool {
        pendingStrokeSnapshots[templateID] != nil
    }

    func beginPendingStrokeIfNeeded(for templateID: String, snapshot: Snapshot?) {
        guard !templateID.isEmpty,
              pendingStrokeSnapshots[templateID] == nil,
              let snapshot
        else {
            return
        }

        pendingStrokeSnapshots[templateID] = snapshot
    }

    @discardableResult
    func finalizePendingStrokeIfNeeded(for templateID: String, currentSnapshot: Snapshot?) -> Bool {
        guard !templateID.isEmpty,
              let pendingSnapshot = pendingStrokeSnapshots.removeValue(forKey: templateID)
        else {
            return false
        }

        return recordChange(from: pendingSnapshot, for: templateID, currentSnapshot: currentSnapshot)
    }

    @discardableResult
    func recordChange(from previousSnapshot: Snapshot?, for templateID: String, currentSnapshot: Snapshot?) -> Bool {
        guard !templateID.isEmpty,
              let previousSnapshot,
              let currentSnapshot,
              previousSnapshot != currentSnapshot
        else {
            return false
        }

        var history = histories[templateID] ?? History()
        history.undo.append(previousSnapshot)
        if history.undo.count > maxSteps {
            history.undo.removeFirst(history.undo.count - maxSteps)
        }
        history.redo.removeAll(keepingCapacity: true)
        histories[templateID] = history
        return true
    }

    func undo(for templateID: String, currentSnapshot: Snapshot?) -> Snapshot? {
        guard !templateID.isEmpty,
              var history = histories[templateID],
              let previousSnapshot = history.undo.popLast(),
              let currentSnapshot
        else {
            return nil
        }

        history.redo.append(currentSnapshot)
        histories[templateID] = history
        return previousSnapshot
    }

    func redo(for templateID: String, currentSnapshot: Snapshot?) -> Snapshot? {
        guard !templateID.isEmpty,
              var history = histories[templateID],
              let nextSnapshot = history.redo.popLast(),
              let currentSnapshot
        else {
            return nil
        }

        history.undo.append(currentSnapshot)
        histories[templateID] = history
        return nextSnapshot
    }

    func canUndo(for templateID: String) -> Bool {
        !(histories[templateID]?.undo.isEmpty ?? true)
    }

    func canRedo(for templateID: String) -> Bool {
        !(histories[templateID]?.redo.isEmpty ?? true)
    }
}
