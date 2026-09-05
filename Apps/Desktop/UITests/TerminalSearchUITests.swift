import XCTest

extension FissionDesktopUITests {
    @MainActor
    func testTerminalScrollbackSearchIsScopedToEachTab() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp(withSearchFixture: true)
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }
        let searchReadyMarker = try XCTUnwrap(context.fixtureFiles.searchReady)
        let focusRestoredMarker = try XCTUnwrap(context.fixtureFiles.focusRestored)

        try createThread(in: context)
        let terminal = app.scrollViews["terminal-workspace"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFile(at: searchReadyMarker, timeout: 10))
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 5)).click()
        terminal.typeKey("f", modifierFlags: .command)

        let searchField = app.textFields["terminal-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.typeText("FISSION_NEEDLE")
        let matchCount = app.staticTexts["terminal-search-count"]
        XCTAssertTrue(
            waitForElement(matchCount, labelEndingIn: "/3", timeout: 5),
            "Expected three renderer-local matches; got \(displayedText(of: matchCount))."
        )

        assertSearchNavigation(searchField: searchField, matchCount: matchCount)
        assertSearchIsScopedToTab(app: app, terminal: terminal, searchField: searchField)
        assertUseSelectionForFind(terminal: terminal, searchField: searchField)

        terminal.typeText("printf focused > \(focusRestoredMarker.path)")
        terminal.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(
            waitForFile(at: focusRestoredMarker, timeout: 5),
            "Escape should close search and restore terminal focus."
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
    }

    private func assertSearchNavigation(
        searchField: XCUIElement,
        matchCount: XCUIElement
    ) {
        searchField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(
            waitForElement(
                matchCount,
                labelEndingIn: "/3",
                labelDifferentFrom: "-/3",
                timeout: 5
            )
        )
        let initialMatch = displayedText(of: matchCount)
        searchField.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(waitForElement(matchCount, labelDifferentFrom: initialMatch, timeout: 5))
        searchField.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForElement(matchCount, labelEqualTo: initialMatch, timeout: 5))

        searchField.typeKey(XCUIKeyboardKey.return, modifierFlags: .shift)
        XCTAssertTrue(waitForElement(matchCount, labelDifferentFrom: initialMatch, timeout: 5))
        searchField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        XCTAssertTrue(waitForElement(matchCount, labelEqualTo: initialMatch, timeout: 5))
    }

    private func assertUseSelectionForFind(
        terminal: XCUIElement,
        searchField: XCUIElement
    ) {
        searchField.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 5))
        terminal.typeKey("a", modifierFlags: .command)
        terminal.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertFalse((searchField.value as? String ?? "").isEmpty)
        searchField.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 5))
    }

    private func assertSearchIsScopedToTab(
        app: XCUIApplication,
        terminal: XCUIElement,
        searchField: XCUIElement
    ) {
        app.buttons["New Terminal"].click()
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 5))
        terminal.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertEqual(searchField.value as? String, "", "Search query must not leak into a new tab.")

        app.buttons["Tab 1"].click()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertEqual(searchField.value as? String, "FISSION_NEEDLE")
    }
}
