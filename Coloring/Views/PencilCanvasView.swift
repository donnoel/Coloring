import PencilKit
import SwiftUI
import UIKit

struct PencilCanvasView: UIViewRepresentable {
    let templateImage: UIImage
    let templateID: String
    @Binding var drawing: PKDrawing
    var onDrawingChanged: ((PKDrawing) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ZoomableCanvasContainerView {
        let containerView = ZoomableCanvasContainerView()
        let canvasView = containerView.canvasView
        let prefersPencilOnly = UIPencilInteraction.prefersPencilOnlyDrawing
        canvasView.drawing = drawing
        canvasView.drawingPolicy = prefersPencilOnly ? .pencilOnly : .anyInput
        containerView.scrollView.panGestureRecognizer.minimumNumberOfTouches = prefersPencilOnly ? 1 : 2
        canvasView.delegate = context.coordinator
        containerView.scrollView.delegate = context.coordinator

        context.coordinator.connect(to: canvasView, containerView: containerView)
        containerView.applyTemplateImage(templateImage, templateID: templateID, resetZoom: true)
        containerView.captureDrawingReference(drawing)
        context.coordinator.lastTemplateID = templateID
        context.coordinator.lastTemplateImageIdentity = ObjectIdentifier(templateImage)
        return containerView
    }

    func updateUIView(_ uiView: ZoomableCanvasContainerView, context: Context) {
        context.coordinator.parent = self

        let canvasView = uiView.canvasView
        let prefersPencilOnly = UIPencilInteraction.prefersPencilOnlyDrawing
        canvasView.drawingPolicy = prefersPencilOnly ? .pencilOnly : .anyInput
        uiView.scrollView.panGestureRecognizer.minimumNumberOfTouches = prefersPencilOnly ? 1 : 2

        if canvasView.drawing != drawing {
            context.coordinator.applyExternalDrawing(drawing, to: canvasView)
        }

        let shouldResetZoom = context.coordinator.lastTemplateID != templateID
        let templateImageIdentity = ObjectIdentifier(templateImage)
        let didTemplateImageChange = context.coordinator.lastTemplateImageIdentity != templateImageIdentity
        let shouldUpdateTemplateImage = shouldResetZoom
            || didTemplateImageChange
            || uiView.imageView.image == nil
        if shouldUpdateTemplateImage {
            uiView.applyTemplateImage(templateImage, templateID: templateID, resetZoom: shouldResetZoom)
            context.coordinator.lastTemplateImageIdentity = templateImageIdentity
        }

        context.coordinator.lastTemplateID = templateID
    }

    static func dismantleUIView(_ uiView: ZoomableCanvasContainerView, coordinator: Coordinator) {
        coordinator.disconnect(from: uiView.canvasView)
        uiView.canvasView.delegate = nil
        uiView.scrollView.delegate = nil
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate, UIScrollViewDelegate {
        var parent: PencilCanvasView
        private weak var canvasView: PKCanvasView?
        private weak var containerView: ZoomableCanvasContainerView?
        private var toolPicker: PKToolPicker?
        private var pencilInteraction: UIPencilInteraction?
        private var lastInkTool: PKTool = PKInkingTool(.marker, color: .black, width: 12)
        private var isApplyingExternalDrawing = false
        var lastTemplateID: String?
        var lastTemplateImageIdentity: ObjectIdentifier?
        private let isRunningTests = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func connect(to canvasView: PKCanvasView, containerView: ZoomableCanvasContainerView) {
            self.canvasView = canvasView
            self.containerView = containerView
            canvasView.tool = lastInkTool

            guard !isRunningTests else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.installToolingIfPossible()
            }
        }

        private func installToolingIfPossible() {
            guard !isRunningTests,
                  toolPicker == nil,
                  let canvasView
            else {
                return
            }

            guard canvasView.window != nil else {
                DispatchQueue.main.async { [weak self] in
                    self?.installToolingIfPossible()
                }
                return
            }

            let toolPicker = PKToolPicker()
            toolPicker.addObserver(canvasView)
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
            self.toolPicker = toolPicker

            let interaction = UIPencilInteraction(delegate: self)
            canvasView.addInteraction(interaction)
            pencilInteraction = interaction
        }

        func disconnect(from canvasView: PKCanvasView) {
            if let toolPicker {
                toolPicker.removeObserver(canvasView)
                toolPicker.setVisible(false, forFirstResponder: canvasView)
            }

            if let pencilInteraction {
                canvasView.removeInteraction(pencilInteraction)
            }

            toolPicker = nil
            pencilInteraction = nil
            self.canvasView = nil
            containerView = nil
        }

        func applyExternalDrawing(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
            isApplyingExternalDrawing = true
            canvasView.drawing = drawing
            containerView?.captureDrawingReference(drawing)
            isApplyingExternalDrawing = false
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else {
                return
            }

            let isProgrammaticTransform = containerView?.consumePendingProgrammaticDrawingChange(for: canvasView.drawing) == true
            if !isProgrammaticTransform {
                containerView?.captureDrawingReference(canvasView.drawing)
            }
            parent.drawing = canvasView.drawing
            parent.onDrawingChanged?(canvasView.drawing)
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            containerView?.contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            containerView?.updateContentInsetForCentering()
        }

        func pencilInteraction(_: UIPencilInteraction, didReceiveTap _: UIPencilInteraction.Tap) {
            showToolPicker()
        }

        func pencilInteraction(_: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended else {
                return
            }

            switchToEraser()
        }

        private func showToolPicker() {
            guard let canvasView, let toolPicker else {
                return
            }

            toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        private func switchToEraser() {
            guard let canvasView else {
                return
            }

            if let inkingTool = canvasView.tool as? PKInkingTool {
                lastInkTool = inkingTool
            }

            canvasView.tool = PKEraserTool(.bitmap)
        }
    }
}

final class ZoomableCanvasContainerView: UIView {
    let scrollView = UIScrollView()
    let contentView = UIView()
    let imageView = UIImageView()
    let canvasView = PKCanvasView()

    private var templateAspectRatio: CGFloat = 4.0 / 3.0
    private var currentTemplateID: String = ""
    private var lastBoundsSize: CGSize = .zero
    private var referenceDrawing: PKDrawing = PKDrawing()
    private var referenceDrawingSize: CGSize = .zero
    private var pendingProgrammaticDrawingData: Data?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds

        let didBoundsChange = bounds.size != lastBoundsSize
        let previousContentSize = contentView.bounds.size
        lastBoundsSize = bounds.size

        layoutContentFrame()
        if didBoundsChange {
            scaleDrawingIfNeeded(from: previousContentSize, to: contentView.bounds.size)
        }

        if didBoundsChange, scrollView.zoomScale <= scrollView.minimumZoomScale {
            resetZoomToFit()
        } else {
            updateContentInsetForCentering()
        }
    }

    func applyTemplateImage(_ image: UIImage, templateID: String, resetZoom: Bool) {
        imageView.image = image
        let nextAspectRatio = Self.aspectRatio(for: image)
        let aspectRatioChanged = abs(nextAspectRatio - templateAspectRatio) > 0.0001
        let templateChanged = currentTemplateID != templateID
        templateAspectRatio = nextAspectRatio
        currentTemplateID = templateID

        setNeedsLayout()
        layoutIfNeeded()

        if resetZoom || templateChanged || aspectRatioChanged {
            resetZoomToFit()
        } else {
            updateContentInsetForCentering()
        }
    }

    func updateContentInsetForCentering() {
        let scaledContentWidth = contentView.bounds.width * scrollView.zoomScale
        let scaledContentHeight = contentView.bounds.height * scrollView.zoomScale
        let horizontalInset = max((scrollView.bounds.width - scaledContentWidth) / 2, 0)
        let verticalInset = max((scrollView.bounds.height - scaledContentHeight) / 2, 0)

        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    func captureDrawingReference(_ drawing: PKDrawing) {
        referenceDrawing = drawing
        referenceDrawingSize = contentView.bounds.size
    }

    func consumePendingProgrammaticDrawingChange(for drawing: PKDrawing) -> Bool {
        guard let pendingProgrammaticDrawingData else {
            return false
        }

        guard drawing.dataRepresentation() == pendingProgrammaticDrawingData else {
            return false
        }

        self.pendingProgrammaticDrawingData = nil
        return true
    }

    private func setupSubviews() {
        backgroundColor = .clear

        scrollView.backgroundColor = .clear
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 8.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        imageView.backgroundColor = .white
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        canvasView.isOpaque = false
        canvasView.backgroundColor = .clear
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.isScrollEnabled = false
        canvasView.contentInset = .zero
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        contentView.addSubview(canvasView)
    }

    private func layoutContentFrame() {
        let contentSize = Self.fittedContentSize(
            in: scrollView.bounds.size,
            aspectRatio: templateAspectRatio
        )
        contentView.frame = CGRect(origin: .zero, size: contentSize)
        imageView.frame = contentView.bounds
        canvasView.frame = contentView.bounds
        scrollView.contentSize = contentSize
    }

    private func resetZoomToFit() {
        scrollView.zoomScale = scrollView.minimumZoomScale
        scrollView.contentOffset = .zero
        updateContentInsetForCentering()
    }

    private func scaleDrawingIfNeeded(from oldSize: CGSize, to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else {
            return
        }

        let sourceDrawing: PKDrawing
        let sourceSize: CGSize
        if referenceDrawingSize.width > 0, referenceDrawingSize.height > 0 {
            sourceDrawing = referenceDrawing
            sourceSize = referenceDrawingSize
        } else {
            sourceDrawing = canvasView.drawing
            sourceSize = oldSize
        }

        guard sourceSize.width > 0,
              sourceSize.height > 0,
              !sourceDrawing.strokes.isEmpty
        else {
            return
        }

        let scaleX = newSize.width / sourceSize.width
        let scaleY = newSize.height / sourceSize.height
        guard abs(scaleX - 1) > 0.0001 || abs(scaleY - 1) > 0.0001 else {
            return
        }

        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let transformedDrawing = sourceDrawing.transformed(using: transform)
        pendingProgrammaticDrawingData = transformedDrawing.dataRepresentation()
        canvasView.drawing = transformedDrawing
    }

    private static func aspectRatio(for image: UIImage) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else {
            return 4.0 / 3.0
        }

        return image.size.width / image.size.height
    }

    private static func fittedContentSize(in viewportSize: CGSize, aspectRatio: CGFloat) -> CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return .zero
        }

        let safeAspectRatio = max(aspectRatio, 0.1)
        let viewportAspectRatio = viewportSize.width / viewportSize.height
        if safeAspectRatio > viewportAspectRatio {
            return CGSize(
                width: viewportSize.width,
                height: viewportSize.width / safeAspectRatio
            )
        }

        return CGSize(
            width: viewportSize.height * safeAspectRatio,
            height: viewportSize.height
        )
    }
}
