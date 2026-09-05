// swiftlint:disable file_length

import XCTest

final class FissionDesktopUITests: XCTestCase {
    struct TestContext {
        let app: XCUIApplication
        let root: URL
        let projectDirectory: URL
        let databaseURL: URL
        let fixtureFiles: FixtureFiles
    }

    struct FixtureFiles {
        let interruptReady: URL?
        let interruptReceived: URL?
        let searchReady: URL?
        let focusRestored: URL?
    }

    @MainActor
    func testCheckForUpdatesIsAvailableFromApplicationMenu() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["FissionDev"].click()
        let checkForUpdates = app.menuItems["Check for Updates…"]
        XCTAssertTrue(checkForUpdates.waitForExistence(timeout: 5))
        checkForUpdates.click()

        XCTAssertTrue(
            app.staticTexts["Updates are unavailable in this build"].waitForExistence(timeout: 5),
            "Development builds should explain why they cannot contact the production feed."
        )
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
    func testControlCClearsPendingTerminalInput() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        let clearedMarker = context.root.appending(path: "pending-input-cleared")
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.buttons["new-thread-button"].click()

        let projectPath = app.textFields["project-path-field"]
        XCTAssertTrue(projectPath.waitForExistence(timeout: 5))
        projectPath.click()
        projectPath.typeText(context.projectDirectory.path)
        let createButton = app.buttons["create-thread-button"]
        waitUntilEnabled(createButton)
        createButton.click()

        let terminal = app.scrollViews["terminal-workspace"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 10))
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 5)).click()
        terminal.typeText("asd")
        terminal.typeKey("c", modifierFlags: .control)
        terminal.typeText("printf cleared > \(clearedMarker.path)")
        terminal.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(
            waitForFile(at: clearedMarker, timeout: 5),
            "Control-C should clear pending input before the next command."
        )
    }

    @MainActor
    func testControlCInterruptsForegroundTerminalProcess() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp(withInterruptProbe: true)
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }
        let readyMarker = try XCTUnwrap(context.fixtureFiles.interruptReady)
        let interruptMarker = try XCTUnwrap(context.fixtureFiles.interruptReceived)

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.buttons["new-thread-button"].click()

        let projectPath = app.textFields["project-path-field"]
        XCTAssertTrue(projectPath.waitForExistence(timeout: 5))
        projectPath.click()
        projectPath.typeText(context.projectDirectory.path)
        let createButton = app.buttons["create-thread-button"]
        waitUntilEnabled(createButton)
        createButton.click()

        let terminal = app.scrollViews["terminal-workspace"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitForFile(at: readyMarker, timeout: 10),
            "The probe must be running before Control-C is sent."
        )
        // SwiftUI propagates the workspace identifier to its tab-bar scroll view.
        // Click below that bar, inside the native terminal surface, to acquire focus.
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 5)).click()
        terminal.typeKey("c", modifierFlags: .control)

        XCTAssertTrue(
            waitForFile(at: interruptMarker, timeout: 5),
            "Control-C should deliver SIGINT to the terminal's foreground process."
        )
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
}

extension FissionDesktopUITests {
    @MainActor
    func launchIsolatedApp(
        withInterruptProbe: Bool = false,
        withSearchFixture: Bool = false
    ) throws -> TestContext {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "fission-ui-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let projectDirectory = root
            .appending(path: "SampleProject", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )

        let fixtureFiles = try prepareShellProfile(
            root: root,
            projectDirectory: projectDirectory,
            withInterruptProbe: withInterruptProbe,
            withSearchFixture: withSearchFixture
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
        if withInterruptProbe || withSearchFixture {
            app.launchEnvironment["SHELL"] = "/bin/zsh"
            app.launchEnvironment["ZDOTDIR"] = root.path
        }
        app.launch()

        return TestContext(
            app: app,
            root: root,
            projectDirectory: projectDirectory,
            databaseURL: databaseURL,
            fixtureFiles: fixtureFiles
        )
    }

    private func prepareShellProfile(
        root: URL,
        projectDirectory: URL,
        withInterruptProbe: Bool,
        withSearchFixture: Bool
    ) throws -> FixtureFiles {
        let interruptReady = withInterruptProbe ? root.appending(path: "probe-ready") : nil
        let interruptReceived = withInterruptProbe ? root.appending(path: "interrupt-received") : nil
        let searchReady = withSearchFixture ? root.appending(path: "search-ready") : nil
        let focusRestored = withSearchFixture ? root.appending(path: "focus-restored") : nil
        let profile = root.appending(path: ".zprofile")

        if let interruptReady, let interruptReceived {
            try """
            trap 'printf interrupted > "\(interruptReceived.path)"' INT
            printf ready > "\(interruptReady.path)"
            while true; do sleep 1; done
            """.write(to: profile, atomically: true, encoding: .utf8)
        } else if let searchReady {
            try """
            if [[ "$PWD" == "\(projectDirectory.path)" ]]; then
              for index in {1..180}; do
                if (( index == 5 || index == 90 || index == 175 )); then
                  printf 'fixture %03d FISSION_NEEDLE\\n' "$index"
                else
                  printf 'fixture %03d ordinary output\\n' "$index"
                fi
              done
              printf ready > "\(searchReady.path)"
            fi
            """.write(to: profile, atomically: true, encoding: .utf8)
        }
        return FixtureFiles(
            interruptReady: interruptReady,
            interruptReceived: interruptReceived,
            searchReady: searchReady,
            focusRestored: focusRestored
        )
    }

    @MainActor
    func waitUntilEnabled(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    func waitForElement(
        _ element: XCUIElement,
        labelEndingIn suffix: String? = nil,
        labelDifferentFrom differentLabel: String? = nil,
        labelEqualTo equalLabel: String? = nil,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = displayedText(of: element)
            if element.exists,
               suffix.map(label.hasSuffix) ?? true,
               differentLabel.map({ label != $0 }) ?? true,
               equalLabel.map({ label == $0 }) ?? true {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    func displayedText(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    func waitForFile(at url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
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
