import Foundation
import PencilKit
import SwiftUI
import UIKit
import XCTest

@testable import Coloring

@MainActor
final class PencilCanvasRenderCacheTests: XCTestCase {
    func testZoomWithoutPreparedCacheKeepsNativeCanvasVisible() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)

        fixture.coordinator.scrollViewWillBeginZooming(fixture.container.canvasView, with: nil)
        fixture.coordinator.scrollViewDidZoom(fixture.container.canvasView)

        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertFalse(fixture.container.canvasView.isHidden)
        XCTAssertGreaterThan(fixture.container.canvasView.alpha, 0.01)
        await dispose(fixture, renderer: renderer)
    }

    func testNativeRenderingCompletionDuringZoomKeepsCacheUntilZoomEnds() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        await prepareCache(in: fixture, renderer: renderer)

        fixture.coordinator.scrollViewWillBeginZooming(fixture.container.canvasView, with: nil)
        fixture.container.canvasView.zoomScale = 2
        fixture.coordinator.scrollViewDidZoom(fixture.container.canvasView)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)

        fixture.coordinator.canvasViewDidFinishRendering(fixture.container.canvasView)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)
        fixture.coordinator.scrollViewDidEndZooming(fixture.container.canvasView, with: nil, atScale: 2)
        let returnedToLive = await waitUntil { !fixture.container.isShowingCachedDrawing }
        XCTAssertTrue(returnedToLive)
        XCTAssertEqual(fixture.container.canvasView.drawing, fixture.state.drawing)
        await dispose(fixture, renderer: renderer)
    }

    func testZoomEndingBeforeNativeRenderingKeepsCacheUntilCompletion() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        await prepareCache(in: fixture, renderer: renderer)

        fixture.coordinator.scrollViewWillBeginZooming(fixture.container.canvasView, with: nil)
        fixture.container.canvasView.zoomScale = 2
        fixture.coordinator.scrollViewDidZoom(fixture.container.canvasView)
        fixture.coordinator.scrollViewDidEndZooming(fixture.container.canvasView, with: nil, atScale: 2)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)

        fixture.coordinator.canvasViewDidFinishRendering(fixture.container.canvasView)
        let returnedToLive = await waitUntil { !fixture.container.isShowingCachedDrawing }
        XCTAssertTrue(returnedToLive)
        await dispose(fixture, renderer: renderer)
    }

    func testBeginningEraseClearsCacheAndRejectsLatePreEraseRendering() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        fixture.coordinator.refreshDrawingRenderCache()
        let requested = await waitUntil { await renderer.requestCount() >= 1 }
        XCTAssertTrue(requested)
        fixture.container.setCachedDrawingImage(solidImage(.red))
        XCTAssertTrue(fixture.container.showCachedDrawing())

        fixture.container.canvasView.tool = PKEraserTool(.bitmap)
        fixture.coordinator.canvasViewDidBeginUsingTool(fixture.container.canvasView)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        fixture.container.canvasView.drawing = PKDrawing()
        fixture.coordinator.canvasViewDrawingDidChange(fixture.container.canvasView)
        fixture.coordinator.canvasViewDidEndUsingTool(fixture.container.canvasView)
        await finishRequest(0, image: solidImage(.red), renderer: renderer)

        XCTAssertTrue(fixture.container.canvasView.drawing.strokes.isEmpty)
        XCTAssertTrue(fixture.state.drawing.strokes.isEmpty)
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        await dispose(fixture, renderer: renderer)
    }

    func testForcedExternalUndoInvalidatesCacheAndRejectsPreviousRender() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        fixture.coordinator.refreshDrawingRenderCache()
        let requested = await waitUntil { await renderer.requestCount() >= 1 }
        XCTAssertTrue(requested)
        fixture.container.setCachedDrawingImage(solidImage(.red))
        XCTAssertTrue(fixture.container.showCachedDrawing())
        let restoredDrawing = sampleDrawing(color: .green)

        fixture.coordinator.applyExternalDrawing(restoredDrawing, to: fixture.container.canvasView)
        XCTAssertEqual(fixture.container.canvasView.drawing, restoredDrawing)
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        await finishRequest(0, image: solidImage(.red), renderer: renderer)

        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertEqual(fixture.container.canvasView.drawing, restoredDrawing)
        await dispose(fixture, renderer: renderer)
    }

    func testSameSizeTemplateSwitchRejectsPreviousTemplateRender() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        fixture.coordinator.refreshDrawingRenderCache()
        let firstRequested = await waitUntil { await renderer.requestCount() >= 1 }
        XCTAssertTrue(firstRequested)
        let nextTemplate = solidImage(.white, size: fixture.container.contentView.bounds.size)
        fixture.coordinator.parent = makeParent(
            templateID: "cache-template-b",
            templateImage: nextTemplate,
            state: fixture.state
        )
        fixture.container.applyTemplateImage(nextTemplate, templateID: "cache-template-b", resetZoom: true)
        fixture.coordinator.invalidateDrawingRenderCache()
        fixture.coordinator.refreshDrawingRenderCache()
        let replacementRequested = await waitUntil { await renderer.requestCount() >= 2 }
        XCTAssertTrue(replacementRequested)
        let newImage = solidImage(.blue)
        await finishRequest(1, image: newImage, renderer: renderer)
        let replacementPublished = await waitUntil {
            self.pixelSignature(fixture.container.cachedDrawingImageView.image) == self.pixelSignature(newImage)
        }
        XCTAssertTrue(replacementPublished)
        await finishRequest(0, image: solidImage(.red), renderer: renderer)

        XCTAssertEqual(pixelSignature(fixture.container.cachedDrawingImageView.image), pixelSignature(newImage))
        XCTAssertEqual(fixture.container.imageView.image?.size, nextTemplate.size)
        await dispose(fixture, renderer: renderer)
    }

    func testNewDrawingGenerationWinsOverLateOlderRendering() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        fixture.coordinator.refreshDrawingRenderCache()
        let firstRequested = await waitUntil { await renderer.requestCount() >= 1 }
        XCTAssertTrue(firstRequested)
        let newDrawing = sampleDrawing(color: .blue)
        fixture.container.canvasView.drawing = newDrawing
        fixture.coordinator.canvasViewDrawingDidChange(fixture.container.canvasView)
        fixture.coordinator.refreshDrawingRenderCache()
        let replacementRequested = await waitUntil { await renderer.requestCount() >= 2 }
        XCTAssertTrue(replacementRequested)
        let firstRequest = await renderer.request(at: 0)
        let secondRequest = await renderer.request(at: 1)
        XCTAssertNotEqual(firstRequest?.drawing, secondRequest?.drawing)
        XCTAssertEqual(secondRequest?.drawing, newDrawing)
        XCTAssertEqual(secondRequest?.canvasSize, fixture.container.contentView.bounds.size)

        let newImage = solidImage(.blue)
        await finishRequest(1, image: newImage, renderer: renderer)
        let replacementPublished = await waitUntil {
            self.pixelSignature(fixture.container.cachedDrawingImageView.image) == self.pixelSignature(newImage)
        }
        XCTAssertTrue(replacementPublished)
        await finishRequest(0, image: solidImage(.red), renderer: renderer)

        XCTAssertEqual(pixelSignature(fixture.container.cachedDrawingImageView.image), pixelSignature(newImage))
        XCTAssertEqual(fixture.container.canvasView.drawing, newDrawing)
        await dispose(fixture, renderer: renderer)
    }

    func testCachedSurfaceFollowsViewportWithoutInterceptingNativeDrawing() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        let container = fixture.container
        container.setCachedDrawingImage(solidImage(.blue))
        XCTAssertTrue(container.showCachedDrawing())
        container.canvasView.zoomScale = 2
        container.canvasView.contentOffset = CGPoint(x: 120, y: 80)
        fixture.coordinator.scrollViewDidZoom(container.canvasView)
        fixture.coordinator.scrollViewDidScroll(container.canvasView)

        XCTAssertTrue(container.cachedDrawingImageView.superview === container.contentView)
        XCTAssertEqual(container.cachedDrawingImageView.bounds, container.contentView.bounds)
        for point in [CGPoint.zero, CGPoint(x: 300, y: 200), CGPoint(x: 600, y: 400)] {
            XCTAssertEqual(
                container.cachedDrawingImageView.convert(point, to: container),
                container.contentView.convert(point, to: container)
            )
        }
        XCTAssertTrue(container.clipsToBounds)
        XCTAssertTrue(container.cachedDrawingImageView.clipsToBounds)
        XCTAssertFalse(container.cachedDrawingImageView.isUserInteractionEnabled)
        XCTAssertFalse(container.cachedDrawingImageView.isAccessibilityElement)
        XCTAssertTrue(container.cachedDrawingImageView.accessibilityElementsHidden)
        XCTAssertNotNil(container.canvasView.layer.mask)
        XCTAssertFalse(container.cachedDrawingImageView.isHidden)
        XCTAssertTrue(container.canvasView.isUserInteractionEnabled)
        XCTAssertTrue(container.canvasView.drawingGestureRecognizer.isEnabled)
        XCTAssertTrue(container.canvasView.panGestureRecognizer.isEnabled)
        XCTAssertTrue(container.canvasView.pinchGestureRecognizer?.isEnabled == true)
        let hitView = container.hitTest(CGPoint(x: container.bounds.midX, y: container.bounds.midY), with: nil)
        XCTAssertTrue(hitView === container.canvasView || hitView?.isDescendant(of: container.canvasView) == true)
        let directScrollViews = container.subviews.compactMap { $0 as? UIScrollView }
        XCTAssertEqual(directScrollViews.count, 1)
        XCTAssertTrue(directScrollViews.first === container.canvasView)
        container.showLiveDrawing()
        XCTAssertNil(container.canvasView.layer.mask)
        XCTAssertTrue(container.cachedDrawingImageView.isHidden)
        await dispose(fixture, renderer: renderer)
    }

    func testBackgroundDiscardsPendingCacheAndActiveNotificationWarmsFreshGeneration() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        defer {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        let firstRequested = await waitUntil { await renderer.requestCount() >= 1 }
        XCTAssertTrue(firstRequested)
        fixture.container.setCachedDrawingImage(solidImage(.red))
        XCTAssertTrue(fixture.container.showCachedDrawing())

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(fixture.container.canvasView.layer.mask)
        fixture.coordinator.canvasViewDidFinishRendering(fixture.container.canvasView)
        fixture.coordinator.refreshDrawingRenderCache()
        await finishRequest(0, image: solidImage(.red), renderer: renderer)
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        let backgroundRequestCount = await renderer.requestCount()
        XCTAssertEqual(backgroundRequestCount, 1)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let resumedRequest = await waitUntil { await renderer.requestCount() >= 2 }
        XCTAssertTrue(resumedRequest)
        let freshImage = solidImage(.blue)
        await finishRequest(1, image: freshImage, renderer: renderer)
        let freshImagePublished = await waitUntil {
            self.pixelSignature(fixture.container.cachedDrawingImageView.image) == self.pixelSignature(freshImage)
        }
        XCTAssertTrue(freshImagePublished)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        await dispose(fixture, renderer: renderer)
    }

    func testRulerKeepsNativeCanvasVisibleAndInvalidatesPreparedCache() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        await prepareCache(in: fixture, renderer: renderer)
        fixture.container.canvasView.isRulerActive = true

        fixture.coordinator.scrollViewWillBeginZooming(fixture.container.canvasView, with: nil)
        fixture.coordinator.scrollViewDidZoom(fixture.container.canvasView)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(fixture.container.canvasView.layer.mask)
        fixture.coordinator.toolPickerIsRulerActiveDidChange(PKToolPicker())
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertFalse(fixture.container.canvasView.isHidden)
        XCTAssertEqual(fixture.container.canvasView.drawing, fixture.state.drawing)
        await dispose(fixture, renderer: renderer)
    }

    func testLassoCannotUsePreparedCacheToHideNativeCanvas() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        await prepareCache(in: fixture, renderer: renderer)
        fixture.container.canvasView.tool = PKLassoTool()

        fixture.coordinator.scrollViewWillBeginZooming(fixture.container.canvasView, with: nil)
        fixture.coordinator.scrollViewDidZoom(fixture.container.canvasView)

        XCTAssertTrue(fixture.container.canvasView.tool is PKLassoTool)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(fixture.container.canvasView.layer.mask)
        XCTAssertFalse(fixture.container.canvasView.isHidden)
        XCTAssertEqual(fixture.container.canvasView.drawing, fixture.state.drawing)
        await dispose(fixture, renderer: renderer)
    }

    func testUnchangedZoomViewportStillWaitsForNativeReadinessBeforeRevealingDrawing() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        await prepareCache(in: fixture, renderer: renderer)
        let originalZoom = fixture.container.canvasView.zoomScale
        let originalOffset = fixture.container.canvasView.contentOffset

        fixture.coordinator.scrollViewWillBeginZooming(fixture.container.canvasView, with: nil)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)
        fixture.coordinator.scrollViewDidEndZooming(
            fixture.container.canvasView,
            with: nil,
            atScale: originalZoom
        )
        XCTAssertEqual(fixture.container.canvasView.zoomScale, originalZoom)
        XCTAssertEqual(fixture.container.canvasView.contentOffset, originalOffset)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)

        fixture.coordinator.canvasViewDidFinishRendering(fixture.container.canvasView)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(fixture.container.canvasView.layer.mask)
        await dispose(fixture, renderer: renderer)
    }

    func testDirectPencilEraserTransitionClearsPresentedCacheBeforeAnyStrokeCallback() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        await prepareCache(in: fixture, renderer: renderer)
        fixture.coordinator.scrollViewWillBeginZooming(fixture.container.canvasView, with: nil)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)

        fixture.coordinator.handlePencilTap(preferredAction: .switchEraser)

        XCTAssertTrue(fixture.container.canvasView.tool is PKEraserTool)
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(fixture.container.canvasView.layer.mask)
        XCTAssertEqual(fixture.container.canvasView.drawing, fixture.state.drawing)
        await dispose(fixture, renderer: renderer)
    }

    func testPencilDrawingStaysNativeDuringZoomAndPanAfterToolChanges() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer, inkType: .pencil)
        let canvas = fixture.container.canvasView
        let originalData = canvas.drawing.dataRepresentation()
        let tools: [PKTool] = [PKInkingTool(.pen, color: .black, width: 12), PKEraserTool(.bitmap)]

        for tool in tools {
            canvas.tool = tool
            fixture.coordinator.refreshDrawingRenderCache()
            fixture.coordinator.scrollViewWillBeginZooming(canvas, with: nil)
            canvas.zoomScale = 2
            fixture.coordinator.scrollViewDidZoom(canvas)
            fixture.coordinator.scrollViewDidEndZooming(canvas, with: nil, atScale: 2)
            fixture.coordinator.scrollViewWillBeginDragging(canvas)
            canvas.contentOffset = CGPoint(x: 60, y: 50)
            fixture.coordinator.scrollViewDidScroll(canvas)
            fixture.coordinator.scrollViewDidEndDragging(canvas, willDecelerate: false)
            fixture.coordinator.canvasViewDidFinishRendering(canvas)

            XCTAssertFalse(fixture.container.isShowingCachedDrawing)
            XCTAssertNil(fixture.container.cachedDrawingImageView.image)
            XCTAssertNil(canvas.layer.mask)
            XCTAssertEqual(canvas.alpha, 1)
            XCTAssertTrue(canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertEqual(canvas.drawing.dataRepresentation(), originalData)
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        let requestCount = await renderer.requestCount()
        XCTAssertEqual(requestCount, 0)
        await dispose(fixture, renderer: renderer)
    }

    func testAddingPencilRejectsLatePenCacheImage() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer)
        let requested = await waitUntil { await renderer.requestCount() >= 1 }
        XCTAssertTrue(requested)
        let canvas = fixture.container.canvasView
        let mixedDrawing = PKDrawing(strokes: canvas.drawing.strokes + sampleDrawing(color: .black, inkType: .pencil).strokes)

        canvas.tool = PKInkingTool(.pencil, color: .black, width: 12)
        fixture.coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing = mixedDrawing
        fixture.coordinator.canvasViewDrawingDidChange(canvas)
        fixture.coordinator.canvasViewDidEndUsingTool(canvas)
        await finishRequest(0, image: solidImage(.red), renderer: renderer)
        fixture.coordinator.scrollViewWillBeginZooming(canvas, with: nil)

        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(canvas.layer.mask)
        XCTAssertEqual(canvas.drawing, mixedDrawing)
        XCTAssertEqual(fixture.state.drawing, mixedDrawing)
        try? await Task.sleep(nanoseconds: 150_000_000)
        let requestCount = await renderer.requestCount()
        XCTAssertEqual(requestCount, 1)
        await dispose(fixture, renderer: renderer)
    }

    func testPencilRestoreDisablesCacheAndRemovingLastPencilAllowsCachingAgain() async {
        let renderer = ControlledPencilCacheRenderer()
        let fixture = makeFixture(renderer: renderer, inkType: .pencil)
        let pencilDrawing = fixture.state.drawing
        let penDrawing = sampleDrawing(color: .blue)
        let canvas = fixture.container.canvasView
        canvas.tool = PKEraserTool(.bitmap)

        fixture.state.drawing = penDrawing
        fixture.coordinator.applyExternalDrawing(penDrawing, to: canvas)
        await prepareCache(in: fixture, renderer: renderer)
        fixture.coordinator.scrollViewWillBeginZooming(canvas, with: nil)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)

        fixture.state.drawing = pencilDrawing
        fixture.coordinator.applyExternalDrawing(pencilDrawing, to: canvas)
        fixture.coordinator.scrollViewDidEndZooming(canvas, with: nil, atScale: canvas.zoomScale)
        fixture.coordinator.scrollViewWillBeginDragging(canvas)
        XCTAssertFalse(fixture.container.isShowingCachedDrawing)
        XCTAssertNil(fixture.container.cachedDrawingImageView.image)
        XCTAssertNil(canvas.layer.mask)
        XCTAssertEqual(canvas.drawing, pencilDrawing)
        try? await Task.sleep(nanoseconds: 150_000_000)
        let requestCount = await renderer.requestCount()
        XCTAssertEqual(requestCount, 1)
        await dispose(fixture, renderer: renderer)
    }

    private func dispose(_ fixture: PencilCacheFixture, renderer: ControlledPencilCacheRenderer) async {
        fixture.coordinator.disconnect(from: fixture.container.canvasView)
        await renderer.completeAllPendingRequests()
    }

    private func makeFixture(renderer: ControlledPencilCacheRenderer, inkType: PKInk.InkType = .pen) -> PencilCacheFixture {
        let state = PencilCacheDrawingState(drawing: sampleDrawing(color: .red, inkType: inkType))
        let templateImage = solidImage(.white, size: CGSize(width: 600, height: 400))
        let parent = makeParent(templateID: "cache-template-a", templateImage: templateImage, state: state)
        let container = ZoomableCanvasContainerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        container.applyTemplateImage(templateImage, templateID: parent.templateID, resetZoom: true)
        container.canvasView.drawing = state.drawing
        let coordinator = PencilCanvasView.Coordinator(parent, renderCacheService: renderer)
        coordinator.connect(to: container.canvasView, containerView: container)
        return PencilCacheFixture(state: state, container: container, coordinator: coordinator)
    }

    private func makeParent(templateID: String, templateImage: UIImage, state: PencilCacheDrawingState) -> PencilCanvasView {
        PencilCanvasView(
            templateImage: templateImage,
            templateID: templateID,
            drawing: Binding(get: { state.drawing }, set: { state.drawing = $0 }),
            isToolPickerSuppressed: true
        )
    }

    private func prepareCache(in fixture: PencilCacheFixture, renderer: ControlledPencilCacheRenderer) async {
        fixture.coordinator.refreshDrawingRenderCache()
        let requested = await waitUntil { await renderer.requestCount() >= 1 }
        XCTAssertTrue(requested)
        await finishRequest(0, image: solidImage(.blue), renderer: renderer)
        let published = await waitUntil { fixture.container.cachedDrawingImageView.image != nil }
        XCTAssertTrue(published)
    }

    private func finishRequest(_ index: Int, image: UIImage, renderer: ControlledPencilCacheRenderer) async {
        await renderer.completeRequest(at: index, image: image)
        let returned = await waitUntil { await renderer.hasReturnedRequest(at: index) }
        XCTAssertTrue(returned)
        // Drain queued main-actor publications after releasing the controlled renderer.
        for _ in 0..<2 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return await condition()
    }

    private func sampleDrawing(color: UIColor, inkType: PKInk.InkType = .pen) -> PKDrawing {
        let points = [CGPoint(x: 30, y: 30), CGPoint(x: 180, y: 120)].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: 12, height: 12),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKDrawing(strokes: [PKStroke(
            ink: PKInk(inkType, color: color),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1))
        )])
    }

    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 16, height: 12)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
    }

    private func pixelSignature(_ image: UIImage?) -> [UInt8]? {
        guard let cgImage = image?.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let didDraw = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return didDraw ? pixel : nil
    }
}

@MainActor
private struct PencilCacheFixture {
    let state: PencilCacheDrawingState
    let container: ZoomableCanvasContainerView
    let coordinator: PencilCanvasView.Coordinator
}

@MainActor
private final class PencilCacheDrawingState {
    var drawing: PKDrawing

    init(drawing: PKDrawing) {
        self.drawing = drawing
    }
}

private actor ControlledPencilCacheRenderer: PencilDrawingRenderCacheRendering {
    private var requests: [PencilDrawingRenderCacheRequest] = []
    private var continuations: [Int: CheckedContinuation<UIImage?, Never>] = [:]
    private var returnedRequests: Set<Int> = []

    func image(for request: PencilDrawingRenderCacheRequest) async -> UIImage? {
        let index = requests.count
        requests.append(request)
        let image = await withCheckedContinuation { continuation in
            continuations[index] = continuation
        }
        returnedRequests.insert(index)
        return image
    }

    func requestCount() -> Int { requests.count }

    func request(at index: Int) -> PencilDrawingRenderCacheRequest? {
        requests.indices.contains(index) ? requests[index] : nil
    }

    func hasReturnedRequest(at index: Int) -> Bool {
        returnedRequests.contains(index)
    }

    func completeRequest(at index: Int, image: UIImage?) {
        continuations.removeValue(forKey: index)?.resume(returning: image)
    }

    func completeAllPendingRequests() {
        let pending = Array(continuations.values)
        continuations.removeAll()
        pending.forEach { $0.resume(returning: nil) }
    }
}
