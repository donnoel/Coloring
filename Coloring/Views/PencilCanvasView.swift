import Combine
import PencilKit
import SwiftUI
import UIKit

@MainActor
enum PencilCanvasGesturePolicy {
    static func shouldEnableFillEraseGesture(fillMode: Bool) -> Bool {
        !fillMode
    }

    static func shouldReceiveFillEraseTouch(fillMode: Bool, isEraserToolActive: Bool) -> Bool {
        !fillMode && isEraserToolActive
    }

    static func shouldRecognizeSimultaneously(
        _ gestureRecognizer: UIGestureRecognizer,
        with otherGestureRecognizer: UIGestureRecognizer,
        fillEraseGesture: UIGestureRecognizer?,
        drawingGestureRecognizer: UIGestureRecognizer?,
        panGestureRecognizer: UIGestureRecognizer?,
        pinchGestureRecognizer: UIGestureRecognizer?
    ) -> Bool {
        guard let fillEraseGesture else {
            return false
        }

        let pairedGesture: UIGestureRecognizer
        if gestureRecognizer === fillEraseGesture {
            pairedGesture = otherGestureRecognizer
        } else if otherGestureRecognizer === fillEraseGesture {
            pairedGesture = gestureRecognizer
        } else {
            return false
        }

        return pairedGesture === drawingGestureRecognizer
            || pairedGesture === panGestureRecognizer
            || pairedGesture === pinchGestureRecognizer
    }
}

@MainActor
enum PencilCanvasToolPickerRecoveryPolicy {
    static func shouldRequestVisibility(
        isSuppressed: Bool,
        isDrawingInteractionActive: Bool,
        hasActiveTextInput: Bool
    ) -> Bool {
        !isSuppressed
            && !isDrawingInteractionActive
            && !hasActiveTextInput
    }

    static func shouldRetry(attemptCount: Int, maximumAttemptCount: Int) -> Bool {
        attemptCount < maximumAttemptCount
    }
}

@MainActor
final class PencilCanvasUndoBridge: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoHandler: (() -> Bool)?
    private var redoHandler: (() -> Bool)?

    func performUndo() -> Bool {
        undoHandler?() ?? false
    }

    func performRedo() -> Bool {
        redoHandler?() ?? false
    }

    fileprivate func connect(
        undoHandler: @escaping () -> Bool,
        redoHandler: @escaping () -> Bool
    ) {
        self.undoHandler = undoHandler
        self.redoHandler = redoHandler
    }

    fileprivate func updateAvailability(canUndo: Bool, canRedo: Bool) {
        if self.canUndo != canUndo {
            self.canUndo = canUndo
        }
        if self.canRedo != canRedo {
            self.canRedo = canRedo
        }
    }

    fileprivate func disconnect() {
        undoHandler = nil
        redoHandler = nil
        updateAvailability(canUndo: false, canRedo: false)
    }
}

struct PencilCanvasView: UIViewRepresentable {
    let templateImage: UIImage
    let templateID: String
    @Binding var drawing: PKDrawing
    var drawingSyncToken: Int = 0
    var onDrawingChanged: ((PKDrawing) -> Void)?
    var onPencilKitUndoDrawingChanged: ((PKDrawing) -> Void)?
    var onPencilKitRedoDrawingChanged: ((PKDrawing) -> Void)?
    var onStrokeInteractionChanged: ((Bool) -> Void)?
    var fillMode: Bool = false
    var fillImage: UIImage?
    /// Normalized tap location in template space (0...1 for both axes).
    var onFillTap: ((CGPoint, UIColor) -> Void)?
    /// Normalized touch location in template space used to erase a fill region.
    var onFillErase: ((CGPoint) -> Void)?
    var onFillEraseInteractionChanged: ((Bool) -> Void)?
    var onAppearanceStyleChanged: ((UITraitCollection?) -> Void)?
    var belowLayerImage: UIImage?
    var aboveLayerImage: UIImage?
    var activeColorOverride: UIColor?
    var activeColorOverrideRevision: Int = 0
    var activationToken: Int = 0
    var isToolPickerSuppressed: Bool = false
    var undoBridge: PencilCanvasUndoBridge?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ZoomableCanvasContainerView {
        let containerView = ZoomableCanvasContainerView()
        let canvasView = containerView.canvasView
        let prefersPencilOnly = UIPencilInteraction.prefersPencilOnlyDrawing

        // Establish the template-sized drawing surface before restoring PencilKit content.
        // Assigning a drawing while PKCanvasView is still zero-sized can leave its internal
        // renderer using a stale scale or offset until the view is rebuilt.
        containerView.applyTemplateImage(templateImage, templateID: templateID, resetZoom: true)
        canvasView.drawing = drawing
        canvasView.drawingPolicy = prefersPencilOnly ? .pencilOnly : .anyInput
        canvasView.panGestureRecognizer.minimumNumberOfTouches = prefersPencilOnly ? 1 : 2
        canvasView.delegate = context.coordinator

        context.coordinator.connect(to: canvasView, containerView: containerView)
        context.coordinator.updateUndoBridge(undoBridge)
        context.coordinator.updateToolPickerSuppression(isToolPickerSuppressed, on: canvasView)
        context.coordinator.lastTemplateID = templateID
        context.coordinator.lastTemplateImageIdentity = ObjectIdentifier(templateImage)
        context.coordinator.updateFillMode(fillMode, in: containerView)
        context.coordinator.updateOverlayImages(
            in: containerView,
            fillImage: fillImage,
            belowLayerImage: belowLayerImage,
            aboveLayerImage: aboveLayerImage
        )
        return containerView
    }

    func updateUIView(_ uiView: ZoomableCanvasContainerView, context: Context) {
        context.coordinator.parent = self

        let canvasView = uiView.canvasView
        let prefersPencilOnly = UIPencilInteraction.prefersPencilOnlyDrawing
        canvasView.drawingPolicy = prefersPencilOnly ? .pencilOnly : .anyInput
        canvasView.panGestureRecognizer.minimumNumberOfTouches = prefersPencilOnly ? 1 : 2
        context.coordinator.updateUndoBridge(undoBridge)

        let shouldResetZoom = context.coordinator.lastTemplateID != templateID
        if shouldResetZoom {
            context.coordinator.resetLocalDrawingSyncTracking()
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

        let shouldForceExternalDrawing = context.coordinator.lastDrawingSyncToken != drawingSyncToken
        context.coordinator.lastDrawingSyncToken = drawingSyncToken

        if context.coordinator.shouldApplyExternalDrawing(
            drawing,
            currentCanvasDrawing: canvasView.drawing,
            forceExternalUpdate: shouldForceExternalDrawing
        ) {
            context.coordinator.applyExternalDrawing(drawing, to: canvasView)
        }

        context.coordinator.lastTemplateID = templateID
        context.coordinator.updateToolPickerSuppression(isToolPickerSuppressed, on: canvasView)
        context.coordinator.updateActivationToken(activationToken, on: canvasView)
        context.coordinator.updateFillMode(fillMode, in: uiView)
        context.coordinator.applyActiveColorOverride(
            activeColorOverride,
            revision: activeColorOverrideRevision,
            on: canvasView
        )
        context.coordinator.suppressEditMenuInteractions(on: canvasView)
        context.coordinator.updateOverlayImages(
            in: uiView,
            fillImage: fillImage,
            belowLayerImage: belowLayerImage,
            aboveLayerImage: aboveLayerImage
        )
    }

    static func dismantleUIView(_ uiView: ZoomableCanvasContainerView, coordinator: Coordinator) {
        coordinator.disconnect(from: uiView.canvasView)
        uiView.canvasView.delegate = nil
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver, UIPencilInteractionDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: PencilCanvasView
        private weak var canvasView: PKCanvasView?
        private weak var containerView: ZoomableCanvasContainerView?
        private weak var undoBridge: PencilCanvasUndoBridge?
        private var toolPicker: PKToolPicker?
        private var pencilInteraction: UIPencilInteraction?
        private var isToolPickerSuppressed = false
        private var lastAppliedToolPickerSuppression: Bool?
        private var lastInkTool: PKTool = PKInkingTool(.marker, color: .black, width: 12)
        private var lastInkToolItemIdentifier: String?
        private var lastEraserToolItemIdentifier: String?
        private var isApplyingExternalDrawing = false
        var lastTemplateID: String?
        var lastTemplateImageIdentity: ObjectIdentifier?
        private var fillTapGesture: UITapGestureRecognizer?
        private var fillEraseGesture: UILongPressGestureRecognizer?
        private var isFillEraseInteractionActive = false
        private weak var drawingGestureRecognizer: UIGestureRecognizer?
        private var lastSourceFillImageIdentity: ObjectIdentifier?
        private var lastSourceBelowLayerImageIdentity: ObjectIdentifier?
        private var lastSourceAboveLayerImageIdentity: ObjectIdentifier?
        private var latestLocalDrawing: PKDrawing?
        var lastDrawingSyncToken: Int
        private var lastFillModeState: Bool?
        private var lastActivationToken = 0
        private var lastColorOverrideRevision = 0
        private var isDrawingInteractionActive = false
        private var pendingToolPickerRecoveryWorkItem: DispatchWorkItem?
        private var toolPickerRecoveryAttemptCount = 0
        private let maximumToolPickerRecoveryAttemptCount = 6
        private let toolPickerRecoveryDelay: TimeInterval = 0.15

        init(_ parent: PencilCanvasView) {
            self.parent = parent
            lastDrawingSyncToken = parent.drawingSyncToken
        }

        func connect(to canvasView: PKCanvasView, containerView: ZoomableCanvasContainerView) {
            self.canvasView = canvasView
            self.containerView = containerView
            lastActivationToken = parent.activationToken
            canvasView.tool = lastInkTool
            containerView.appearanceDidChangeHandler = { [weak self] previousTraitCollection in
                self?.handleAppearanceChange(previousTraitCollection: previousTraitCollection)
            }
            installDrawingInteractionTracking(on: canvasView)
            installFillEraseGestureIfNeeded(on: canvasView)
            installPencilInteractionIfNeeded(on: canvasView)
            suppressEditMenuInteractions(on: canvasView)
        }

        private func installPencilInteractionIfNeeded(on canvasView: PKCanvasView) {
            guard pencilInteraction == nil else {
                return
            }

            let interaction = UIPencilInteraction(delegate: self)
            canvasView.addInteraction(interaction)
            pencilInteraction = interaction
        }

        private func installToolingIfPossible(on canvasView: PKCanvasView) {
            guard toolPicker == nil,
                  canvasView.window != nil
            else {
                return
            }

            let toolPicker = PKToolPicker()
            toolPicker.stateAutosaveName = "Coloring.TemplateStudio.ToolPicker"
            toolPicker.addObserver(canvasView)
            toolPicker.addObserver(self)
            applyToolPickerAppearance(for: toolPicker, on: canvasView)
            canvasView.pencilKitResponderState.activeToolPicker = toolPicker
            self.toolPicker = toolPicker
            rememberSelectedToolItem(from: toolPicker, on: canvasView)
        }

        func disconnect(from canvasView: PKCanvasView) {
            if let drawingGestureRecognizer {
                drawingGestureRecognizer.removeTarget(self, action: #selector(handleDrawingGestureStateChange(_:)))
            }

            if let toolPicker {
                toolPicker.removeObserver(canvasView)
                toolPicker.removeObserver(self)
                canvasView.pencilKitResponderState.toolPickerVisibility = .inactive
                canvasView.pencilKitResponderState.activeToolPicker = nil
            }

            if let pencilInteraction {
                canvasView.removeInteraction(pencilInteraction)
            }

            toolPicker = nil
            pencilInteraction = nil
            drawingGestureRecognizer = nil
            if isFillEraseInteractionActive {
                parent.onFillEraseInteractionChanged?(false)
                isFillEraseInteractionActive = false
            }
            fillEraseGesture?.isEnabled = false
            lastSourceFillImageIdentity = nil
            lastSourceBelowLayerImageIdentity = nil
            lastSourceAboveLayerImageIdentity = nil
            pendingToolPickerRecoveryWorkItem?.cancel()
            pendingToolPickerRecoveryWorkItem = nil
            toolPickerRecoveryAttemptCount = 0
            isDrawingInteractionActive = false
            lastFillModeState = nil
            isToolPickerSuppressed = false
            lastAppliedToolPickerSuppression = nil
            lastActivationToken = 0
            undoBridge?.disconnect()
            undoBridge = nil
            self.canvasView = nil
            containerView?.appearanceDidChangeHandler = nil
            containerView = nil
        }

        func updateUndoBridge(_ bridge: PencilCanvasUndoBridge?) {
            guard undoBridge !== bridge else {
                refreshUndoAvailability()
                return
            }

            undoBridge?.disconnect()
            undoBridge = bridge
            bridge?.connect(
                undoHandler: { [weak self] in
                    self?.performUndo() ?? false
                },
                redoHandler: { [weak self] in
                    self?.performRedo() ?? false
                }
            )
            refreshUndoAvailability()
        }

        @discardableResult
        func updateToolPickerSuppression(_ isSuppressed: Bool, on canvasView: PKCanvasView) -> Bool {
            guard lastAppliedToolPickerSuppression != isSuppressed else {
                return false
            }

            lastAppliedToolPickerSuppression = isSuppressed
            isToolPickerSuppressed = isSuppressed
            if isSuppressed {
                cancelPendingToolPickerRecovery()
            }
            applyToolPickerVisibility(on: canvasView)
            return true
        }

        func updateActivationToken(_ activationToken: Int, on canvasView: PKCanvasView) {
            guard activationToken != lastActivationToken else {
                return
            }

            lastActivationToken = activationToken
            guard !isToolPickerSuppressed else {
                return
            }

            applyToolPickerVisibility(on: canvasView)
        }

        func updateOverlayImages(
            in containerView: ZoomableCanvasContainerView,
            fillImage: UIImage?,
            belowLayerImage: UIImage?,
            aboveLayerImage: UIImage?
        ) {
            let fillImageIdentity = fillImage.map(ObjectIdentifier.init)
            if fillImageIdentity != lastSourceFillImageIdentity {
                containerView.fillImageView.image = fillImage?.stableDisplayImage()
                lastSourceFillImageIdentity = fillImageIdentity
            }

            let belowLayerImageIdentity = belowLayerImage.map(ObjectIdentifier.init)
            if belowLayerImageIdentity != lastSourceBelowLayerImageIdentity {
                containerView.belowLayerImageView.image = belowLayerImage?.stableDisplayImage()
                lastSourceBelowLayerImageIdentity = belowLayerImageIdentity
            }

            let aboveLayerImageIdentity = aboveLayerImage.map(ObjectIdentifier.init)
            if aboveLayerImageIdentity != lastSourceAboveLayerImageIdentity {
                containerView.aboveLayerImageView.image = aboveLayerImage?.stableDisplayImage()
                lastSourceAboveLayerImageIdentity = aboveLayerImageIdentity
            }
        }

        private func applyToolPickerVisibility(on canvasView: PKCanvasView) {
            if isToolPickerSuppressed {
                hideToolPicker(on: canvasView)
                return
            }

            showToolPicker(on: canvasView)
        }

        private func showToolPicker(on canvasView: PKCanvasView) {
            cancelPendingToolPickerRecovery()
            attemptToolPickerVisibility(on: canvasView)
        }

        private func applyToolPickerAppearance(for toolPicker: PKToolPicker, on canvasView: PKCanvasView) {
            let interfaceStyle = canvasView.traitCollection.userInterfaceStyle
            toolPicker.overrideUserInterfaceStyle = interfaceStyle
            // Keep white/black color selection behavior stable regardless of app appearance.
            toolPicker.colorUserInterfaceStyle = .light
        }

        private func colorResolutionTraitCollection(for _: PKCanvasView) -> UITraitCollection {
            UITraitCollection(userInterfaceStyle: .light)
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
            clearPendingLocalDrawingSync()
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
                clearPendingLocalDrawingSync()
                return currentCanvasDrawing != externalDrawing
            }

            if let latestLocalDrawing, latestLocalDrawing == externalDrawing {
                return false
            }

            if currentCanvasDrawing == externalDrawing {
                return false
            }

            // Ordinary SwiftUI updates can arrive out of order after the binding catches up.
            // Only a model restore with a new sync token may replace the live canvas.
            if latestLocalDrawing != nil {
                return false
            }

            return true
        }

        func applyExternalDrawing(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
            isApplyingExternalDrawing = true
            canvasView.drawing = drawing
            isApplyingExternalDrawing = false
            refreshUndoAvailability()
        }

        private func markLocalDrawingChanged(_ drawing: PKDrawing) {
            latestLocalDrawing = drawing
        }

        private func clearPendingLocalDrawingSync() {
            latestLocalDrawing = nil
        }

        private func performUndo() -> Bool {
            guard let undoManager = canvasView?.undoManager,
                  undoManager.canUndo
            else {
                refreshUndoAvailability()
                return false
            }

            undoManager.undo()
            refreshUndoAvailability()
            return true
        }

        private func performRedo() -> Bool {
            guard let undoManager = canvasView?.undoManager,
                  undoManager.canRedo
            else {
                refreshUndoAvailability()
                return false
            }

            undoManager.redo()
            refreshUndoAvailability()
            return true
        }

        private func refreshUndoAvailability() {
            let undoManager = canvasView?.undoManager
            undoBridge?.updateAvailability(
                canUndo: undoManager?.canUndo ?? false,
                canRedo: undoManager?.canRedo ?? false
            )
        }

        private func handleAppearanceChange(previousTraitCollection _: UITraitCollection?) {
            guard let canvasView else {
                return
            }

            if let toolPicker {
                applyToolPickerAppearance(for: toolPicker, on: canvasView)
            }
            let artworkTraitCollection = colorResolutionTraitCollection(for: canvasView)
            normalizeDisplayedDrawing(using: artworkTraitCollection, on: canvasView)
            normalizeCurrentTool(using: artworkTraitCollection, on: canvasView)
            parent.onAppearanceStyleChanged?(artworkTraitCollection)
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
            fillEraseGesture?.isEnabled = PencilCanvasGesturePolicy.shouldEnableFillEraseGesture(
                fillMode: isFillMode
            )
            if isFillMode {
                drawingGestureRecognizer?.isEnabled = false
                if fillTapGesture == nil {
                    let tap = UITapGestureRecognizer(target: self, action: #selector(handleFillTap(_:)))
                    tap.numberOfTapsRequired = 1
                    tap.cancelsTouchesInView = false
                    containerView.canvasView.addGestureRecognizer(tap)
                    fillTapGesture = tap
                }
                fillTapGesture?.isEnabled = true
                refreshToolPickerVisibilityIfPossible()
            } else {
                drawingGestureRecognizer?.isEnabled = true
                fillTapGesture?.isEnabled = false
                if didFillModeChange {
                    refreshToolPickerVisibilityIfPossible()
                }
            }
        }

        func applyActiveColorOverride(_ color: UIColor?, revision: Int, on canvasView: PKCanvasView) {
            guard revision != lastColorOverrideRevision else {
                return
            }

            lastColorOverrideRevision = revision
            guard let color else {
                return
            }

            let normalizedColor = color.stableResolvedColor(using: colorResolutionTraitCollection(for: canvasView))
            let sourceTool = (canvasView.tool as? PKInkingTool) ?? (lastInkTool as? PKInkingTool)
            let updatedTool = PKInkingTool(
                sourceTool?.inkType ?? .marker,
                color: normalizedColor,
                width: sourceTool?.width ?? 12
            )
            lastInkTool = updatedTool
            canvasView.tool = updatedTool
            syncPickerDisplayedTool(to: updatedTool, on: canvasView)
        }

        private func syncPickerDisplayedTool(to tool: PKTool, on canvasView: PKCanvasView) {
            guard let toolPicker else {
                return
            }

            // selectedToolItem can select an item by identifier, but it does not apply an
            // app-selected color to that item. Keep the compact glyph aligned with the canvas.
            toolPicker.setValue(tool, forKey: "selectedTool")
            showToolPicker(on: canvasView)
        }

        func suppressEditMenuInteractions(on canvasView: PKCanvasView) {
            if #available(iOS 16.0, *) {
                let views = [canvasView] + canvasView.subviewsRecursive
                for view in views {
                    for interaction in view.interactions where interaction is UIEditMenuInteraction {
                        view.removeInteraction(interaction)
                    }
                }
            }
        }

        func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
            guard let canvasView else {
                return
            }

            DispatchQueue.main.async { [weak self, weak canvasView] in
                guard let self, let canvasView else {
                    return
                }

                self.rememberSelectedToolItem(from: toolPicker, on: canvasView)
                self.normalizeCurrentTool(
                    using: self.colorResolutionTraitCollection(for: canvasView),
                    on: canvasView
                )
            }
        }

        private func rememberSelectedToolItem(from toolPicker: PKToolPicker, on canvasView: PKCanvasView) {
            let selectedItem = toolPicker.selectedToolItem
            if selectedItem.tool is PKInkingTool {
                lastInkToolItemIdentifier = selectedItem.identifier
                if let inkingTool = canvasView.tool as? PKInkingTool {
                    lastInkTool = inkingTool
                }
            } else if selectedItem.tool is PKEraserTool {
                lastEraserToolItemIdentifier = selectedItem.identifier
            }
        }

        func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
            if toolPicker.isVisible {
                cancelPendingToolPickerRecovery()
                return
            }

            scheduleToolPickerRecovery(on: canvasView)
        }

        @objc private func handleFillTap(_ gesture: UITapGestureRecognizer) {
            guard let normalizedPoint = normalizedTemplatePoint(for: gesture),
                  let fillColor = activeFillColor()
            else {
                return
            }

            parent.onFillTap?(normalizedPoint, fillColor)
            refreshToolPickerVisibilityIfPossible()
        }

        @objc private func handleFillEraseGesture(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard !parent.fillMode, canvasView?.tool is PKEraserTool else {
                    return
                }

                cleanUpFillEraseInteractions()
                isFillEraseInteractionActive = true
                parent.onFillEraseInteractionChanged?(true)
                if let normalizedPoint = normalizedTemplatePoint(for: gesture) {
                    parent.onFillErase?(normalizedPoint)
                }
            case .changed:
                guard isFillEraseInteractionActive,
                      let normalizedPoint = normalizedTemplatePoint(for: gesture)
                else {
                    return
                }

                parent.onFillErase?(normalizedPoint)
            case .ended, .cancelled, .failed:
                guard isFillEraseInteractionActive else {
                    return
                }

                isFillEraseInteractionActive = false
                parent.onFillEraseInteractionChanged?(false)
                cleanUpFillEraseInteractions()
            default:
                break
            }
        }

        private func cleanUpFillEraseInteractions() {
            guard let canvasView else {
                return
            }

            suppressEditMenuInteractions(on: canvasView)
            DispatchQueue.main.async { [weak self, weak canvasView] in
                guard let self, let canvasView else {
                    return
                }

                self.suppressEditMenuInteractions(on: canvasView)
            }
        }

        private func normalizedTemplatePoint(for gesture: UIGestureRecognizer) -> CGPoint? {
            guard let containerView else {
                return nil
            }

            return containerView.normalizedArtworkPoint(
                fromContainerLocation: gesture.location(in: containerView)
            )
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else {
                return
            }

            let updatedDrawing = canvasView.drawing
            if latestLocalDrawing == updatedDrawing,
               parent.drawing == updatedDrawing
            {
                return
            }

            markLocalDrawingChanged(updatedDrawing)
            if canvasView.undoManager?.isUndoing == true,
               let onPencilKitUndoDrawingChanged = parent.onPencilKitUndoDrawingChanged {
                onPencilKitUndoDrawingChanged(updatedDrawing)
            } else if canvasView.undoManager?.isRedoing == true,
                      let onPencilKitRedoDrawingChanged = parent.onPencilKitRedoDrawingChanged {
                onPencilKitRedoDrawingChanged(updatedDrawing)
            } else if let onDrawingChanged = parent.onDrawingChanged {
                onDrawingChanged(updatedDrawing)
            } else {
                parent.drawing = updatedDrawing
            }
            refreshUndoAvailability()
            DispatchQueue.main.async { [weak self] in
                self?.refreshUndoAvailability()
            }
        }

        @objc private func handleDrawingGestureStateChange(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began:
                isDrawingInteractionActive = true
                cancelPendingToolPickerRecovery()
                parent.onStrokeInteractionChanged?(true)
            case .ended, .cancelled, .failed:
                isDrawingInteractionActive = false
                parent.onStrokeInteractionChanged?(false)
                if let toolPicker, !toolPicker.isVisible {
                    scheduleToolPickerRecovery(on: canvasView)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.refreshUndoAvailability()
                }
            default:
                break
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let containerView,
                  scrollView === containerView.canvasView
            else {
                return
            }

            containerView.updateCanvasViewport()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let containerView,
                  scrollView === containerView.canvasView
            else {
                return
            }

            containerView.updateArtworkViewport()
        }

        func pencilInteraction(_: UIPencilInteraction, didReceiveTap _: UIPencilInteraction.Tap) {
            handlePencilTap(preferredAction: UIPencilInteraction.preferredTapAction)
        }

        func handlePencilTap(preferredAction: UIPencilPreferredAction) {
            if preferredAction == .switchEraser {
                toggleEraser()
            } else {
                showToolPicker()
            }
        }

        func pencilInteraction(_: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended else {
                return
            }

            switchToEraser()
        }

        private func showToolPicker() {
            refreshToolPickerVisibilityIfPossible()
        }

        private func hideToolPicker(on canvasView: PKCanvasView) {
            canvasView.pencilKitResponderState.toolPickerVisibility = .inactive
            canvasView.resignFirstResponder()
        }

        private func refreshToolPickerVisibilityIfPossible() {
            guard let canvasView else {
                return
            }

            applyToolPickerVisibility(on: canvasView)
        }

        private func attemptToolPickerVisibility(on canvasView: PKCanvasView) {
            pendingToolPickerRecoveryWorkItem = nil

            guard shouldRequestToolPickerVisibility() else {
                cancelPendingToolPickerRecovery()
                return
            }

            guard UIApplication.shared.applicationState == .active,
                  let window = canvasView.window,
                  window.isKeyWindow
            else {
                scheduleToolPickerRecovery(on: canvasView)
                return
            }

            installToolingIfPossible(on: canvasView)
            guard let toolPicker else {
                scheduleToolPickerRecovery(on: canvasView)
                return
            }

            let didAcquireFirstResponder = canvasView.isFirstResponder || canvasView.becomeFirstResponder()
            guard didAcquireFirstResponder, canvasView.isFirstResponder else {
                scheduleToolPickerRecovery(on: canvasView)
                return
            }

            canvasView.pencilKitResponderState.activeToolPicker = toolPicker
            canvasView.pencilKitResponderState.toolPickerVisibility = .visible
            guard toolPicker.isVisible else {
                scheduleToolPickerRecovery(on: canvasView)
                return
            }

            cancelPendingToolPickerRecovery()
        }

        private func scheduleToolPickerRecovery(on canvasView: PKCanvasView?) {
            guard let canvasView,
                  shouldRequestToolPickerVisibility(),
                  PencilCanvasToolPickerRecoveryPolicy.shouldRetry(
                      attemptCount: toolPickerRecoveryAttemptCount,
                      maximumAttemptCount: maximumToolPickerRecoveryAttemptCount
                  )
            else {
                cancelPendingToolPickerRecovery()
                return
            }

            guard pendingToolPickerRecoveryWorkItem == nil else {
                return
            }

            toolPickerRecoveryAttemptCount += 1
            let recoveryWorkItem = DispatchWorkItem { [weak self, weak canvasView] in
                guard let self, let canvasView else {
                    return
                }

                self.pendingToolPickerRecoveryWorkItem = nil
                self.attemptToolPickerVisibility(on: canvasView)
            }
            pendingToolPickerRecoveryWorkItem = recoveryWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + toolPickerRecoveryDelay,
                execute: recoveryWorkItem
            )
        }

        private func shouldRequestToolPickerVisibility() -> Bool {
            let activeResponder = UIResponder.currentFirstResponder
            let hasActiveTextInput = activeResponder is UITextField || activeResponder is UITextView
            return PencilCanvasToolPickerRecoveryPolicy.shouldRequestVisibility(
                isSuppressed: isToolPickerSuppressed,
                isDrawingInteractionActive: isDrawingInteractionActive,
                hasActiveTextInput: hasActiveTextInput
            )
        }

        private func cancelPendingToolPickerRecovery() {
            pendingToolPickerRecoveryWorkItem?.cancel()
            pendingToolPickerRecoveryWorkItem = nil
            toolPickerRecoveryAttemptCount = 0
        }

        private func switchToEraser() {
            guard let canvasView else {
                return
            }

            if let inkingTool = canvasView.tool as? PKInkingTool {
                lastInkTool = inkingTool
            }

            if let eraserItem = preferredToolPickerItem(
                identifier: lastEraserToolItemIdentifier,
                matching: { $0.tool is PKEraserTool }
            ) {
                toolPicker?.selectedToolItem = eraserItem
                if let eraserTool = eraserItem.tool {
                    canvasView.tool = eraserTool
                }
            } else {
                canvasView.tool = PKEraserTool(.bitmap)
            }
            showToolPicker(on: canvasView)
        }

        private func toggleEraser() {
            guard let canvasView else {
                return
            }

            if canvasView.tool is PKEraserTool {
                if let inkItem = preferredToolPickerItem(
                    identifier: lastInkToolItemIdentifier,
                    matching: { $0.tool is PKInkingTool }
                ) {
                    toolPicker?.selectedToolItem = inkItem
                    canvasView.tool = inkItem.tool ?? lastInkTool
                } else {
                    canvasView.tool = lastInkTool
                }
                showToolPicker(on: canvasView)
            } else {
                switchToEraser()
            }
        }

        private func preferredToolPickerItem(
            identifier: String?,
            matching predicate: (PKToolPickerItem) -> Bool
        ) -> PKToolPickerItem? {
            guard let toolPicker else {
                return nil
            }

            if let identifier,
               let rememberedItem = toolPicker.toolItems.first(where: { $0.identifier == identifier && predicate($0) })
            {
                return rememberedItem
            }

            return toolPicker.toolItems.first(where: predicate)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            PencilCanvasGesturePolicy.shouldRecognizeSimultaneously(
                gestureRecognizer,
                with: otherGestureRecognizer,
                fillEraseGesture: fillEraseGesture,
                drawingGestureRecognizer: drawingGestureRecognizer,
                panGestureRecognizer: containerView?.canvasView.panGestureRecognizer,
                pinchGestureRecognizer: containerView?.canvasView.pinchGestureRecognizer
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive _: UITouch
        ) -> Bool {
            guard gestureRecognizer === fillEraseGesture else {
                return true
            }

            return PencilCanvasGesturePolicy.shouldReceiveFillEraseTouch(
                fillMode: parent.fillMode,
                isEraserToolActive: canvasView?.tool is PKEraserTool
            )
        }

        private func activeFillColor() -> UIColor? {
            if let canvasView,
               let inkingTool = canvasView.tool as? PKInkingTool {
                return inkingTool.color.stableResolvedColor(using: colorResolutionTraitCollection(for: canvasView))
            }

            if let inkingTool = lastInkTool as? PKInkingTool,
               let canvasView {
                return inkingTool.color.stableResolvedColor(using: colorResolutionTraitCollection(for: canvasView))
            }

            if let inkingTool = lastInkTool as? PKInkingTool {
                return inkingTool.color
            }

            return nil
        }
    }
}

private extension UIResponder {
    private static weak var trackedFirstResponder: UIResponder?

    static var currentFirstResponder: UIResponder? {
        trackedFirstResponder = nil
        UIApplication.shared.sendAction(#selector(trackFirstResponder), to: nil, from: nil, for: nil)
        return trackedFirstResponder
    }

    @objc func trackFirstResponder() {
        UIResponder.trackedFirstResponder = self
    }
}

final class ZoomableCanvasContainerView: UIView {
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
        canvasView.frame = bounds

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

    func updateCanvasViewport() {
        updateContentInsetForCentering()
        updateArtworkViewport()
    }

    func updateArtworkViewport() {
        let scale = canvasView.zoomScale
        let scaledSize = CGSize(
            width: contentView.bounds.width * scale,
            height: contentView.bounds.height * scale
        )
        let visibleOrigin = CGPoint(
            x: -canvasView.contentOffset.x,
            y: -canvasView.contentOffset.y
        )
        let artworkCenter = CGPoint(
            x: visibleOrigin.x + (scaledSize.width / 2),
            y: visibleOrigin.y + (scaledSize.height / 2)
        )
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

        contentView.transform = scaleTransform
        contentView.center = artworkCenter
        aboveLayerImageView.transform = scaleTransform
        aboveLayerImageView.center = artworkCenter
    }

    func normalizedArtworkPoint(fromContainerLocation location: CGPoint) -> CGPoint? {
        let contentSize = contentView.bounds.size
        guard contentSize.width > 0, contentSize.height > 0 else {
            return nil
        }

        let artworkLocation = contentView.convert(location, from: self)
        let normalizedX = min(max(artworkLocation.x / contentSize.width, 0), 1)
        let normalizedY = min(max(artworkLocation.y / contentSize.height, 0), 1)
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    private func updateContentInsetForCentering() {
        let scaledContentWidth = contentView.bounds.width * canvasView.zoomScale
        let scaledContentHeight = contentView.bounds.height * canvasView.zoomScale
        let horizontalInset = max((canvasView.bounds.width - scaledContentWidth) / 2, 0)
        let verticalInset = max((canvasView.bounds.height - scaledContentHeight) / 2, 0)
        let verticalCompensation = externalVerticalCenteringCompensation()

        let topInset = max(verticalInset - verticalCompensation, 0)
        let bottomInset = max(verticalInset + verticalCompensation, 0)

        let nextInsets = UIEdgeInsets(
            top: topInset,
            left: horizontalInset,
            bottom: bottomInset,
            right: horizontalInset
        )
        if canvasView.contentInset != nextInsets {
            canvasView.contentInset = nextInsets
        }
    }

    private func externalVerticalCenteringCompensation() -> CGFloat {
        guard let window else {
            return 0
        }

        let frameInWindow = convert(bounds, to: window)
        let topGap = max(frameInWindow.minY, 0)
        let bottomGap = max(window.bounds.maxY - frameInWindow.maxY, 0)
        let baselineCompensation = (topGap - bottomGap) / 2
        let visualTopBias: CGFloat = 16
        return baselineCompensation + visualTopBias
    }

    private func setupSubviews() {
        backgroundColor = .clear
        // PencilKit clips its drawing to the canvas viewport. Keep the manually
        // transformed artwork layers inside that same viewport during zoom and pan.
        clipsToBounds = true

        contentView.backgroundColor = .white
        contentView.isUserInteractionEnabled = false
        addSubview(contentView)

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
        canvasView.isScrollEnabled = true
        canvasView.bouncesZoom = true
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.showsVerticalScrollIndicator = false
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.delaysContentTouches = false
        canvasView.panGestureRecognizer.minimumNumberOfTouches = 2
        canvasView.contentInset = .zero
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 8.0
        addSubview(canvasView)

        aboveLayerImageView.isOpaque = false
        aboveLayerImageView.backgroundColor = .clear
        aboveLayerImageView.contentMode = .scaleToFill
        aboveLayerImageView.clipsToBounds = true
        aboveLayerImageView.isUserInteractionEnabled = false
        addSubview(aboveLayerImageView)

        lockArtworkAppearanceToLight()
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
        let contentBounds = CGRect(origin: .zero, size: contentSize)
        contentView.transform = .identity
        contentView.bounds = contentBounds
        imageView.frame = contentView.bounds
        fillImageView.frame = contentView.bounds
        belowLayerImageView.frame = contentView.bounds
        aboveLayerImageView.transform = .identity
        aboveLayerImageView.bounds = contentBounds
        canvasView.contentSize = contentSize
        updateArtworkViewport()
    }

    private func updateZoomScaleLimits(maintainUserZoom: Bool) {
        guard contentView.bounds.width > 0,
              contentView.bounds.height > 0,
              canvasView.bounds.width > 0,
              canvasView.bounds.height > 0
        else {
            return
        }

        let fitScaleX = canvasView.bounds.width / contentView.bounds.width
        let fitScaleY = canvasView.bounds.height / contentView.bounds.height
        let fitScale = min(fitScaleX, fitScaleY)

        // Allow users to zoom out to 1.0 even on large iPads where "fit" would upscale.
        canvasView.minimumZoomScale = min(fitScale, 1.0)
        canvasView.maximumZoomScale = max(canvasView.minimumZoomScale * 8.0, 8.0)

        let isEffectivelyAtFit = abs(canvasView.zoomScale - lastFitZoomScale) < 0.02
        let shouldSnapToFit = !maintainUserZoom || isEffectivelyAtFit

        if shouldSnapToFit {
            canvasView.zoomScale = fitScale
        } else if canvasView.zoomScale < canvasView.minimumZoomScale {
            canvasView.zoomScale = canvasView.minimumZoomScale
        }

        lastFitZoomScale = fitScale
        updateContentInsetForCentering()

        if shouldSnapToFit {
            canvasView.contentOffset = CGPoint(
                x: -canvasView.contentInset.left,
                y: -canvasView.contentInset.top
            )
        }
        updateArtworkViewport()
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

private extension UIView {
    var subviewsRecursive: [UIView] {
        subviews + subviews.flatMap(\.subviewsRecursive)
    }
}
