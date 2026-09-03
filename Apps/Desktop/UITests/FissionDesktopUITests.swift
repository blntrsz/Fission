import XCTest

final class FissionDesktopUITests: XCTestCase {
    private struct TestContext {
        let app: XCUIApplication
        let root: URL
        let projectDirectory: URL
    }

    @MainActor
    func testUserCanCreateThreadFromFreshState() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(
            app.staticTexts["Explore Fission"].waitForExistence(timeout: 10),
            "A fresh database should contain the starter Thread."
        )

        app.buttons["new-thread-button"].click()

        let projectPath = app.textFields["project-path-field"]
        XCTAssertTrue(projectPath.waitForExistence(timeout: 5))
        projectPath.click()
        projectPath.typeText(context.projectDirectory.path)

        let createButton = app.buttons["create-thread-button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        XCTAssertTrue(createButton.isEnabled)
        createButton.click()

        XCTAssertTrue(
            projectPath.waitForNonExistence(timeout: 10),
            "Creating a Thread should dismiss the New Thread sheet."
        )
        XCTAssertTrue(
            app.staticTexts["SampleProject"].waitForExistence(timeout: 10),
            "The created Thread should select the requested project."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["terminal-workspace"].waitForExistence(timeout: 10),
            "Creating a Thread should reveal its terminal workspace."
        )

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Created Thread Workspace"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func launchIsolatedApp() throws -> TestContext {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "fission-ui-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let projectDirectory = root
            .appending(path: "SampleProject", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )

        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-createThreadsInNewWorktree", "NO",
            "-FissionDatabasePath", root.appending(path: "fission.sqlite").path
        ]
        app.launchEnvironment["HOME"] = root.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = root.path
        app.launchEnvironment["PI_CODING_AGENT_DIR"] = root
            .appending(path: ".pi/agent", directoryHint: .isDirectory)
            .path
        app.launch()

        return TestContext(app: app, root: root, projectDirectory: projectDirectory)
    }
}
