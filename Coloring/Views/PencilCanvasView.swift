import PencilKit
import SwiftUI
import UIKit

struct PencilCanvasView: UIViewRepresentable {
    let templateImage: UIImage
    let templateID: String
    @Binding var drawing: PKDrawing
    var drawingSyncToken: Int = 0
    var onDrawingChanged: ((PKDrawing) -> Void)?
    var onStrokeInteractionChanged: ((Bool) -> Void)?
    var fillMode: Bool = false
    var selectedFillColor: UIColor?
    var fillImage: UIImage?
    /// Normalized tap location in template space (0...1 for both axes).
    var onFillTap: ((CGPoint) -> Void)?
    /// Normalized touch location in template space used to erase a fill region.
    var onFillErase: ((CGPoint) -> Void)?
    var onAppearanceStyleChanged: ((UITraitCollection?) -> Void)?
    var belowLayerImage: UIImage?
    var aboveLayerImage: UIImage?
    var brushTool: PKInkingTool?

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
        context.coordinator.lastTemplateID = templateID
        context.coordinator.lastTemplateImageIdentity = ObjectIdentifier(templateImage)
        context.coordinator.updateFillMode(fillMode, in: containerView)
        containerView.fillImageView.image = fillImage?.stableDisplayImage()
        containerView.belowLayerImageView.image = belowLayerImage?.stableDisplayImage()
        containerView.aboveLayerImageView.image = aboveLayerImage?.stableDisplayImage()
        return containerView
    }

    func updateUIView(_ uiView: ZoomableCanvasContainerView, context: Context) {
        context.coordinator.parent = self

        let canvasView = uiView.canvasView
        let prefersPencilOnly = UIPencilInteraction.prefersPencilOnlyDrawing
        canvasView.drawingPolicy = prefersPencilOnly ? .pencilOnly : .anyInput
        uiView.scrollView.panGestureRecognizer.minimumNumberOfTouches = prefersPencilOnly ? 1 : 2

        let shouldResetZoom = context.coordinator.lastTemplateID != templateID
        if shouldResetZoom {
            context.coordinator.resetLocalDrawingSyncTracking()
        }

        let shouldForceExternalDrawing = context.coordinator.lastDrawingSyncToken != drawingSyncToken
        context.coordinator.lastDrawingSyncToken = drawingSyncToken

        if context.coordinator.shouldApplyExternalDrawing(
            drawing,
            currentCanvasDrawing: canvasView.drawing,
            forceExternalUpdate: shouldForceExternalDrawing
        ) {
            context.coordinator.applyExternalDrawing(drawing, to: canvasView)
        }

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
        context.coordinator.updateFillMode(fillMode, in: uiView)
        context.coordinator.updateBrushTool(brushTool, on: canvasView)
        uiView.fillImageView.image = fillImage?.stableDisplayImage()
        uiView.belowLayerImageView.image = belowLayerImage?.stableDisplayImage()
        uiView.aboveLayerImageView.image = aboveLayerImage?.stableDisplayImage()
    }

    static func dismantleUIView(_ uiView: ZoomableCanvasContainerView, coordinator: Coordinator) {
        coordinator.disconnect(from: uiView.canvasView)
        uiView.canvasView.delegate = nil
        uiView.scrollView.delegate = nil
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver, UIPencilInteractionDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: PencilCanvasView
        private weak var canvasView: PKCanvasView?
        private weak var containerView: ZoomableCanvasContainerView?
        private var toolPicker: PKToolPicker?
        private var pencilInteraction: UIPencilInteraction?
        private var lastInkTool: PKTool = PKInkingTool(.marker, color: .black, width: 12)
        private var isApplyingExternalDrawing = false
        var lastTemplateID: String?
        var lastTemplateImageIdentity: ObjectIdentifier?
        private var fillTapGesture: UITapGestureRecognizer?
        private var fillEraseGesture: UILongPressGestureRecognizer?
        private weak var drawingGestureRecognizer: UIGestureRecognizer?
        private var lastAppliedBrushTool: PKInkingTool?
        private var latestLocalDrawingData: Data?
        private var hasPendingLocalDrawingSync = false
        var lastDrawingSyncToken = 0
        private var pendingLocalSyncResetWorkItem: DispatchWorkItem?
        private var lifecycleObservers: [NSObjectProtocol] = []
        private var lastFillModeState: Bool?
        private let isRunningTests = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        deinit {
            unregisterLifecycleObservers()
        }

        func connect(to canvasView: PKCanvasView, containerView: ZoomableCanvasContainerView) {
            self.canvasView = canvasView
            self.containerView = containerView
            canvasView.tool = lastInkTool
            containerView.appearanceDidChangeHandler = { [weak self] previousTraitCollection in
                self?.handleAppearanceChange(previousTraitCollection: previousTraitCollection)
            }
            installDrawingInteractionTracking(on: canvasView)
            installFillEraseGestureIfNeeded(on: canvasView)
            registerLifecycleObserversIfNeeded()

            guard !isRunningTests else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.recoverToolPickerVisibilityIfNeeded()
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
            toolPicker.addObserver(self)
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
            self.toolPicker = toolPicker

            let interaction = UIPencilInteraction(delegate: self)
            canvasView.addInteraction(interaction)
            pencilInteraction = interaction
        }

        func disconnect(from canvasView: PKCanvasView) {
            if let drawingGestureRecognizer {
                drawingGestureRecognizer.removeTarget(self, action: #selector(handleDrawingGestureStateChange(_:)))
            }

            if let toolPicker {
                toolPicker.removeObserver(canvasView)
                toolPicker.removeObserver(self)
                toolPicker.setVisible(false, forFirstResponder: canvasView)
            }

            if let pencilInteraction {
                canvasView.removeInteraction(pencilInteraction)
            }

            toolPicker = nil
            pencilInteraction = nil
            drawingGestureRecognizer = nil
            fillEraseGesture?.isEnabled = false
            pendingLocalSyncResetWorkItem?.cancel()
            pendingLocalSyncResetWorkItem = nil
            lastFillModeState = nil
            unregisterLifecycleObservers()
            self.canvasView = nil
            containerView?.appearanceDidChangeHandler = nil
            containerView = nil
        }

        private func registerLifecycleObserversIfNeeded() {
            guard lifecycleObservers.isEmpty else {
                return
            }

            let center = NotificationCenter.default
            lifecycleObservers.append(
                center.addObserver(
                    forName: UIApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.recoverToolPickerVisibilityIfNeeded()
                }
            )
            lifecycleObservers.append(
                center.addObserver(
                    forName: UIScene.didActivateNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.recoverToolPickerVisibilityIfNeeded()
                }
            )
            lifecycleObservers.append(
                center.addObserver(
                    forName: UIWindow.didBecomeKeyNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.recoverToolPickerVisibilityIfNeeded()
                }
            )
        }

        private func unregisterLifecycleObservers() {
            guard !lifecycleObservers.isEmpty else {
                return
            }

            let center = NotificationCenter.default
            for observer in lifecycleObservers {
                center.removeObserver(observer)
            }
            lifecycleObservers.removeAll()
        }

        private func recoverToolPickerVisibilityIfNeeded() {
            guard !isRunningTests,
                  let canvasView
            else {
                return
            }

            guard canvasView.window != nil else {
                DispatchQueue.main.async { [weak self] in
                    self?.recoverToolPickerVisibilityIfNeeded()
                }
                return
            }

            if toolPicker == nil {
                installToolingIfPossible()
                return
            }

            toolPicker?.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        private func colorResolutionTraitCollection(for canvasView: PKCanvasView) -> UITraitCollection? {
            if let windowTraitCollection = canvasView.window?.traitCollection {
                return windowTraitCollection
            }

            if let activeSceneTraitCollection = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?
                .traitCollection {
                return activeSceneTraitCollection
            }

            return canvasView.traitCollection
        }

        private func installDrawingInteractionTracking(on canvasView: PKCanvasView) {
            let gesture = canvasView.drawingGestureRecognizer

            guard drawingGestureRecognizer !== gesture else {
                return
            }

            drawingGestureRecognizer?.removeTarget(self, action: #selector(handleDrawingGestureStateChange(_:)))
            drawingGestureRecognizer = gesture
            gesture.addTarget(self, action: #selector(handleDrawingGestureStateChange(_:)))
        }

        func resetLocalDrawingSyncTracking() {
            pendingLocalSyncResetWorkItem?.cancel()
            pendingLocalSyncResetWorkItem = nil
            latestLocalDrawingData = nil
            hasPendingLocalDrawingSync = false
        }

        private func installFillEraseGestureIfNeeded(on canvasView: PKCanvasView) {
            guard fillEraseGesture == nil else {
                return
            }

            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleFillEraseGesture(_:)))
            gesture.minimumPressDuration = 0
            gesture.allowableMovement = .greatestFiniteMagnitude
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            canvasView.addGestureRecognizer(gesture)
            fillEraseGesture = gesture
        }

        func shouldApplyExternalDrawing(
            _ externalDrawing: PKDrawing,
            currentCanvasDrawing: PKDrawing,
            forceExternalUpdate: Bool = false
        ) -> Bool {
            if forceExternalUpdate {
                hasPendingLocalDrawingSync = false
                pendingLocalSyncResetWorkItem?.cancel()
                pendingLocalSyncResetWorkItem = nil
                return currentCanvasDrawing != externalDrawing
            }

            let externalData = externalDrawing.dataRepresentation()
            if let latestLocalDrawingData, latestLocalDrawingData == externalData {
                hasPendingLocalDrawingSync = false
                pendingLocalSyncResetWorkItem?.cancel()
                pendingLocalSyncResetWorkItem = nil
                return false
            } else if currentCanvasDrawing == externalDrawing {
                return false
            }

            if hasPendingLocalDrawingSync {
                return false
            }

            return true
        }

        func applyExternalDrawing(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
            isApplyingExternalDrawing = true
            canvasView.drawing = drawing
            isApplyingExternalDrawing = false
        }

        private func markLocalDrawingChanged(_ drawing: PKDrawing) {
            latestLocalDrawingData = drawing.dataRepresentation()
            hasPendingLocalDrawingSync = true

            pendingLocalSyncResetWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.hasPendingLocalDrawingSync = false
            }
            pendingLocalSyncResetWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        private func handleAppearanceChange(previousTraitCollection: UITraitCollection?) {
            guard let canvasView else {
                return
            }

            normalizeDisplayedDrawing(using: previousTraitCollection, on: canvasView)
            normalizeCurrentTool(using: previousTraitCollection, on: canvasView)
            parent.onAppearanceStyleChanged?(previousTraitCollection)
        }

        private func normalizeDisplayedDrawing(using traitCollection: UITraitCollection?, on canvasView: PKCanvasView) {
            let normalizedDrawing = canvasView.drawing.stableColorDrawing(using: traitCollection)
            guard normalizedDrawing != canvasView.drawing else {
                return
            }

            applyExternalDrawing(normalizedDrawing, to: canvasView)
            parent.drawing = normalizedDrawing
        }

        private func normalizeCurrentTool(using traitCollection: UITraitCollection?, on canvasView: PKCanvasView) {
            if let inkingTool = canvasView.tool as? PKInkingTool {
                let normalizedTool = inkingTool.stableResolvedTool(using: traitCollection)
                canvasView.tool = normalizedTool
                lastInkTool = normalizedTool
            } else if let inkingTool = lastInkTool as? PKInkingTool {
                lastInkTool = inkingTool.stableResolvedTool(using: traitCollection)
            }
        }

        func updateFillMode(_ isFillMode: Bool, in containerView: ZoomableCanvasContainerView) {
            let didFillModeChange = lastFillModeState != isFillMode
            lastFillModeState = isFillMode
            let canvasView = containerView.canvasView
            if isFillMode {
                canvasView.isUserInteractionEnabled = false
                if fillTapGesture == nil {
                    let tap = UITapGestureRecognizer(target: self, action: #selector(handleFillTap(_:)))
                    tap.numberOfTapsRequired = 1
                    containerView.contentView.addGestureRecognizer(tap)
                    fillTapGesture = tap
                }
                fillTapGesture?.isEnabled = true
            } else {
                canvasView.isUserInteractionEnabled = true
                fillTapGesture?.isEnabled = false
                if didFillModeChange {
                    recoverToolPickerVisibilityIfNeeded()
                }
            }
        }

        func updateBrushTool(_ brushTool: PKInkingTool?, on canvasView: PKCanvasView) {
            guard let brushTool else {
                return
            }

            let normalizedBrushTool = brushTool.stableResolvedTool(
                using: colorResolutionTraitCollection(for: canvasView)
            )

            // Only apply if the brush tool actually changed to avoid fighting with PKToolPicker.
            if let last = lastAppliedBrushTool,
               last.inkType == normalizedBrushTool.inkType,
               last.width == normalizedBrushTool.width,
               last.color == normalizedBrushTool.color
            {
                return
            }

            lastAppliedBrushTool = normalizedBrushTool
            lastInkTool = normalizedBrushTool
            canvasView.tool = normalizedBrushTool
        }

        func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
            guard let canvasView else {
                return
            }

            DispatchQueue.main.async { [weak self, weak canvasView] in
                guard let self, let canvasView else {
                    return
                }

                self.normalizeCurrentTool(
                    using: self.colorResolutionTraitCollection(for: canvasView),
                    on: canvasView
                )
            }
        }

        @objc private func handleFillTap(_ gesture: UITapGestureRecognizer) {
            guard let normalizedPoint = normalizedTemplatePoint(for: gesture) else {
                return
            }

            parent.onFillTap?(normalizedPoint)
        }

        @objc private func handleFillEraseGesture(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed,
                  !parent.fillMode,
                  canvasView?.tool is PKEraserTool,
                  let normalizedPoint = normalizedTemplatePoint(for: gesture)
            else {
                return
            }

            parent.onFillErase?(normalizedPoint)
        }

        private func normalizedTemplatePoint(for gesture: UIGestureRecognizer) -> CGPoint? {
            guard let containerView else {
                return nil
            }

            let location = gesture.location(in: containerView.contentView)
            let contentSize = containerView.contentView.bounds.size
            guard contentSize.width > 0, contentSize.height > 0 else {
                return nil
            }

            let normalizedX = min(max(location.x / contentSize.width, 0), 1)
            let normalizedY = min(max(location.y / contentSize.height, 0), 1)
            return CGPoint(x: normalizedX, y: normalizedY)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else {
                return
            }

            let normalizedDrawing = canvasView.drawing.stableColorDrawing(
                using: colorResolutionTraitCollection(for: canvasView)
            )
            markLocalDrawingChanged(normalizedDrawing)
            parent.drawing = normalizedDrawing
            parent.onDrawingChanged?(normalizedDrawing)
        }

        @objc private func handleDrawingGestureStateChange(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.onStrokeInteractionChanged?(true)
            case .ended, .cancelled, .failed:
                parent.onStrokeInteractionChanged?(false)
            default:
                break
            }
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
            recoverToolPickerVisibilityIfNeeded()
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

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === fillEraseGesture || otherGestureRecognizer === fillEraseGesture
        }
    }
}

final class ZoomableCanvasContainerView: UIView {
    let scrollView = UIScrollView()
    let contentView = UIView()
    let imageView = UIImageView()
    let fillImageView = UIImageView()
    let belowLayerImageView = UIImageView()
    let canvasView = PKCanvasView()
    let aboveLayerImageView = UIImageView()

    private var currentTemplateID: String = ""
    private var canvasBaseSize: CGSize = .zero
    private var lastFitZoomScale: CGFloat = 1.0
    private let maxCanvasLongEdge: CGFloat = 2048
    var appearanceDidChangeHandler: ((UITraitCollection?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
        installTraitObserverIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds

        // Keep the user's zoom during normal layout passes.
        // On rotation/resizing, if the user was at "fit", we'll snap to the new fit scale.
        updateZoomScaleLimits(maintainUserZoom: true)
    }

    func applyTemplateImage(_ image: UIImage, templateID: String, resetZoom: Bool) {
        imageView.image = image.stableDisplayImage()
        let templateChanged = currentTemplateID != templateID
        currentTemplateID = templateID

        canvasBaseSize = Self.normalizedCanvasSize(for: image, maxLongEdge: maxCanvasLongEdge)
        layoutContentFrame()

        setNeedsLayout()
        layoutIfNeeded()

        updateZoomScaleLimits(maintainUserZoom: !resetZoom && !templateChanged)
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

        contentView.backgroundColor = .white
        scrollView.addSubview(contentView)
        lockArtworkAppearanceToLight()

        imageView.backgroundColor = .white
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        fillImageView.isOpaque = false
        fillImageView.backgroundColor = .clear
        fillImageView.contentMode = .scaleToFill
        fillImageView.clipsToBounds = true
        contentView.addSubview(fillImageView)

        belowLayerImageView.isOpaque = false
        belowLayerImageView.backgroundColor = .clear
        belowLayerImageView.contentMode = .scaleToFill
        belowLayerImageView.clipsToBounds = true
        contentView.addSubview(belowLayerImageView)

        canvasView.isOpaque = false
        canvasView.backgroundColor = .clear
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.isScrollEnabled = false
        canvasView.contentInset = .zero
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        contentView.addSubview(canvasView)

        aboveLayerImageView.isOpaque = false
        aboveLayerImageView.backgroundColor = .clear
        aboveLayerImageView.contentMode = .scaleToFill
        aboveLayerImageView.clipsToBounds = true
        aboveLayerImageView.isUserInteractionEnabled = false
        contentView.addSubview(aboveLayerImageView)
    }

    private func lockArtworkAppearanceToLight() {
        let artworkViews: [UIView] = [
            contentView,
            imageView,
            fillImageView,
            belowLayerImageView,
            canvasView,
            aboveLayerImageView
        ]

        for view in artworkViews {
            view.overrideUserInterfaceStyle = .light
        }
    }

    private func installTraitObserverIfNeeded() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
                self.appearanceDidChangeHandler?(previousTraitCollection)
            }
        }
    }

    private func layoutContentFrame() {
        let contentSize = canvasBaseSize == .zero ? CGSize(width: 1024, height: 768) : canvasBaseSize
        contentView.frame = CGRect(origin: .zero, size: contentSize)
        imageView.frame = contentView.bounds
        fillImageView.frame = contentView.bounds
        belowLayerImageView.frame = contentView.bounds
        canvasView.frame = contentView.bounds
        aboveLayerImageView.frame = contentView.bounds
        scrollView.contentSize = contentSize
    }

    private func updateZoomScaleLimits(maintainUserZoom: Bool) {
        guard contentView.bounds.width > 0,
              contentView.bounds.height > 0,
              scrollView.bounds.width > 0,
              scrollView.bounds.height > 0
        else {
            return
        }

        let fitScaleX = scrollView.bounds.width / contentView.bounds.width
        let fitScaleY = scrollView.bounds.height / contentView.bounds.height
        let fitScale = min(fitScaleX, fitScaleY)

        // Allow users to zoom out to 1.0 even on large iPads where "fit" would upscale.
        scrollView.minimumZoomScale = min(fitScale, 1.0)
        scrollView.maximumZoomScale = max(scrollView.minimumZoomScale * 8.0, 8.0)

        let isEffectivelyAtFit = abs(scrollView.zoomScale - lastFitZoomScale) < 0.02
        let shouldSnapToFit = !maintainUserZoom || isEffectivelyAtFit

        if shouldSnapToFit {
            scrollView.zoomScale = fitScale
        } else if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }

        lastFitZoomScale = fitScale
        updateContentInsetForCentering()

        if shouldSnapToFit {
            scrollView.contentOffset = CGPoint(
                x: -scrollView.contentInset.left,
                y: -scrollView.contentInset.top
            )
        }
    }

    private static func normalizedCanvasSize(for image: UIImage, maxLongEdge: CGFloat) -> CGSize {
        let rawSize = image.size
        guard rawSize.width > 0, rawSize.height > 0 else {
            return CGSize(width: 1024, height: 768)
        }

        let longEdge = max(rawSize.width, rawSize.height)
        guard longEdge > maxLongEdge else {
            return rawSize
        }

        let scale = maxLongEdge / longEdge
        return CGSize(width: rawSize.width * scale, height: rawSize.height * scale)
    }
}
