import XCTest

extension FissionDesktopUITests {
    @MainActor
    func testNewThreadSheetCanSwitchToRemoteMachines() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.buttons["new-thread-button"].click()

        let locationPicker = app.segmentedControls["new-thread-location-picker"]
        XCTAssertTrue(locationPicker.waitForExistence(timeout: 5))
        let remoteSegment = app.descendants(matching: .any)["new-thread-location-remote"]
        if remoteSegment.waitForExistence(timeout: 2) {
            remoteSegment.click()
        } else {
            app.radioButtons["Remote"].click()
        }

        XCTAssertTrue(app.staticTexts["No Remote Machines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-remote-machine-settings"].exists)
        XCTAssertTrue(app.textFields["remote-project-path-field"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["create-thread-button"].isEnabled)
    }

    @MainActor
    func testUserCanCreateRemoteThreadFromRegisteredMachine() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp(withRemoteMachine: true)
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.buttons["new-thread-button"].click()

        XCTAssertTrue(app.segmentedControls["new-thread-location-picker"].waitForExistence(timeout: 5))
        let remoteSegment = app.descendants(matching: .any)["new-thread-location-remote"]
        if remoteSegment.waitForExistence(timeout: 2) {
            remoteSegment.click()
        } else {
            app.radioButtons["Remote"].click()
        }

        XCTAssertTrue(
            app.popUpButtons["remote-machine-picker"].waitForExistence(timeout: 5)
                || app.descendants(matching: .any)["remote-machine-picker"].waitForExistence(timeout: 5),
            "Registered machines should appear in the New Thread sheet."
        )

        let projectPath = app.textFields["remote-project-path-field"]
        XCTAssertTrue(projectPath.waitForExistence(timeout: 5))
        XCTAssertEqual(projectPath.value as? String, "/work/fission")

        let createButton = app.buttons["create-thread-button"]
        waitUntilEnabled(createButton)
        createButton.click()

        XCTAssertTrue(
            app.staticTexts["fission"].waitForExistence(timeout: 10),
            "The remote Thread should use the project path name."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["terminal-workspace"].waitForExistence(timeout: 10),
            "Creating a remote Thread should reveal its terminal workspace."
        )

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Created Remote Thread"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSettingsCanRegisterARemoteMachine() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp()
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["FissionDev"].click()
        let settingsItem = app.menuItems["Settings…"]
        if settingsItem.waitForExistence(timeout: 3) {
            settingsItem.click()
        } else {
            app.typeKey(",", modifierFlags: .command)
        }

        let settings = app.windows["FissionDev Settings"]
        let settingsWindow = settings.exists ? settings : app.dialogs.firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5) || app.tabs["Remote Machines"].waitForExistence(timeout: 5))

        let remoteTab = app.tabs["Remote Machines"]
        if remoteTab.waitForExistence(timeout: 5) {
            remoteTab.click()
        } else {
            app.buttons["Remote Machines"].click()
        }

        let addMachine = app.buttons["add-remote-machine-button"]
        XCTAssertTrue(addMachine.waitForExistence(timeout: 5))
        addMachine.click()

        let nameField = app.textFields["remote-machine-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText("Studio")

        let hostField = app.textFields["remote-machine-host-field"]
        hostField.click()
        hostField.typeText("gpu.example")

        let pathField = app.textFields["remote-machine-project-path-field"]
        XCTAssertTrue(pathField.waitForExistence(timeout: 5))
        pathField.click()
        pathField.typeText("/work/fission")

        app.buttons["save-remote-machine-button"].click()
        XCTAssertTrue(app.staticTexts["Studio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["gpu.example"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["/work/fission"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRemoteProjectPickerAutocompletesDirectories() throws {
        continueAfterFailure = false

        let context = try launchIsolatedApp(withRemoteMachine: true)
        let app = context.app
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: context.root)
        }

        XCTAssertTrue(app.staticTexts["Explore Fission"].waitForExistence(timeout: 10))
        app.buttons["new-thread-button"].click()

        let remoteSegment = app.descendants(matching: .any)["new-thread-location-remote"]
        if remoteSegment.waitForExistence(timeout: 2) {
            remoteSegment.click()
        } else {
            app.radioButtons["Remote"].click()
        }

        let projectPath = app.textFields["remote-project-path-field"]
        XCTAssertTrue(projectPath.waitForExistence(timeout: 5))
        XCTAssertEqual(projectPath.value as? String, "/work/fission")
        XCTAssertTrue(
            app.descendants(matching: .any)["new-thread-project-fission"].waitForExistence(timeout: 5),
            "The remote picker should list the matching project directory."
        )

        if app.buttons["Clear"].waitForExistence(timeout: 2) {
            app.buttons["Clear"].click()
        }
        projectPath.click()
        projectPath.typeText("/work/")

        XCTAssertTrue(app.descendants(matching: .any)["new-thread-project-notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["new-thread-project-fission"].exists)

        app.descendants(matching: .any)["new-thread-project-notes"].firstMatch.doubleClick()
        XCTAssertEqual(projectPath.value as? String, "/work/notes/")
    }
}
