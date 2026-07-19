import Foundation

enum TemplateEditChangeKind {
    case snapshot
    case canvasStroke
}

final class TemplateEditHistoryStore<Snapshot: Equatable> {
    private struct Entry {
        let snapshot: Snapshot
        let kind: TemplateEditChangeKind
    }

    private struct History {
        var undo: [Entry] = []
        var redo: [Entry] = []
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
    func finalizePendingStrokeIfNeeded(
        for templateID: String,
        currentSnapshot: Snapshot?,
        kind: TemplateEditChangeKind = .canvasStroke
    ) -> Bool {
        guard !templateID.isEmpty,
              let pendingSnapshot = pendingStrokeSnapshots.removeValue(forKey: templateID)
        else {
            return false
        }

        return recordChange(
            from: pendingSnapshot,
            for: templateID,
            currentSnapshot: currentSnapshot,
            kind: kind
        )
    }

    @discardableResult
    func recordChange(
        from previousSnapshot: Snapshot?,
        for templateID: String,
        currentSnapshot: Snapshot?,
        kind: TemplateEditChangeKind = .snapshot
    ) -> Bool {
        guard !templateID.isEmpty,
              let previousSnapshot,
              let currentSnapshot,
              previousSnapshot != currentSnapshot
        else {
            return false
        }

        var history = histories[templateID] ?? History()
        history.undo.append(Entry(snapshot: previousSnapshot, kind: kind))
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
              let previousEntry = history.undo.popLast(),
              let currentSnapshot
        else {
            return nil
        }

        history.redo.append(Entry(snapshot: currentSnapshot, kind: previousEntry.kind))
        histories[templateID] = history
        return previousEntry.snapshot
    }

    func redo(for templateID: String, currentSnapshot: Snapshot?) -> Snapshot? {
        guard !templateID.isEmpty,
              var history = histories[templateID],
              let nextEntry = history.redo.popLast(),
              let currentSnapshot
        else {
            return nil
        }

        history.undo.append(Entry(snapshot: currentSnapshot, kind: nextEntry.kind))
        histories[templateID] = history
        return nextEntry.snapshot
    }

    func nextUndoKind(for templateID: String) -> TemplateEditChangeKind? {
        histories[templateID]?.undo.last?.kind
    }

    func nextRedoKind(for templateID: String) -> TemplateEditChangeKind? {
        histories[templateID]?.redo.last?.kind
    }

    func canUndo(for templateID: String) -> Bool {
        !(histories[templateID]?.undo.isEmpty ?? true)
    }

    func canRedo(for templateID: String) -> Bool {
        !(histories[templateID]?.redo.isEmpty ?? true)
    }
}
