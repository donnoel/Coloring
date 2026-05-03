import Foundation
import UIKit

@MainActor
final class TemplateFillOverlayCoordinator {
    struct Result {
        let templateID: String
        let fillColor: UIColor
        let nextFillData: Data
    }

    private var task: Task<Void, Never>?
    private var operationID = 0

    func cancel() {
        task?.cancel()
        task = nil
        operationID += 1
    }

    func start(
        templateID: String,
        currentFillData: Data?,
        request: FillOverlayRequest,
        floodFillService: any FloodFillProviding,
        onResult: @escaping @MainActor (Result) -> Void
    ) {
        cancel()
        let operationID = operationID
        let fillColor = request.fillColor

        task = Task { [weak self, templateID, currentFillData, request, floodFillService, fillColor] in
            guard let self else {
                return
            }

            defer {
                if self.operationID == operationID {
                    self.task = nil
                }
            }

            let nextFillData = await Task.detached(priority: .userInitiated) {
                FillOverlayRenderer.makeFillOverlayData(
                    request: request,
                    floodFillService: floodFillService
                )
            }.value

            guard !Task.isCancelled,
                  self.operationID == operationID,
                  let nextFillData,
                  nextFillData != currentFillData
            else {
                return
            }

            onResult(
                Result(
                    templateID: templateID,
                    fillColor: fillColor,
                    nextFillData: nextFillData
                )
            )
        }
    }
}
