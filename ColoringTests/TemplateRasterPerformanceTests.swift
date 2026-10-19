import PencilKit
import UIKit
import XCTest
@testable import Coloring

final class TemplateRasterPerformanceTests: XCTestCase {
    @MainActor
    func testCoveragePreservesStrokeGeometryAcrossLargeCanvasOrientations() async throws {
        let estimator = TemplateProgressEstimator()
        for canvasSize in [
            CGSize(width: 2_048, height: 1_536),
            CGSize(width: 1_536, height: 2_048),
            CGSize(width: 2_048, height: 2_048)
        ] {
            let drawing = horizontalDrawing(canvasSize: canvasSize, width: canvasSize.height / 4)
            let expectedCoverage = drawing.bounds.height / canvasSize.height
            XCTAssertEqual(expectedCoverage, 0.5, accuracy: 0.01)
            let progress = await estimator.estimateProgress(
                layerStack: .singleLayer(drawingData: drawing.dataRepresentation()),
                fallbackDrawingData: nil,
                fillData: nil,
                canvasSize: canvasSize
            )

            XCTAssertEqual(
                try XCTUnwrap(progress),
                Double(expectedCoverage),
                accuracy: 0.04,
                "canvas=\(canvasSize), bounds=\(drawing.bounds)"
            )
        }
    }

    @MainActor
    func testCoverageCountsTranslucentBlackFillUsingAlpha() async throws {
        let fillData = try XCTUnwrap(image(color: UIColor.black.withAlphaComponent(0.25)).pngData())
        let estimator = TemplateProgressEstimator()
        let progress = await estimator.estimateProgress(
            layerStack: nil,
            fallbackDrawingData: nil,
            fillData: fillData,
            canvasSize: CGSize(width: 80, height: 60)
        )

        XCTAssertEqual(try XCTUnwrap(progress), 0.99, accuracy: 0.001)
    }

    @MainActor
    func testBackgroundWidgetRendererPreservesLayerOrderAndLightInkColors() async throws {
        let canvasSize = CGSize(width: 2_048, height: 1_536)
        let input = TemplateWidgetArtworkRenderer.Input(
            templateImage: image(color: .clear),
            drawing: horizontalDrawing(canvasSize: canvasSize, width: 120, color: .label),
            fillImage: image(color: .red),
            belowLayerImage: image(color: .blue, horizontalRange: 0...0.25),
            aboveLayerImage: image(color: .green, horizontalRange: 0.75...1),
            canvasSize: canvasSize
        )
        let renderer = TemplateWidgetArtworkRenderer()
        let renderedData = await renderer.makeImageData(for: input)
        let preview = try XCTUnwrap(UIImage(data: XCTUnwrap(renderedData)))

        XCTAssertEqual(preview.size.width, 720, accuracy: 0.5)
        XCTAssertEqual(preview.size.height, 540, accuracy: 0.5)
        assertPixel(preview, x: 0.1, y: 0.2, red: 0, green: 0, blue: 1)
        assertPixel(preview, x: 0.5, y: 0.2, red: 1, green: 0, blue: 0)
        assertPixel(preview, x: 0.1, y: 0.5, red: 0, green: 0, blue: 0)
        assertPixel(preview, x: 0.9, y: 0.5, red: 0, green: 1, blue: 0)
    }

    @MainActor
    func testBackgroundWidgetRendererKeepsTransparentArtworkWhiteWithoutUpscaling() async throws {
        let input = TemplateWidgetArtworkRenderer.Input(
            templateImage: image(color: .clear),
            drawing: PKDrawing(),
            fillImage: nil,
            belowLayerImage: nil,
            aboveLayerImage: nil,
            canvasSize: CGSize(width: 80, height: 120)
        )
        let renderer = TemplateWidgetArtworkRenderer()
        let renderedData = await renderer.makeImageData(for: input)
        let preview = try XCTUnwrap(UIImage(data: XCTUnwrap(renderedData)))

        XCTAssertEqual(preview.size, CGSize(width: 80, height: 120))
        assertPixel(preview, x: 0.5, y: 0.5, red: 1, green: 1, blue: 1)
    }

    @MainActor
    func testBackgroundWidgetRendererSkipsAlreadyCancelledWork() async {
        let renderer = TemplateWidgetArtworkRenderer()
        let input = TemplateWidgetArtworkRenderer.Input(
            templateImage: image(color: .white),
            drawing: PKDrawing(),
            fillImage: nil,
            belowLayerImage: nil,
            aboveLayerImage: nil,
            canvasSize: CGSize(width: 80, height: 120)
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await renderer.makeImageData(for: input)
        }

        let renderedData = await task.value
        XCTAssertNil(renderedData)
    }

    func testIdenticalWidgetArtworkSkipsPersistenceAndTimelineReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("widget.json")
        let reloadCounter = TimelineReloadCounter()
        let writer = ColoringWidgetSnapshotWriter(
            fileURLProvider: { fileURL },
            timelineReloader: { reloadCounter.increment() }
        )

        await writer.updateCurrentArtwork(templateID: "drawing", title: "Drawing", progress: 0.2, imageData: Data([1]))
        let firstSnapshot = ColoringWidgetSnapshotStore.load(from: fileURL)
        await writer.updateCurrentArtwork(templateID: "drawing", title: "Drawing", progress: 0.2, imageData: Data([1]))

        XCTAssertEqual(reloadCounter.value, 1)
        XCTAssertEqual(ColoringWidgetSnapshotStore.load(from: fileURL), firstSnapshot)

        await writer.updateCurrentArtwork(templateID: "drawing", title: "Drawing", progress: 0.4, imageData: Data([1]))

        XCTAssertEqual(reloadCounter.value, 2)
        XCTAssertEqual(ColoringWidgetSnapshotStore.load(from: fileURL).currentArtwork?.progress, 0.4)
    }

    @MainActor
    private func horizontalDrawing(
        canvasSize: CGSize,
        width: CGFloat,
        color: UIColor = .black
    ) -> PKDrawing {
        let points = [-canvasSize.width, canvasSize.width * 2].enumerated().map { index, x in
            PKStrokePoint(
                location: CGPoint(x: x, y: canvasSize.height / 2),
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let stroke = PKStroke(
            ink: PKInk(.pen, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
        return PKDrawing(strokes: [stroke])
    }

    @MainActor
    private func image(color: UIColor, horizontalRange: ClosedRange<CGFloat> = 0...1) -> UIImage {
        let size = CGSize(width: 80, height: 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(
                x: size.width * horizontalRange.lowerBound,
                y: 0,
                width: size.width * (horizontalRange.upperBound - horizontalRange.lowerBound),
                height: size.height
            ))
        }
    }

    private func assertPixel(
        _ image: UIImage,
        x: CGFloat,
        y: CGFloat,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let cgImage = image.cgImage,
              let pixelImage = cgImage.cropping(to: CGRect(
                  x: CGFloat(cgImage.width - 1) * x,
                  y: CGFloat(cgImage.height - 1) * y,
                  width: 1,
                  height: 1
              ))
        else {
            XCTFail("Preview pixel is unavailable.", file: file, line: line)
            return
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let didDraw = pixel.withUnsafeMutableBytes { buffer in
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
        XCTAssertTrue(didDraw, file: file, line: line)
        XCTAssertEqual(CGFloat(pixel[0]) / 255, red, accuracy: 0.12, file: file, line: line)
        XCTAssertEqual(CGFloat(pixel[1]) / 255, green, accuracy: 0.12, file: file, line: line)
        XCTAssertEqual(CGFloat(pixel[2]) / 255, blue, accuracy: 0.12, file: file, line: line)
        XCTAssertEqual(pixel[3], 255, file: file, line: line)
    }
}

private final class TimelineReloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
