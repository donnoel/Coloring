import PencilKit
import SwiftUI
import UIKit

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var onDrawingChanged: ((PKDrawing) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.isOpaque = false
        canvasView.backgroundColor = .clear
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.drawingPolicy = UIPencilInteraction.prefersPencilOnlyDrawing ? .pencilOnly : .anyInput
        canvasView.contentInset = .zero
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        context.coordinator.connect(to: canvasView)
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            context.coordinator.applyExternalDrawing(drawing, to: uiView)
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.disconnect(from: uiView)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        private let parent: PencilCanvasView
        private weak var canvasView: PKCanvasView?
        private var toolPicker: PKToolPicker?
        private var pencilInteraction: UIPencilInteraction?
        private var lastInkTool: PKTool = PKInkingTool(.marker, color: .black, width: 12)
        private var isApplyingExternalDrawing = false
        private let isRunningTests = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func connect(to canvasView: PKCanvasView) {
            self.canvasView = canvasView
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
        }

        func applyExternalDrawing(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
            isApplyingExternalDrawing = true
            canvasView.drawing = drawing
            isApplyingExternalDrawing = false
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else {
                return
            }

            parent.drawing = canvasView.drawing
            parent.onDrawingChanged?(canvasView.drawing)
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
