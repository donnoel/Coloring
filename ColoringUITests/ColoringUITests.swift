import XCTest

final class ColoringUITests: XCTestCase {
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    func testDrawingSurvivesLandscapeToPortraitRotation() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        XCUIDevice.shared.orientation = .landscapeLeft
        drawStroke(in: app)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        XCUIDevice.shared.orientation = .portrait
        drawStroke(in: app)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private func drawStroke(in app: XCUIApplication) {
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
