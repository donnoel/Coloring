import CoreGraphics
import Foundation

@MainActor
final class TemplateProgressSnapshotCoordinator {
    struct Input {
        static let empty = Input(
            hasColoring: false,
            layerStack: nil,
            fallbackDrawingData: nil,
            fillData: nil,
            canvasSize: .zero,
            currentSnapshot: nil
        )

        let hasColoring: Bool
        let layerStack: LayerStack?
        let fallbackDrawingData: Data?
        let fillData: Data?
        let canvasSize: CGSize
        let currentSnapshot: TemplateProgressSnapshot?
    }

    enum Result {
        case remove(templateID: String)
        case update(snapshot: TemplateProgressSnapshot)
    }

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func scheduleUpdate(
        for templateID: String,
        progressEstimator: TemplateProgressEstimator,
        makeInput: @escaping @MainActor () -> Input,
        onResult: @escaping @MainActor (Result) -> Void
    ) {
        guard !templateID.isEmpty else {
            return
        }

        cancel()
        task = Task { [weak self, templateID, progressEstimator, makeInput] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else {
                return
            }

            let input = makeInput()
            guard input.hasColoring else {
                onResult(.remove(templateID: templateID))
                self?.clearTaskIfCurrent()
                return
            }

            let progress = await progressEstimator.estimateProgress(
                layerStack: input.layerStack,
                fallbackDrawingData: input.fallbackDrawingData,
                fillData: input.fillData,
                canvasSize: input.canvasSize
            )

            guard !Task.isCancelled else {
                return
            }

            guard let progress else {
                onResult(.remove(templateID: templateID))
                self?.clearTaskIfCurrent()
                return
            }

            let snapshot = TemplateProgressSnapshot(templateID: templateID, estimatedProgress: progress)
            guard input.currentSnapshot != snapshot else {
                self?.clearTaskIfCurrent()
                return
            }

            onResult(.update(snapshot: snapshot))
            self?.clearTaskIfCurrent()
        }
    }

    private func clearTaskIfCurrent() {
        task = nil
    }
}
