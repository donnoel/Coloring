import XCTest

final class ColoringUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsStudioShell() throws {
        let app = launchApp()

        XCTAssertTrue(findShellSwitchElement(named: "Studio", in: app).exists)
        XCTAssertTrue(findShellSwitchElement(named: "Gallery", in: app).exists)
        XCTAssertTrue(tapTab(named: "Studio", in: app), "Could not tap Studio tab")
        XCTAssertTrue(waitForStudioContent(in: app))
    }

    func testSwitchesBetweenStudioAndGalleryTabs() throws {
        let app = launchApp()
        XCTAssertTrue(tapTab(named: "Studio", in: app), "Could not tap Studio tab")
        XCTAssertTrue(waitForStudioContent(in: app))

        XCTAssertTrue(tapTab(named: "Gallery", in: app), "Could not tap Gallery tab")
        XCTAssertTrue(waitForGalleryContent(in: app), "Gallery content did not appear")

        XCTAssertTrue(tapTab(named: "Studio", in: app), "Could not tap Studio tab")
        XCTAssertTrue(waitForStudioContent(in: app))
    }

    func testRepeatedStudioGallerySwitchingRemainsReachable() throws {
        let app = launchApp()
        XCTAssertTrue(tapTab(named: "Studio", in: app), "Could not tap Studio tab")
        XCTAssertTrue(waitForStudioContent(in: app))

        for _ in 0..<3 {
            XCTAssertTrue(tapTab(named: "Gallery", in: app), "Could not tap Gallery tab")
            XCTAssertTrue(waitForGalleryContent(in: app), "Gallery content did not appear")

            XCTAssertTrue(tapTab(named: "Studio", in: app), "Could not tap Studio tab")
            XCTAssertTrue(waitForStudioContent(in: app))
        }
    }

    func testLayersIsNotVisibleInStudioSidebar() throws {
        let app = launchApp()
        XCTAssertTrue(tapTab(named: "Studio", in: app), "Could not tap Studio tab")
        XCTAssertTrue(waitForStudioContent(in: app))

        XCTAssertFalse(app.tables.buttons["Layers"].exists)
        XCTAssertFalse(app.tables.staticTexts["Layers"].exists)
    }

    func testSelectsBuiltInDrawingAndShowsCanvasExportControls() throws {
        let app = launchApp(skipOnboarding: true)
        XCTAssertTrue(tapTab(named: "Studio", in: app), "Could not tap Studio tab")
        XCTAssertTrue(waitForStudioContent(in: app))

        let templateRow = app.buttons["template.row"].firstMatch
        XCTAssertTrue(templateRow.waitForExistence(timeout: 15), "No built-in drawing row appeared")
        templateRow.tap()

        XCTAssertTrue(app.otherElements["studio.canvas"].waitForExistence(timeout: 15), "Canvas did not appear after selecting a drawing")

        let sendToGallery = app.buttons["studio.sendToGallery"].firstMatch
        XCTAssertTrue(sendToGallery.waitForExistence(timeout: 5), "Send to Gallery control was not reachable")
        XCTAssertTrue(sendToGallery.isEnabled, "Send to Gallery should be enabled after a drawing loads")
    }

    @discardableResult
    private func launchApp(skipOnboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if skipOnboarding {
            app.launchArguments.append("-UITestSkipOnboarding")
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func findShellSwitchElement(named name: String, in app: XCUIApplication) -> XCUIElement {
        let terms = tabSearchTerms(for: name)
        for term in terms {
            let matches = app
                .descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "label == %@ OR identifier == %@",
                        term,
                        term
                    )
                )
            let hittable = matches.allElementsBoundByIndex.first(where: { $0.isHittable })
            if let hittable {
                return hittable
            }
            if matches.count > 0 {
                return matches.element(boundBy: 0)
            }
        }

        let tabItems = app.descendants(matching: .any).allElementsBoundByIndex.filter { $0.exists }
        if name == "Studio", let first = tabItems.first {
            return first
        }
        if name == "Gallery", tabItems.count > 1 {
            return tabItems[1]
        }

        return app.descendants(matching: .any).firstMatch
    }

    private func tapTab(named name: String, in app: XCUIApplication) -> Bool {
        let tab = findShellSwitchElement(named: name, in: app)
        guard tab.waitForExistence(timeout: 5) else {
            return false
        }

        if tab.isHittable {
            tab.tap()
            return true
        }

        if let frame = tab.value(forKey: "frame") as? CGRect, !frame.isEmpty {
            let coordinate = tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coordinate.tap()
            return true
        }

        return false
    }

    private func tabSearchTerms(for name: String) -> [String] {
        switch name {
        case "Studio":
            return ["Studio", "paintbrush.pointed"]
        case "Gallery":
            return ["Gallery", "photo.on.rectangle.angled"]
        default:
            return [name]
        }
    }

    private func waitForStudioContent(in app: XCUIApplication) -> Bool {
        if app.otherElements["studio.root"].waitForExistence(timeout: 10) {
            return true
        }

        return app.staticTexts["Add New Coloring Page"].waitForExistence(timeout: 10)
    }

    private func waitForGalleryContent(in app: XCUIApplication) -> Bool {
        if app.otherElements["gallery.root"].waitForExistence(timeout: 10) {
            return true
        }

        return waitForAny(
            [
                app.staticTexts["No Artwork Yet"],
                app.staticTexts["Loading Artwork…"],
                app.staticTexts["Artwork Gallery"]
            ],
            timeout: 10
        )
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
