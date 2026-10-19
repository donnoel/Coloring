import PencilKit
import UIKit
import XCTest
@testable import Coloring

final class PencilDrawingRenderCacheServiceTests: XCTestCase {
    @MainActor
    func testCachePreservesTransparentStrokeAlphaAndFullCanvasAlignment() async throws {
        let canvasSize = CGSize(width: 128, height: 96)
        let drawing = makeDrawing(canvasSize: canvasSize, color: UIColor.red.withAlphaComponent(0.4))
        let renderedImage = await PencilDrawingRenderCacheService().image(for: .init(
            drawing: drawing,
            canvasSize: canvasSize
        ))
        let image = try XCTUnwrap(renderedImage)

        XCTAssertEqual(image.size, canvasSize)
        let strokePixel = try pixel(image, x: 64, y: 48)
        XCTAssertGreaterThan(strokePixel.alpha, 0.1)
        XCTAssertLessThan(strokePixel.alpha, 0.8)
        XCTAssertGreaterThan(strokePixel.red, 0.85)
        XCTAssertLessThan(strokePixel.green, 0.15)
        XCTAssertLessThan(strokePixel.blue, 0.15)
        XCTAssertEqual(try pixel(image, x: 64, y: 8).alpha, 0)
        XCTAssertEqual(try pixel(image, x: 8, y: 48).alpha, 0)
    }

    @MainActor
    func testCacheBoundsPixelsAndPreservesLandscapeAndPortraitAspect() async throws {
        let renderer = PencilDrawingRenderCacheService()
        for canvasSize in [
            CGSize(width: 8_192, height: 4_096),
            CGSize(width: 4_096, height: 8_192),
            CGSize(width: 8_192, height: 8_192)
        ] {
            let drawing = makeDrawing(canvasSize: canvasSize)
            let renderedImage = await renderer.image(for: .init(
                drawing: drawing,
                canvasSize: canvasSize,
                maximumLongEdge: 4_096
            ))
            let image = try XCTUnwrap(renderedImage)
            let cgImage = try XCTUnwrap(image.cgImage)

            XCTAssertEqual(max(cgImage.width, cgImage.height), 2_048)
            XCTAssertEqual(CGFloat(cgImage.width) / CGFloat(cgImage.height), canvasSize.width / canvasSize.height, accuracy: 0.001)
            XCTAssertEqual(cgImage.bitsPerComponent, 8)
            XCTAssertEqual(cgImage.bitsPerPixel, 32)
            XCTAssertLessThanOrEqual(cgImage.bytesPerRow * cgImage.height, 16 * 1_024 * 1_024)
        }
    }

    @MainActor
    func testCacheRespectsSmallerRequestedPixelLimit() async throws {
        let canvasSize = CGSize(width: 1_600, height: 1_200)
        let renderedImage = await PencilDrawingRenderCacheService().image(for: .init(
            drawing: makeDrawing(canvasSize: canvasSize),
            canvasSize: canvasSize,
            maximumLongEdge: 400
        ))
        let image = try XCTUnwrap(renderedImage)

        XCTAssertEqual(image.size, CGSize(width: 400, height: 300))
    }

    @MainActor
    func testCacheResolvesLightInkWithoutMutatingTheDrawing() async throws {
        let canvasSize = CGSize(width: 128, height: 96)
        let drawing = makeDrawing(canvasSize: canvasSize, color: .label)
        let originalData = drawing.dataRepresentation()
        let renderedImage = await PencilDrawingRenderCacheService().image(for: .init(
            drawing: drawing,
            canvasSize: canvasSize
        ))
        let image = try XCTUnwrap(renderedImage)

        let strokePixel = try pixel(image, x: 64, y: 48)
        XCTAssertGreaterThan(strokePixel.alpha, 0.95)
        XCTAssertLessThan(strokePixel.red, 0.05)
        XCTAssertLessThan(strokePixel.green, 0.05)
        XCTAssertLessThan(strokePixel.blue, 0.05)
        XCTAssertEqual(drawing.dataRepresentation(), originalData)
    }

    @MainActor
    func testCacheSkipsCancelledWorkAndEmptyDrawing() async {
        let renderer = PencilDrawingRenderCacheService()
        let request = PencilDrawingRenderCacheRequest(
            drawing: makeDrawing(canvasSize: CGSize(width: 128, height: 96)),
            canvasSize: CGSize(width: 128, height: 96)
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await renderer.image(for: request)
        }
        let cancelledImage = await task.value
        let emptyImage = await renderer.image(for: .init(drawing: PKDrawing(), canvasSize: request.canvasSize))

        XCTAssertNil(cancelledImage)
        XCTAssertNil(emptyImage)
    }

    @MainActor
    func testCacheBypassesPencilAndMixedInkWithoutChangingStrokes() async {
        let canvasSize = CGSize(width: 128, height: 96)
        let pencil = makeDrawing(canvasSize: canvasSize, inkType: .pencil)
        let pen = makeDrawing(canvasSize: canvasSize)
        let renderer = PencilDrawingRenderCacheService()
        for drawing in [
            pencil,
            PKDrawing(strokes: pencil.strokes + pen.strokes),
            PKDrawing(strokes: pen.strokes + pencil.strokes)
        ] {
            let originalData = drawing.dataRepresentation()
            let image = await renderer.image(for: .init(drawing: drawing, canvasSize: canvasSize))

            XCTAssertNil(image)
            XCTAssertEqual(drawing.dataRepresentation(), originalData)
        }
    }

    @MainActor
    private func makeDrawing(canvasSize: CGSize, color: UIColor = .black, inkType: PKInk.InkType = .pen) -> PKDrawing {
        let points = [canvasSize.width / 4, canvasSize.width * 3 / 4].enumerated().map { index, x in
            PKStrokePoint(
                location: CGPoint(x: x, y: canvasSize.height / 2),
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKDrawing(strokes: [PKStroke(
            ink: PKInk(inkType, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )])
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let pixelImage = try XCTUnwrap(cgImage.cropping(to: CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let didDraw = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(didDraw)
        let alpha = CGFloat(bytes[3])
        return (
            alpha > 0 ? CGFloat(bytes[0]) / alpha : 0,
            alpha > 0 ? CGFloat(bytes[1]) / alpha : 0,
            alpha > 0 ? CGFloat(bytes[2]) / alpha : 0,
            alpha / 255
        )
    }
}
