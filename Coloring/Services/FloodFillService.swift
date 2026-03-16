import CoreGraphics
import UIKit

protocol FloodFillProviding: Sendable {
    nonisolated func floodFill(
        image: CGImage,
        at point: CGPoint,
        with color: UIColor,
        tolerance: Int
    ) -> CGImage?
}

struct FillOverlayRequest: @unchecked Sendable {
    let templateImage: UIImage
    let existingFillImage: UIImage?
    let normalizedPoint: CGPoint
    let fillColor: UIColor
}

enum FillOverlayRenderer {
    nonisolated static func makeFillOverlayData(
        request: FillOverlayRequest,
        floodFillService: any FloodFillProviding
    ) -> Data? {
        let fillCanvasSize = normalizedCanvasSize(for: request.templateImage.size)
        let renderedTemplate = renderTemplateForFill(request.templateImage, canvasSize: fillCanvasSize)
        guard let templateCGImage = renderedTemplate.cgImage else {
            return nil
        }

        let clampedPoint = CGPoint(
            x: min(max(request.normalizedPoint.x, 0), 1),
            y: min(max(request.normalizedPoint.y, 0), 1)
        )
        let imagePoint = CGPoint(
            x: clampedPoint.x * CGFloat(max(templateCGImage.width - 1, 0)),
            y: clampedPoint.y * CGFloat(max(templateCGImage.height - 1, 0))
        )

        guard let baseImage = compositeBaseImageForFill(
            templateImage: renderedTemplate,
            existingFillImage: request.existingFillImage
        ) else {
            return nil
        }

        guard let filledImage = floodFillService.floodFill(
            image: baseImage,
            at: imagePoint,
            with: request.fillColor,
            tolerance: 40
        ) else {
            return nil
        }

        let fillOverlay = extractFillOverlay(
            filledComposite: filledImage,
            templateCGImage: templateCGImage,
            existingFillImage: request.existingFillImage
        )
        return fillOverlay.pngData()
    }

    private nonisolated static func normalizedCanvasSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: 2048, height: 1536)
        }

        let longEdge = max(size.width, size.height)
        guard longEdge > 2048 else {
            return size
        }

        let scale = 2048 / longEdge
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private nonisolated static func renderTemplateForFill(_ templateImage: UIImage, canvasSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvasSize))
            templateImage.draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }

    private nonisolated static func compositeBaseImageForFill(
        templateImage: UIImage,
        existingFillImage: UIImage?
    ) -> CGImage? {
        let size = templateImage.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let composited = renderer.image { _ in
            templateImage.draw(in: CGRect(origin: .zero, size: size))
            if let existingFillImage {
                existingFillImage.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return composited.cgImage ?? templateImage.cgImage
    }

    private nonisolated static func extractFillOverlay(
        filledComposite: CGImage,
        templateCGImage: CGImage,
        existingFillImage: UIImage?
    ) -> UIImage {
        let width = templateCGImage.width
        let height = templateCGImage.height
        let size = CGSize(width: width, height: height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return UIImage(cgImage: filledComposite)
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let templateContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let templateData = templateContext.data else {
            return UIImage(cgImage: filledComposite)
        }
        templateContext.draw(templateCGImage, in: CGRect(origin: .zero, size: size))
        let templatePixels = templateData.bindMemory(to: UInt8.self, capacity: totalBytes)

        guard let filledContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let filledData = filledContext.data else {
            return UIImage(cgImage: filledComposite)
        }
        filledContext.draw(filledComposite, in: CGRect(origin: .zero, size: size))
        let filledPixels = filledData.bindMemory(to: UInt8.self, capacity: totalBytes)

        guard let overlayContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let overlayData = overlayContext.data else {
            return UIImage(cgImage: filledComposite)
        }

        if let existingFill = existingFillImage?.cgImage {
            overlayContext.draw(existingFill, in: CGRect(origin: .zero, size: size))
        }

        let overlayPixels = overlayData.bindMemory(to: UInt8.self, capacity: totalBytes)

        for index in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
            let templateR = templatePixels[index]
            let templateG = templatePixels[index + 1]
            let templateB = templatePixels[index + 2]
            let filledR = filledPixels[index]
            let filledG = filledPixels[index + 1]
            let filledB = filledPixels[index + 2]

            let differs = abs(Int(templateR) - Int(filledR)) > 2
                || abs(Int(templateG) - Int(filledG)) > 2
                || abs(Int(templateB) - Int(filledB)) > 2

            if differs {
                overlayPixels[index] = filledR
                overlayPixels[index + 1] = filledG
                overlayPixels[index + 2] = filledB
                overlayPixels[index + 3] = filledPixels[index + 3]
            }
        }

        guard let overlayCGImage = overlayContext.makeImage() else {
            return UIImage(cgImage: filledComposite)
        }
        return UIImage(cgImage: overlayCGImage)
    }
}

struct FloodFillService: FloodFillProviding {
    nonisolated func floodFill(
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

    private nonisolated func colorsMatch(
        _ r1: UInt8, _ g1: UInt8, _ b1: UInt8, _ a1: UInt8,
        _ r2: UInt8, _ g2: UInt8, _ b2: UInt8, _ a2: UInt8,
        tolerance: Int
    ) -> Bool {
        abs(Int(r1) - Int(r2)) <= tolerance
            && abs(Int(g1) - Int(g2)) <= tolerance
            && abs(Int(b1) - Int(b2)) <= tolerance
            && abs(Int(a1) - Int(a2)) <= tolerance
    }

    private nonisolated func extractRGBA(from color: UIColor, r: inout UInt8, g: inout UInt8, b: inout UInt8, a: inout UInt8) {
        let normalizedColor = color.stableResolvedColor(using: UITraitCollection(userInterfaceStyle: .light))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if normalizedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            r = UInt8(min(max(red * 255, 0), 255))
            g = UInt8(min(max(green * 255, 0), 255))
            b = UInt8(min(max(blue * 255, 0), 255))
            a = UInt8(min(max(alpha * 255, 0), 255))
            return
        }

        var white: CGFloat = 0
        if normalizedColor.getWhite(&white, alpha: &alpha) {
            let value = UInt8(min(max(white * 255, 0), 255))
            r = value
            g = value
            b = value
            a = UInt8(min(max(alpha * 255, 0), 255))
            return
        }

        if let stableColor = normalizedColor.cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ), let components = stableColor.components {
            let alphaComponent = components.count > 3 ? components[3] : 1
            r = UInt8(min(max(components[0] * 255, 0), 255))
            g = UInt8(min(max(components[1] * 255, 0), 255))
            b = UInt8(min(max(components[2] * 255, 0), 255))
            a = UInt8(min(max(alphaComponent * 255, 0), 255))
            return
        }

        // Keep behavior deterministic instead of leaking uninitialized values if conversion fails.
        r = 0
        g = 0
        b = 0
        a = 255
    }
}
