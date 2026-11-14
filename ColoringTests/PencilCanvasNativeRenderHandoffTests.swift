import PencilKit
import SwiftUI
import UIKit
import XCTest

@testable import Coloring

@MainActor
final class PencilCanvasNativeRenderHandoffTests: XCTestCase {
    func testAppearanceChangeWaitsForActiveStrokeAndUsesItsFinalDrawing() async throws {
        try await withAppearanceCanvas { canvas, container, coordinator, state, appearanceCount in
            let initialDrawing = canvas.drawing
            coordinator.canvasViewDidBeginUsingTool(canvas)
            container.appearanceDidChangeHandler?(nil)
            container.appearanceDidChangeHandler?(nil)
            XCTAssertEqual(appearanceCount(), 0, "Appearance must not replace a drawing during active coloring.")
            XCTAssertEqual(canvas.drawing, initialDrawing)

            let finalDrawing = initialDrawing.appending(Self.makeDrawing().transformed(using: .init(translationX: 10, y: 10)))
            canvas.drawing = finalDrawing
            coordinator.canvasViewDrawingDidChange(canvas)
            coordinator.canvasViewDidEndUsingTool(canvas)

            XCTAssertEqual(appearanceCount(), 1, "Apply the latest appearance once after the stroke ends.")
            XCTAssertEqual(state.drawing.strokes.count, finalDrawing.strokes.count)
            XCTAssertEqual(state.drawing.strokes.map(\.transform), finalDrawing.strokes.map(\.transform))
            XCTAssertEqual(state.drawing.strokes.map(\.randomSeed), finalDrawing.strokes.map(\.randomSeed))
        }
    }

    func testAppearanceChangeWaitsForZoomToEndWithoutMovingTheViewport() async throws {
        try await withAppearanceCanvas { canvas, container, coordinator, _, appearanceCount in
            coordinator.scrollViewWillBeginZooming(canvas, with: nil)
            canvas.zoomScale = 2
            canvas.contentOffset = CGPoint(x: 90, y: 70)
            let offset = canvas.contentOffset
            container.appearanceDidChangeHandler?(nil)
            XCTAssertEqual(appearanceCount(), 0)

            coordinator.scrollViewDidEndZooming(canvas, with: nil, atScale: 2)

            XCTAssertEqual(appearanceCount(), 1)
            XCTAssertEqual(canvas.zoomScale, 2)
            XCTAssertEqual(canvas.contentOffset, offset)
        }
    }

    private func withAppearanceCanvas(
        _ body: (PKCanvasView, ZoomableCanvasContainerView, PencilCanvasView.Coordinator,
                 NativeHandoffDrawingState, () -> Int) async throws -> Void
    ) async throws {
        let fixture = try makeWindow()
        let drawing = Self.makeDrawing()
        let state = NativeHandoffDrawingState(drawing: drawing)
        var appearanceCount = 0
        let parent = PencilCanvasView(
            templateImage: fixture.template,
            templateID: fixture.templateID,
            drawing: Binding(get: { state.drawing }, set: { state.drawing = $0 }),
            onAppearanceStyleChanged: { _ in appearanceCount += 1 },
            isToolPickerSuppressed: true
        )
        let canvas = fixture.container.canvasView
        let coordinator = parent.makeCoordinator()
        canvas.delegate = coordinator
        coordinator.connect(to: canvas, containerView: fixture.container)
        coordinator.updateToolPickerSuppression(true, on: canvas)
        canvas.drawing = drawing
        defer {
            canvas.delegate = nil
            coordinator.disconnect(from: canvas)
            fixture.close()
        }
        try await body(canvas, fixture.container, coordinator, state, { appearanceCount })
    }

    func testNativeDrawingLoadFinishesWhileOwnedMaskCoversInk() async throws {
        let fixture = try makeWindow()
        defer { fixture.close() }
        let canvas = fixture.container.canvasView
        let observer = NativeHandoffDelegate()
        canvas.delegate = observer
        let originalDrawing = Self.makeDrawing()
        let initialCompletion = expectation(description: "Initial native drawing finishes rendering")
        var initialRenderingObserved = false
        observer.onFinishedRendering = { nativeCanvas in
            guard !initialRenderingObserved, nativeCanvas.drawing == originalDrawing else { return }
            initialRenderingObserved = true
            initialCompletion.fulfill()
        }
        canvas.drawing = originalDrawing
        let initialResult = await XCTWaiter.fulfillment(of: [initialCompletion], timeout: 5)
        XCTAssertEqual(initialResult, .completed)
        guard initialResult == .completed else { return }

        let renderedImage = await PencilDrawingRenderCacheService().image(for: .init(
            drawing: originalDrawing,
            canvasSize: fixture.container.contentView.bounds.size
        ))
        fixture.container.setCachedDrawingImage(try XCTUnwrap(renderedImage))
        XCTAssertTrue(fixture.container.showCachedDrawing())

        let changedDrawing = originalDrawing.transformed(using: CGAffineTransform(translationX: 18, y: 11))
        let maskedCompletion = expectation(description: "Changed native drawing finishes while masked")
        var completionObservedUnderMask = false
        observer.onFinishedRendering = { nativeCanvas in
            guard !completionObservedUnderMask,
                  nativeCanvas.drawing == changedDrawing,
                  fixture.container.isShowingCachedDrawing
            else { return }
            completionObservedUnderMask = true
            maskedCompletion.fulfill()
        }
        // No coordinator is attached here: this isolates whether the owned mask
        // suppresses PencilKit rendering, without edit invalidation revealing ink.
        canvas.drawing = changedDrawing
        let maskedResult = await XCTWaiter.fulfillment(of: [maskedCompletion], timeout: 5)

        XCTAssertEqual(maskedResult, .completed)
        XCTAssertTrue(completionObservedUnderMask)
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)
        fixture.container.showLiveDrawing()
        XCTAssertNil(canvas.layer.mask)
        XCTAssertTrue(fixture.container.cachedDrawingImageView.isHidden)
        XCTAssertEqual(canvas.drawing, changedDrawing)
    }

    func testNativeZoomKeepsCacheDuringNavigationAndRecoversLiveCanvas() async throws {
        try await assertNativeZoomHandoff(appearance: .light)
    }

    func testDarkModeZoomKeepsCacheDuringNavigationAndRecoversLiveCanvas() async throws {
        try await assertNativeZoomHandoff(appearance: .dark)
    }

    private func assertNativeZoomHandoff(appearance: UIUserInterfaceStyle) async throws {
        let fixture = try makeWindow(appearance: appearance)
        XCTAssertEqual(fixture.window.traitCollection.userInterfaceStyle, appearance)
        XCTAssertEqual(fixture.container.canvasView.traitCollection.userInterfaceStyle, .light)
        let drawing = Self.makeDrawing()
        let state = NativeHandoffDrawingState(drawing: drawing)
        let parent = PencilCanvasView(
            templateImage: fixture.template,
            templateID: fixture.templateID,
            drawing: Binding(get: { state.drawing }, set: { state.drawing = $0 }),
            isToolPickerSuppressed: true
        )
        let canvas = fixture.container.canvasView
        let coordinator = PencilCanvasView.Coordinator(parent)
        let observer = NativeHandoffDelegate(coordinator: coordinator)
        canvas.delegate = observer
        coordinator.connect(to: canvas, containerView: fixture.container)
        coordinator.updateToolPickerSuppression(true, on: canvas)
        defer {
            observer.onFinishedRendering = nil
            canvas.delegate = nil
            coordinator.disconnect(from: canvas)
            fixture.close()
        }

        let initialCompletion = expectation(description: "Initial coordinator drawing finishes rendering")
        var initialRenderingObserved = false
        observer.onFinishedRendering = { nativeCanvas in
            guard !initialRenderingObserved, nativeCanvas.drawing == drawing else { return }
            initialRenderingObserved = true
            initialCompletion.fulfill()
        }
        canvas.drawing = drawing
        let initialResult = await XCTWaiter.fulfillment(of: [initialCompletion], timeout: 5)
        XCTAssertEqual(initialResult, .completed)
        guard initialResult == .completed else { return }

        let cachePrepared = await waitUntil(timeout: 5) { fixture.container.cachedDrawingImageView.image != nil }
        XCTAssertTrue(cachePrepared)
        guard cachePrepared else { return }

        // A programmatic zoom may omit pinch lifetime callbacks. The test owns
        // that lifetime while forwarding real viewport and rendering callbacks.
        observer.isNavigationBracketedByTest = true
        coordinator.scrollViewWillBeginZooming(canvas, with: nil)
        let targetZoom = min(canvas.maximumZoomScale, canvas.zoomScale * 2)
        XCTAssertGreaterThan(targetZoom, canvas.zoomScale)
        canvas.setZoomScale(targetZoom, animated: false)
        fixture.container.updateCanvasViewport()
        XCTAssertTrue(fixture.container.isShowingCachedDrawing)
        assertNativeHitTesting(in: fixture.container)

        observer.isNavigationBracketedByTest = false
        coordinator.scrollViewDidEndZooming(canvas, with: nil, atScale: targetZoom)
        // PencilKit need not emit a callback when zooming already-rendered ink.
        // Either native readiness or the bounded recovery must reveal the canvas.
        let returnedToLive = await waitUntil(timeout: 3) { !fixture.container.isShowingCachedDrawing }
        XCTAssertTrue(returnedToLive)
        XCTAssertNil(canvas.layer.mask)
        XCTAssertTrue(fixture.container.cachedDrawingImageView.isHidden)
        XCTAssertEqual(canvas.drawing, drawing)
        assertNativeHitTesting(in: fixture.container)
    }

    private func assertNativeHitTesting(in container: ZoomableCanvasContainerView) {
        let point = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        let hitView = container.hitTest(point, with: nil)
        XCTAssertTrue(hitView === container.canvasView || hitView?.isDescendant(of: container.canvasView) == true)
        XCTAssertTrue(container.canvasView.drawingGestureRecognizer.isEnabled)
        XCTAssertTrue(container.canvasView.panGestureRecognizer.isEnabled)
    }

    private func waitUntil(timeout: TimeInterval, condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func makeWindow(appearance: UIUserInterfaceStyle = .light) throws -> NativeHandoffWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let template = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        }
        return NativeHandoffWindow(scene: scene, template: template, appearance: appearance)
    }

    private static func makeDrawing() -> PKDrawing {
        let points = [CGPoint(x: 60, y: 80), CGPoint(x: 520, y: 320)].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: 18, height: 18),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKDrawing(strokes: [PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1))
        )])
    }
}

@MainActor
private final class NativeHandoffWindow {
    let window: UIWindow
    let container: ZoomableCanvasContainerView
    let template: UIImage
    let templateID = "native-render-handoff"
    private let previousKeyWindow: UIWindow?

    init(scene: UIWindowScene, template: UIImage, appearance: UIUserInterfaceStyle) {
        self.template = template
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        window.overrideUserInterfaceStyle = appearance
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.frame = window.bounds
        container = ZoomableCanvasContainerView(frame: controller.view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(container)
        container.applyTemplateImage(template, templateID: templateID, resetZoom: true)
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        container.layoutIfNeeded()
    }

    func close() {
        container.canvasView.delegate = nil
        container.clearCachedDrawing()
        container.removeFromSuperview()
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}

@MainActor
private final class NativeHandoffDrawingState {
    var drawing: PKDrawing
    init(drawing: PKDrawing) { self.drawing = drawing }
}

@MainActor
private final class NativeHandoffDelegate: NSObject, PKCanvasViewDelegate {
    let coordinator: PencilCanvasView.Coordinator?
    var onFinishedRendering: ((PKCanvasView) -> Void)?
    var isNavigationBracketedByTest = false

    init(coordinator: PencilCanvasView.Coordinator? = nil) { self.coordinator = coordinator }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { coordinator?.canvasViewDrawingDidChange(canvasView) }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { coordinator?.canvasViewDidBeginUsingTool(canvasView) }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { coordinator?.canvasViewDidEndUsingTool(canvasView) }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { coordinator?.scrollViewDidZoom(scrollView) }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { coordinator?.scrollViewDidScroll(scrollView) }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { coordinator?.scrollViewWillBeginDragging(scrollView) }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { coordinator?.scrollViewDidEndDecelerating(scrollView) }

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        onFinishedRendering?(canvasView)
        coordinator?.canvasViewDidFinishRendering(canvasView)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        guard !isNavigationBracketedByTest else { return }
        coordinator?.scrollViewWillBeginZooming(scrollView, with: view)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard !isNavigationBracketedByTest else { return }
        coordinator?.scrollViewDidEndZooming(scrollView, with: view, atScale: scale)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        coordinator?.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }
}
