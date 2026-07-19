import CoreGraphics
import Foundation
import UIKit

struct TemplateFillEraseResult {
    let didChange: Bool
    let fillData: Data?
    let fillImage: UIImage?
}

enum TemplateFillEraseService {
    static func eraseRegion(in fillImage: UIImage, at normalizedPoint: CGPoint) -> TemplateFillEraseResult {
        guard let fillCGImage = fillImage.cgImage else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let width = fillCGImage.width
        let height = fillCGImage.height
        guard width > 0, height > 0 else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let clampedPoint = CGPoint(
            x: min(max(normalizedPoint.x, 0), 1),
            y: min(max(normalizedPoint.y, 0), 1)
        )
        let pixelX = min(max(Int(clampedPoint.x * CGFloat(max(width - 1, 0))), 0), width - 1)
        let pixelY = min(max(Int(clampedPoint.y * CGFloat(max(height - 1, 0))), 0), height - 1)

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        context.draw(fillCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: totalBytes)
        let targetIndex = (pixelY * bytesPerRow) + (pixelX * bytesPerPixel)
        let targetAlpha = pixels[targetIndex + 3]
        guard targetAlpha > 0 else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let targetRed = pixels[targetIndex]
        let targetGreen = pixels[targetIndex + 1]
        let targetBlue = pixels[targetIndex + 2]
        let tolerance = 12

        var stack: [(Int, Int)] = [(pixelX, pixelY)]
        var visited = [Bool](repeating: false, count: width * height)
        var didErase = false

        while let (seedX, seedY) = stack.popLast() {
            guard !FillEraseCancellation.isCancelled() else {
                return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
            }

            let visitIndex = seedY * width + seedX
            guard !visited[visitIndex] else {
                continue
            }

            let seedPixelIndex = (seedY * bytesPerRow) + (seedX * bytesPerPixel)
            guard pixelMatchesTarget(
                pixels: pixels,
                pixelIndex: seedPixelIndex,
                targetRed: targetRed,
                targetGreen: targetGreen,
                targetBlue: targetBlue,
                tolerance: tolerance
            ) else {
                continue
            }

            var leftX = seedX
            while leftX > 0 {
                let checkIndex = (seedY * bytesPerRow) + ((leftX - 1) * bytesPerPixel)
                guard pixelMatchesTarget(
                    pixels: pixels,
                    pixelIndex: checkIndex,
                    targetRed: targetRed,
                    targetGreen: targetGreen,
                    targetBlue: targetBlue,
                    tolerance: tolerance
                ) else {
                    break
                }
                leftX -= 1
            }

            var x = leftX
            var aboveAdded = false
            var belowAdded = false

            while x < width {
                if x.isMultiple(of: 256), FillEraseCancellation.isCancelled() {
                    return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
                }

                let pixelIndex = (seedY * bytesPerRow) + (x * bytesPerPixel)
                guard pixelMatchesTarget(
                    pixels: pixels,
                    pixelIndex: pixelIndex,
                    targetRed: targetRed,
                    targetGreen: targetGreen,
                    targetBlue: targetBlue,
                    tolerance: tolerance
                ) else {
                    break
                }

                pixels[pixelIndex] = 0
                pixels[pixelIndex + 1] = 0
                pixels[pixelIndex + 2] = 0
                pixels[pixelIndex + 3] = 0
                visited[seedY * width + x] = true
                didErase = true

                if seedY > 0 {
                    let aboveVisitIndex = (seedY - 1) * width + x
                    if !visited[aboveVisitIndex] {
                        let aboveIndex = ((seedY - 1) * bytesPerRow) + (x * bytesPerPixel)
                        let aboveMatches = pixelMatchesTarget(
                            pixels: pixels,
                            pixelIndex: aboveIndex,
                            targetRed: targetRed,
                            targetGreen: targetGreen,
                            targetBlue: targetBlue,
                            tolerance: tolerance
                        )
                        if aboveMatches, !aboveAdded {
                            stack.append((x, seedY - 1))
                            aboveAdded = true
                        } else if !aboveMatches {
                            aboveAdded = false
                        }
                    }
                }

                if seedY < height - 1 {
                    let belowVisitIndex = (seedY + 1) * width + x
                    if !visited[belowVisitIndex] {
                        let belowIndex = ((seedY + 1) * bytesPerRow) + (x * bytesPerPixel)
                        let belowMatches = pixelMatchesTarget(
                            pixels: pixels,
                            pixelIndex: belowIndex,
                            targetRed: targetRed,
                            targetGreen: targetGreen,
                            targetBlue: targetBlue,
                            tolerance: tolerance
                        )
                        if belowMatches, !belowAdded {
                            stack.append((x, seedY + 1))
                            belowAdded = true
                        } else if !belowMatches {
                            belowAdded = false
                        }
                    }
                }

                x += 1
            }
        }

        guard didErase else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        guard !FillEraseCancellation.isCancelled() else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let hasVisiblePixels = stride(from: 0, to: totalBytes, by: bytesPerPixel)
            .contains { pixels[$0 + 3] > 0 }
        guard hasVisiblePixels else {
            return TemplateFillEraseResult(didChange: true, fillData: nil, fillImage: nil)
        }

        guard let erasedCGImage = context.makeImage() else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        let erasedImage = UIImage(cgImage: erasedCGImage)
        guard let fillData = erasedImage.pngData() else {
            return TemplateFillEraseResult(didChange: false, fillData: nil, fillImage: nil)
        }

        return TemplateFillEraseResult(didChange: true, fillData: fillData, fillImage: erasedImage)
    }

    private static func pixelMatchesTarget(
        pixels: UnsafeMutablePointer<UInt8>,
        pixelIndex: Int,
        targetRed: UInt8,
        targetGreen: UInt8,
        targetBlue: UInt8,
        tolerance: Int
    ) -> Bool {
        let alpha = pixels[pixelIndex + 3]
        guard alpha > 0 else {
            return false
        }

        return abs(Int(pixels[pixelIndex]) - Int(targetRed)) <= tolerance
            && abs(Int(pixels[pixelIndex + 1]) - Int(targetGreen)) <= tolerance
            && abs(Int(pixels[pixelIndex + 2]) - Int(targetBlue)) <= tolerance
    }
}

@MainActor
final class TemplateFillEraseCoordinator {
    struct Result {
        let templateID: String
        let fillData: Data
    }

    private let worker = TemplateFillEraseRasterWorker()
    private var task: Task<Void, Never>?
    private var operationID = 0
    private var templateID = ""
    private var initialFillData = Data()
    private var pendingPoints: [CGPoint] = []
    private var lastQueuedPoint: CGPoint?
    private var isFinishing = false
    private var onResult: ((Result) -> Void)?
    private var onFinish: (() -> Void)?
    private let minimumPointDistance: CGFloat = 1.0 / 1024.0
    private let maximumQueuedPointCount = 64

    func startSession(
        templateID: String,
        fillData: Data,
        onResult: @escaping (Result) -> Void,
        onFinish: @escaping () -> Void
    ) {
        cancel()
        self.templateID = templateID
        initialFillData = fillData
        self.onResult = onResult
        self.onFinish = onFinish
    }

    func enqueue(_ normalizedPoint: CGPoint) {
        guard !templateID.isEmpty, !isFinishing else {
            return
        }

        if let lastQueuedPoint {
            let distance = hypot(
                normalizedPoint.x - lastQueuedPoint.x,
                normalizedPoint.y - lastQueuedPoint.y
            )
            guard distance >= minimumPointDistance else {
                return
            }
        }

        lastQueuedPoint = normalizedPoint
        if pendingPoints.count >= maximumQueuedPointCount {
            pendingPoints[pendingPoints.count - 1] = normalizedPoint
        } else {
            pendingPoints.append(normalizedPoint)
        }
        processNextPointIfNeeded()
    }

    func finishSession() {
        guard !templateID.isEmpty else {
            return
        }

        isFinishing = true
        finishIfIdle()
    }

    func cancel() {
        task?.cancel()
        task = nil
        operationID += 1
        templateID = ""
        initialFillData = Data()
        pendingPoints.removeAll(keepingCapacity: true)
        lastQueuedPoint = nil
        isFinishing = false
        onResult = nil
        onFinish = nil
    }

    private func processNextPointIfNeeded() {
        guard task == nil else {
            return
        }
        guard !pendingPoints.isEmpty else {
            finishIfIdle()
            return
        }

        let normalizedPoint = pendingPoints.removeFirst()
        let operationID = operationID
        let templateID = templateID
        let initialFillData = initialFillData
        task = Task { [weak self, worker] in
            let fillData = await worker.eraseRegion(
                sessionID: operationID,
                initialFillData: initialFillData,
                at: normalizedPoint
            )
            guard let self,
                  !Task.isCancelled,
                  self.operationID == operationID
            else {
                return
            }

            self.task = nil
            if let fillData {
                self.onResult?(Result(templateID: templateID, fillData: fillData))
                if fillData.isEmpty {
                    self.pendingPoints.removeAll(keepingCapacity: true)
                }
            }
            self.processNextPointIfNeeded()
        }
    }

    private func finishIfIdle() {
        guard isFinishing, task == nil, pendingPoints.isEmpty else {
            return
        }

        let onFinish = onFinish
        cancel()
        onFinish?()
    }
}

private actor TemplateFillEraseRasterWorker {
    private var sessionID: Int?
    private var fillImage: UIImage?

    func eraseRegion(
        sessionID: Int,
        initialFillData: Data,
        at normalizedPoint: CGPoint
    ) -> Data? {
        guard !Task.isCancelled else {
            return nil
        }

        if self.sessionID != sessionID {
            self.sessionID = sessionID
            fillImage = UIImage(data: initialFillData)
        }

        guard let fillImage else {
            return nil
        }

        let result = TemplateFillEraseService.eraseRegion(in: fillImage, at: normalizedPoint)
        guard !Task.isCancelled, result.didChange else {
            return nil
        }

        self.fillImage = result.fillImage
        return result.fillData ?? Data()
    }
}

private enum FillEraseCancellation {
    nonisolated static func isCancelled() -> Bool {
        withUnsafeCurrentTask { task in
            task?.isCancelled ?? false
        }
    }
}
