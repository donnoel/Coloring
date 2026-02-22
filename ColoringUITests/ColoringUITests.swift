import XCTest

final class ColoringUITests: XCTestCase {
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }
}
