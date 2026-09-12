import XCTest

extension FissionDesktopUITests {
    @MainActor
    func testNewTabReusesLowestAvailableDefaultName() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        try createThread(in: context)
        XCTAssertTrue(app.buttons["Tab 1"].waitForExistence(timeout: 10))

        app.buttons["New Terminal"].click()
        app.buttons["New Terminal"].click()
        XCTAssertTrue(app.buttons["Tab 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Tab 3"].waitForExistence(timeout: 5))

        app.buttons["Tab 1"].rightClick()
        let closeItem = app.menuItems["Close"]
        XCTAssertTrue(closeItem.waitForExistence(timeout: 5))
        closeItem.click()
        XCTAssertTrue(app.buttons["Tab 1"].waitForNonExistence(timeout: 5))

        app.buttons["New Terminal"].click()
        XCTAssertTrue(
            app.buttons["Tab 1"].waitForExistence(timeout: 5),
            "A new tab should take the first unused default name."
        )
        XCTAssertTrue(app.buttons["Tab 2"].exists)
        XCTAssertTrue(app.buttons["Tab 3"].exists)
    }

    @MainActor
    func testTabsCanBeReorderedByDragging() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        try createThread(in: context)
        XCTAssertTrue(app.buttons["Tab 1"].waitForExistence(timeout: 10))
        app.buttons["New Terminal"].click()
        XCTAssertTrue(app.buttons["Tab 2"].waitForExistence(timeout: 5))

        XCTAssertLessThan(
            app.buttons["Tab 1"].frame.minX,
            app.buttons["Tab 2"].frame.minX
        )

        app.buttons["Tab 2"].press(forDuration: 0.5, thenDragTo: app.buttons["Tab 1"])

        XCTAssertTrue(
            waitUntil(timeout: 5) {
                app.buttons["Tab 2"].frame.minX < app.buttons["Tab 1"].frame.minX
            },
            "Tab 2 should move before Tab 1"
        )
    }

    @MainActor
    private func createThread(in context: TestContext) throws {
        let app = context.app
        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.buttons["new-thread-button"].click()
        let projectPath = app.textFields["project-path-field"]
        XCTAssertTrue(projectPath.waitForExistence(timeout: 5))
        projectPath.click()
        projectPath.typeText(context.projectDirectory.path)
        let createButton = app.buttons["create-thread-button"]
        waitUntilEnabled(createButton)
        createButton.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["terminal-workspace"].waitForExistence(timeout: 10)
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
