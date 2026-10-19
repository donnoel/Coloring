import PencilKit
import UIKit
import XCTest

@testable import Coloring

final class PencilCanvasCachePresentationTests: XCTestCase {
    func testCachedDrawingUsesMaskAndKeepsNativeCanvasInteractive() async {
        await MainActor.run {
            let container = Self.makeContainer()
            let image = Self.makeImage()
            let wasDrawingEnabled = container.canvasView.drawingGestureRecognizer.isEnabled
            let drawingPolicy = container.canvasView.drawingPolicy

            XCTAssertFalse(container.showCachedDrawing())
            container.setCachedDrawingImage(image)
            XCTAssertTrue(container.cachedDrawingImageView.isHidden)
            XCTAssertTrue(container.showCachedDrawing())
            XCTAssertTrue(container.isShowingCachedDrawing)
            XCTAssertNotNil(container.canvasView.layer.mask)
            XCTAssertEqual(container.canvasView.alpha, 1)
            XCTAssertFalse(container.canvasView.isHidden)
            XCTAssertTrue(container.canvasView.isUserInteractionEnabled)
            XCTAssertTrue(container.canvasView.isScrollEnabled)
            XCTAssertEqual(container.canvasView.drawingGestureRecognizer.isEnabled, wasDrawingEnabled)
            XCTAssertEqual(container.canvasView.drawingPolicy, drawingPolicy)

            container.showLiveDrawing()

            XCTAssertFalse(container.isShowingCachedDrawing)
            XCTAssertNil(container.canvasView.layer.mask)
            XCTAssertTrue(container.cachedDrawingImageView.isHidden)
            XCTAssertTrue(container.cachedDrawingImageView.image === image)

            XCTAssertTrue(container.showCachedDrawing())
            container.setCachedDrawingImage(UIImage())
            XCTAssertFalse(container.isShowingCachedDrawing)
            XCTAssertNil(container.cachedDrawingImageView.image)
            XCTAssertNil(container.canvasView.layer.mask)
        }
    }

    func testMaskedCanvasRemainsWindowHitTestTarget() async {
        await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                XCTFail("Expected a window scene for the canvas test host.")
                return
            }
            let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
            let controller = UIViewController()
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                previousKeyWindow?.makeKey()
            }

            let container = Self.makeContainer(frame: controller.view.bounds)
            controller.view.addSubview(container)
            controller.view.layoutIfNeeded()
            container.setCachedDrawingImage(Self.makeImage())
            XCTAssertTrue(container.showCachedDrawing())

            let point = container.convert(CGPoint(x: 100, y: 150), to: window)
            let hitView = window.hitTest(point, with: nil)
            XCTAssertTrue(hitView === container.canvasView || hitView?.isDescendant(of: container.canvasView) == true)
            XCTAssertEqual(container.canvasView.alpha, 1)

            container.showLiveDrawing()
            XCTAssertTrue(container.showCachedDrawing())
            let nextHitView = window.hitTest(point, with: nil)
            XCTAssertTrue(nextHitView === container.canvasView || nextHitView?.isDescendant(of: container.canvasView) == true)
        }
    }

    func testCachePresentationPreservesMasksOwnedByOtherCode() async {
        await MainActor.run {
            let container = Self.makeContainer()
            let foreignMask = CALayer()
            container.canvasView.layer.mask = foreignMask
            container.setCachedDrawingImage(Self.makeImage())

            XCTAssertFalse(container.showCachedDrawing())
            XCTAssertTrue(container.canvasView.layer.mask === foreignMask)
            XCTAssertTrue(container.cachedDrawingImageView.isHidden)
            container.showLiveDrawing()
            XCTAssertTrue(container.canvasView.layer.mask === foreignMask)
            container.clearCachedDrawing()
            XCTAssertTrue(container.canvasView.layer.mask === foreignMask)
            XCTAssertNil(container.cachedDrawingImageView.image)

            container.canvasView.layer.mask = nil
            container.setCachedDrawingImage(Self.makeImage())
            XCTAssertTrue(container.showCachedDrawing())
            let ownedMask = container.canvasView.layer.mask
            container.showLiveDrawing()
            XCTAssertNil(container.canvasView.layer.mask)
            XCTAssertTrue(container.showCachedDrawing())
            XCTAssertTrue(container.canvasView.layer.mask === ownedMask)

            container.canvasView.layer.mask = foreignMask
            container.showLiveDrawing()
            XCTAssertTrue(container.canvasView.layer.mask === foreignMask)
            XCTAssertFalse(container.isShowingCachedDrawing)
        }
    }

    func testCachedInkFollowsArtworkGeometryAndPreservesLayerOrder() async {
        await MainActor.run {
            let container = Self.makeContainer()
            container.setCachedDrawingImage(Self.makeImage())
            XCTAssertTrue(container.showCachedDrawing())

            let artworkLayers = container.contentView.subviews
            XCTAssertEqual(artworkLayers.count, 4)
            XCTAssertTrue(artworkLayers[0] === container.imageView)
            XCTAssertTrue(artworkLayers[1] === container.fillImageView)
            XCTAssertTrue(artworkLayers[2] === container.belowLayerImageView)
            XCTAssertTrue(artworkLayers[3] === container.cachedDrawingImageView)
            XCTAssertTrue(container.subviews.first === container.contentView)
            XCTAssertTrue(container.subviews.last === container.aboveLayerImageView)
            let scrollViews = container.subviews.compactMap { $0 as? UIScrollView }
            XCTAssertEqual(scrollViews.count, 1)
            XCTAssertTrue(scrollViews.first === container.canvasView)
            XCTAssertFalse(container.cachedDrawingImageView.isUserInteractionEnabled)
            XCTAssertTrue(container.cachedDrawingImageView.accessibilityElementsHidden)
            XCTAssertEqual(container.cachedDrawingImageView.overrideUserInterfaceStyle, .light)

            container.canvasView.zoomScale = 2
            container.canvasView.contentOffset = CGPoint(x: 120, y: 180)
            container.updateCanvasViewport()

            XCTAssertEqual(container.cachedDrawingImageView.frame, container.contentView.bounds)
            XCTAssertEqual(container.contentView.transform.a, 2, accuracy: 0.0001)
            XCTAssertEqual(container.contentView.center, CGPoint(x: 480, y: 720))
            XCTAssertEqual(container.aboveLayerImageView.transform, container.contentView.transform)
            XCTAssertEqual(container.aboveLayerImageView.center, container.contentView.center)
            let artworkPoint = CGPoint(x: 150, y: 225)
            XCTAssertEqual(
                container.cachedDrawingImageView.convert(artworkPoint, to: container),
                container.contentView.convert(artworkPoint, to: container)
            )
            container.showLiveDrawing()
            XCTAssertEqual(container.canvasView.zoomScale, 2)
            XCTAssertEqual(container.canvasView.contentOffset, CGPoint(x: 120, y: 180))
        }
    }

    func testTemplateIdentityOrGeometryChangesDiscardCachedInk() async {
        await MainActor.run {
            let container = Self.makeContainer()
            let template = Self.makeImage(size: CGSize(width: 600, height: 900))
            container.applyTemplateImage(template, templateID: "one", resetZoom: true)
            container.setCachedDrawingImage(Self.makeImage())
            XCTAssertTrue(container.showCachedDrawing())

            container.applyTemplateImage(template, templateID: "one", resetZoom: false)
            XCTAssertTrue(container.isShowingCachedDrawing)

            let replacement = Self.makeImage(size: template.size)
            container.applyTemplateImage(replacement, templateID: "one", resetZoom: false)
            XCTAssertNil(container.cachedDrawingImageView.image)
            XCTAssertNil(container.canvasView.layer.mask)

            container.setCachedDrawingImage(Self.makeImage())
            XCTAssertTrue(container.showCachedDrawing())
            container.applyTemplateImage(replacement, templateID: "two", resetZoom: true)
            XCTAssertNil(container.cachedDrawingImageView.image)

            container.setCachedDrawingImage(Self.makeImage())
            XCTAssertTrue(container.showCachedDrawing())
            container.applyTemplateImage(
                Self.makeImage(size: CGSize(width: 900, height: 600)),
                templateID: "two",
                resetZoom: false
            )
            XCTAssertNil(container.cachedDrawingImageView.image)
            XCTAssertNil(container.canvasView.layer.mask)
            XCTAssertFalse(container.isShowingCachedDrawing)
        }
    }

    @MainActor
    private static func makeContainer(
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 1_000)
    ) -> ZoomableCanvasContainerView {
        let container = ZoomableCanvasContainerView(frame: frame)
        container.applyTemplateImage(
            makeImage(size: CGSize(width: 600, height: 900)),
            templateID: "presentation-test",
            resetZoom: true
        )
        return container
    }

    @MainActor
    private static func makeImage(size: CGSize = CGSize(width: 80, height: 120)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
