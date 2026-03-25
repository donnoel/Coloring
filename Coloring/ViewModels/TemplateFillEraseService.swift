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
