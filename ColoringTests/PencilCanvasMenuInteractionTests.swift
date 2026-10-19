import PencilKit
import SwiftUI
import UIKit
import XCTest

@testable import Coloring

final class PencilCanvasMenuInteractionTests: XCTestCase {
    func testConnectingCanvasRemovesNestedEditMenuInteractions() async {
        await MainActor.run {
            let view = Self.makeCanvasView()
            let coordinator = view.makeCoordinator()
            let container = ZoomableCanvasContainerView()
            let nestedView = UIView()
            let menu = UIEditMenuInteraction(delegate: nil)
            container.canvasView.addSubview(nestedView)
            nestedView.addInteraction(menu)

            coordinator.connect(to: container.canvasView, containerView: container)
            defer { coordinator.disconnect(from: container.canvasView) }

            XCTAssertNil(menu.view)
        }
    }

    func testFillModeChangesSuppressMenusWithoutRepeatingCleanupForUnchangedMode() async {
        await MainActor.run {
            let view = Self.makeCanvasView()
            let coordinator = view.makeCoordinator()
            let container = ZoomableCanvasContainerView()
            coordinator.connect(to: container.canvasView, containerView: container)
            defer { coordinator.disconnect(from: container.canvasView) }
            coordinator.updateFillMode(false, in: container)
            let menu = UIEditMenuInteraction(delegate: nil)
            container.canvasView.addInteraction(menu)

            coordinator.updateFillMode(false, in: container)
            XCTAssertTrue(menu.view === container.canvasView)
            coordinator.updateFillMode(true, in: container)
            XCTAssertNil(menu.view)

            container.canvasView.addInteraction(menu)
            coordinator.updateFillMode(true, in: container)
            XCTAssertTrue(menu.view === container.canvasView)
            coordinator.updateFillMode(false, in: container)
            XCTAssertNil(menu.view)
        }
    }

    func testPencilEraserTransitionsSuppressMenusAndRestoreInk() async {
        await MainActor.run {
            let view = Self.makeCanvasView()
            let coordinator = view.makeCoordinator()
            let container = ZoomableCanvasContainerView()
            coordinator.connect(to: container.canvasView, containerView: container)
            defer { coordinator.disconnect(from: container.canvasView) }
            let ink = PKInkingTool(.marker, color: .blue.withAlphaComponent(0.5), width: 18)
            container.canvasView.tool = ink
            let menu = UIEditMenuInteraction(delegate: nil)
            container.canvasView.addInteraction(menu)

            coordinator.handlePencilTap(preferredAction: .switchEraser)

            XCTAssertTrue(container.canvasView.tool is PKEraserTool)
            XCTAssertNil(menu.view)
            container.canvasView.addInteraction(menu)

            coordinator.handlePencilTap(preferredAction: .switchEraser)

            let restoredInk = container.canvasView.tool as? PKInkingTool
            XCTAssertEqual(restoredInk?.inkType, ink.inkType)
            XCTAssertEqual(restoredInk?.color, ink.color)
            XCTAssertEqual(restoredInk?.width, ink.width)
            XCTAssertNil(menu.view)
        }
    }

    @MainActor
    private static func makeCanvasView() -> PencilCanvasView {
        PencilCanvasView(
            templateImage: UIImage(),
            templateID: "menu-interaction-test",
            drawing: .constant(PKDrawing())
        )
    }
}
