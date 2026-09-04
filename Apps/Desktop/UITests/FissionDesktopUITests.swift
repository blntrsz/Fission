import XCTest

final class FissionDesktopUITests: XCTestCase {
    private struct TestContext {
        let app: XCUIApplication
        let root: URL
        let projectDirectory: URL
        let databaseURL: URL
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
        waitUntilEnabled(createButton)
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
    func testCreatingThreadScrollsSidebarToNewestThread() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.terminate()
        try seedThreads(count: 18, databaseURL: context.databaseURL)
        app.launch()

        let oldestThread = app.staticTexts["Seed 00"]
        XCTAssertTrue(oldestThread.waitForExistence(timeout: 10))
        let threadList = app.outlines.firstMatch
        XCTAssertTrue(threadList.exists)
        for _ in 0..<20 where !oldestThread.isHittable {
            threadList.swipeUp()
        }
        XCTAssertTrue(oldestThread.isHittable, "The test must start with the sidebar scrolled down.")
        XCTAssertFalse(app.staticTexts["Seed 17"].isHittable)

        app.buttons["new-thread-button"].click()
        let projectPath = app.textFields["project-path-field"]
        XCTAssertTrue(projectPath.waitForExistence(timeout: 5))
        projectPath.click()
        projectPath.typeText(context.projectDirectory.path)
        let createButton = app.buttons["create-thread-button"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        waitUntilEnabled(createButton)
        createButton.click()

        XCTAssertTrue(
            projectPath.waitForNonExistence(timeout: 10),
            "Creating a Thread should dismiss the New Thread sheet."
        )
        let newThread = app.staticTexts["SampleProject"]
        XCTAssertTrue(newThread.waitForExistence(timeout: 10))
        XCTAssertTrue(
            newThread.isHittable,
            "The newly created Thread should be visible at the top of the sidebar."
        )
    }

    @MainActor
    func testSettledAccordionLoadsTwentyThreadsAtATime() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.terminate()
        try seedThreads(count: 25, status: "settled", databaseURL: context.databaseURL)
        app.launch()

        XCTAssertTrue(app.staticTexts["Seed 24"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.staticTexts["Seed 04"].exists,
            "The twenty-first settled Thread should initially be hidden."
        )

        let loadMore = app.buttons["load-more-settled-threads"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 10))
        let threadList = app.outlines.firstMatch
        for _ in 0..<20 where !loadMore.isHittable {
            threadList.swipeUp()
        }
        XCTAssertTrue(loadMore.isHittable)
        loadMore.click()

        XCTAssertTrue(
            app.staticTexts["Seed 04"].waitForExistence(timeout: 10),
            "Loading more should reveal the remaining settled Threads."
        )

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Loaded More Settled Threads"
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

        let databaseURL = root.appending(path: "fission.sqlite")
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-createThreadsInNewWorktree", "NO",
            "-FissionDatabasePath", databaseURL.path
        ]
        app.launchEnvironment["HOME"] = root.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = root.path
        app.launchEnvironment["PI_CODING_AGENT_DIR"] = root
            .appending(path: ".pi/agent", directoryHint: .isDirectory)
            .path
        app.launchEnvironment["FISSION_EXECUTION_EPHEMERAL"] = "1"
        app.launch()

        return TestContext(
            app: app,
            root: root,
            projectDirectory: projectDirectory,
            databaseURL: databaseURL
        )
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    private func seedThreads(
        count: Int,
        status: String = "active",
        databaseURL: URL
    ) throws {
        let values = (0..<count).map { index in
            let id = String(format: "00000000-0000-0000-0000-%012d", index)
            return "('\(id)', 'Seed \(String(format: "%02d", index))', '\(status)', NULL, \(index), \(index))"
        }.joined(separator: ",")

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            databaseURL.path,
            "INSERT INTO threads (id, title, status, working_directory, created_at, updated_at) VALUES \(values);"
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(bytes: data, encoding: .utf8) ?? "Unknown sqlite3 error"
        )
    }
}
