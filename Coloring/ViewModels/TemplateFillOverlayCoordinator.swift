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
    private let rasterWorker = TemplateFillRasterWorker()

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

            let nextFillData = await self.rasterWorker.makeFillOverlayData(
                request: request,
                floodFillService: floodFillService
            )

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

private actor TemplateFillRasterWorker {
    func makeFillOverlayData(
        request: FillOverlayRequest,
        floodFillService: any FloodFillProviding
    ) -> Data? {
        guard !Task.isCancelled else {
            return nil
        }

        return FillOverlayRenderer.makeFillOverlayData(
            request: request,
            floodFillService: floodFillService
        )
    }
}
