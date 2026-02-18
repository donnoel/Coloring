import XCTest

final class ColoringUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }
}