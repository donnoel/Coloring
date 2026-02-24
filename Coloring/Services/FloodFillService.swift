import CoreGraphics
import UIKit

protocol FloodFillProviding {
    func floodFill(
        image: CGImage,
        at point: CGPoint,
        with color: UIColor,
        tolerance: Int
    ) -> CGImage?
}

struct FloodFillService: FloodFillProviding {
    func floodFill(
        image: CGImage,
        at point: CGPoint,
        with color: UIColor,
        tolerance: Int
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        let pixelX = Int(point.x)
        let pixelY = Int(point.y)
        guard pixelX >= 0, pixelX < width, pixelY >= 0, pixelY < height else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
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
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return nil
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: totalBytes)

        let targetIndex = (pixelY * bytesPerRow) + (pixelX * bytesPerPixel)
        let targetR = pixels[targetIndex]
        let targetG = pixels[targetIndex + 1]
        let targetB = pixels[targetIndex + 2]
        let targetA = pixels[targetIndex + 3]

        var fillR: UInt8 = 0
        var fillG: UInt8 = 0
        var fillB: UInt8 = 0
        var fillA: UInt8 = 255
        extractRGBA(from: color, r: &fillR, g: &fillG, b: &fillB, a: &fillA)

        // Don't fill if the target pixel already matches the fill color.
        if colorsMatch(targetR, targetG, targetB, targetA, fillR, fillG, fillB, fillA, tolerance: 0) {
            return nil
        }

        let tol = tolerance

        // Scanline flood fill using a stack of (x, y) seed points.
        var stack: [(Int, Int)] = [(pixelX, pixelY)]
        var visited = [Bool](repeating: false, count: width * height)

        while let (seedX, seedY) = stack.popLast() {
            let visitIndex = seedY * width + seedX
            guard !visited[visitIndex] else {
                continue
            }

            let seedPixelIndex = (seedY * bytesPerRow) + (seedX * bytesPerPixel)
            guard colorsMatch(
                pixels[seedPixelIndex], pixels[seedPixelIndex + 1],
                pixels[seedPixelIndex + 2], pixels[seedPixelIndex + 3],
                targetR, targetG, targetB, targetA, tolerance: tol
            ) else {
                continue
            }

            // Scan left to find the start of this span.
            var leftX = seedX
            while leftX > 0 {
                let checkIndex = (seedY * bytesPerRow) + ((leftX - 1) * bytesPerPixel)
                guard colorsMatch(
                    pixels[checkIndex], pixels[checkIndex + 1],
                    pixels[checkIndex + 2], pixels[checkIndex + 3],
                    targetR, targetG, targetB, targetA, tolerance: tol
                ) else {
                    break
                }
                leftX -= 1
            }

            // Scan right filling pixels and checking rows above/below.
            var x = leftX
            var aboveAdded = false
            var belowAdded = false

            while x < width {
                let pixIndex = (seedY * bytesPerRow) + (x * bytesPerPixel)
                guard colorsMatch(
                    pixels[pixIndex], pixels[pixIndex + 1],
                    pixels[pixIndex + 2], pixels[pixIndex + 3],
                    targetR, targetG, targetB, targetA, tolerance: tol
                ) else {
                    break
                }

                // Fill this pixel.
                pixels[pixIndex] = fillR
                pixels[pixIndex + 1] = fillG
                pixels[pixIndex + 2] = fillB
                pixels[pixIndex + 3] = fillA
                visited[seedY * width + x] = true

                // Check pixel above.
                if seedY > 0 {
                    let aboveVisitIndex = (seedY - 1) * width + x
                    if !visited[aboveVisitIndex] {
                        let aboveIndex = ((seedY - 1) * bytesPerRow) + (x * bytesPerPixel)
                        let aboveMatches = colorsMatch(
                            pixels[aboveIndex], pixels[aboveIndex + 1],
                            pixels[aboveIndex + 2], pixels[aboveIndex + 3],
                            targetR, targetG, targetB, targetA, tolerance: tol
                        )
                        if aboveMatches, !aboveAdded {
                            stack.append((x, seedY - 1))
                            aboveAdded = true
                        } else if !aboveMatches {
                            aboveAdded = false
                        }
                    }
                }

                // Check pixel below.
                if seedY < height - 1 {
                    let belowVisitIndex = (seedY + 1) * width + x
                    if !visited[belowVisitIndex] {
                        let belowIndex = ((seedY + 1) * bytesPerRow) + (x * bytesPerPixel)
                        let belowMatches = colorsMatch(
                            pixels[belowIndex], pixels[belowIndex + 1],
                            pixels[belowIndex + 2], pixels[belowIndex + 3],
                            targetR, targetG, targetB, targetA, tolerance: tol
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

        return context.makeImage()
    }

    private func colorsMatch(
        _ r1: UInt8, _ g1: UInt8, _ b1: UInt8, _ a1: UInt8,
        _ r2: UInt8, _ g2: UInt8, _ b2: UInt8, _ a2: UInt8,
        tolerance: Int
    ) -> Bool {
        abs(Int(r1) - Int(r2)) <= tolerance
            && abs(Int(g1) - Int(g2)) <= tolerance
            && abs(Int(b1) - Int(b2)) <= tolerance
            && abs(Int(a1) - Int(a2)) <= tolerance
    }

    private func extractRGBA(from color: UIColor, r: inout UInt8, g: inout UInt8, b: inout UInt8, a: inout UInt8) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        r = UInt8(min(max(red * 255, 0), 255))
        g = UInt8(min(max(green * 255, 0), 255))
        b = UInt8(min(max(blue * 255, 0), 255))
        a = UInt8(min(max(alpha * 255, 0), 255))
    }
}
