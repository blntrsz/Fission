# Driving Fission's macOS UI without granting `osascript` Accessibility access

## Decision

**Adopt a dedicated XCTest UI-testing target as the primary desktop verification driver.** Run it with `xcodebuild` and collect an `.xcresult` bundle. This removes `System Events`, `osascript`, AX-tree dumping, coordinate calculation, and `screencapture` from the normal path. It does **not** make macOS UI automation permission-free: macOS UI testing is Accessibility-backed, and the Xcode/XCTest helper identity may need a one-time Accessibility grant. The important practical distinction is that **Terminal/the agent shell no longer needs Accessibility access**.

If the machine policy forbids granting Accessibility to *any* automation helper, add a **DEBUG-only, launch-gated app-internal semantic control channel** as the fallback. It can drive the same application actions as the UI (rather than writing SQLite/defaults), but it is not a substitute for testing hit targets, focus, keyboard routing, or the accessibility hierarchy. Use it for deterministic setup, hard-to-reach Ghostty terminal operations, and state observation; keep at least a small XCUITest smoke suite wherever XCTest UI automation is permitted.

Do not replace System Events with direct AX calls, CGEvent posting, another event-injection wrapper, or Appium merely to evade the denial. Those approaches either need the same class of consent or add layers without removing it.

## What the current project implies

- `Apps/Desktop/FissionDesktop.xcodeproj` currently has an application target and a hosted **unit-test** target only; there is no UI-testing bundle. The shared `FissionDesktop` scheme includes `FissionDesktopTests`, not UI tests.
- Debug builds produce `FissionDev.app` with bundle ID `com.fission.desktop.dev`; the deployment target is macOS 14.
- `.agents/skills/verify-fission/scripts/launch-desktop.sh` already provides valuable isolation by setting `HOME` and `CFFIXED_USER_HOME` to `/tmp/fission-verification-$UID/home`, but readiness is currently determined through System Events.
- `ax-dump.sh` and window-bound discovery in `screenshot-desktop.sh` are both System Events dependent. The latter then invokes `screencapture`, which introduces a second privacy boundary.
- The SwiftUI surface has useful labels, but very few stable `.accessibilityIdentifier(...)` values. Labels such as “Close” and “Show settled threads” are user-facing and can change; identifiers are specifically intended as stable UI-test hooks ([Apple: `accessibilityIdentifier(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier(_:))).
- Existing desktop logic tests already use Swift Testing (`@Test`, `#expect`). That is compatible with retaining XCTest specifically for UI automation.

## Options compared

| Option | Can shell run it via `xcodebuild` without shell Accessibility? | Privacy grants in practice | Observation/artifacts | Setup for Fission | Verdict |
|---|---|---|---|---|---|
| **XCTest/XCUITest UI-testing bundle** | **Yes.** The shell launches `xcodebuild`; Xcode's test infrastructure owns UI automation. | Xcode/XCTest's helper may need **Accessibility**. No Input Monitoring is needed for normal actions. Apple does not document a separate Terminal Screen Recording grant for `XCUIScreenshot`; validate this on the target host rather than promising it is universally grant-free. | Accessibility queries/assertions, automatic failure snapshots, explicit element/window/screen screenshots, attachments, `.xcresult`. | Medium: add one target and scheme entry, identifiers, test helpers, and result handling. | **Recommended primary path.** |
| **App-internal DEBUG semantic control channel** | **Yes**, and it can work with no Accessibility grant at all. | None if it uses a private loopback/Unix socket or inherited file descriptors and captures no other process. | Structured state/events/logs. Pair with XCTest screenshots where allowed; an app-owned view snapshot can be supplementary but may miss Metal/Ghostty content. | Medium/high: design commands, security gate, lifecycle, acknowledgements, and test adapters. | **Recommended fallback/complement**, not sole end-to-end UI proof. |
| **AppleScript + System Events** | No under the present denial. | Caller needs **Accessibility** for GUI scripting; Apple Events may separately trigger **Automation** consent. Screen capture is separate. | AX hierarchy plus actions; external screenshot only with screen-capture access. | Already present, but brittle and blocked. | Retire from default path. |
| **Direct AXUIElement API** | No practical improvement. | The calling executable needs **Accessibility** trust (`AXIsProcessTrustedWithOptions`). | Rich semantic tree and AX actions; no screenshot. | Medium; would replace AppleScript syntax with Swift/Obj-C but preserve the same TCC blocker. | Not an escape hatch. |
| **CGEvent/Quartz synthesis** | No practical improvement. | Posting has an explicit event-synthesis authorization check; listening has a separate event-listening check. In System Settings these map to sensitive control/monitoring permissions. Capturing pixels separately needs screen-capture consent. | Input only. No semantic tree; needs AX or image recognition to observe. | Medium and coordinate/focus fragile. | Reject as the main harness. |
| **Appium Mac2** | Yes, but only by delegating to an Appium server/XCTest stack. | Official Mac2 docs require **Accessibility for Xcode Helper**. Appium's ffmpeg recording additionally requires **Screen & System Audio Recording** for the Appium process; some native-video retrieval requires Full Disk Access. | WebDriver element source, screenshots, recordings, client ecosystem. | High: Node/Appium/driver/client/version lifecycle, while Fission already has Xcode tests. | No benefit for this repo unless remote WebDriver is a separate requirement. |
| **Swift Testing** | Yes for code tests, but it is not the UI driver. | None for ordinary in-process tests. Any external UI mechanism it calls retains that mechanism's permissions. | Swift Testing attachments and normal test results; no replacement for `XCUIApplication`/`XCUIElement`. | Already used. | Keep for logic/integration tests; use XCTest alongside it for UI. |
| **External screen/image automation** | Usually not without grants. | Screen recognition needs **Screen & System Audio Recording**; clicks normally need Accessibility/event-synthesis access. | Pixel screenshots/video, weak semantics. | High and visually brittle. | Poor fit and no permission advantage. |

## Why XCUITest is the best near-term migration

Apple describes UI tests as running in a **separate process**, interacting at the app's surface without access to internal methods, and synthesizing events the app responds to. The framework is built on XCTest plus Accessibility, uses `XCUIApplication`, `XCUIElement`, and `XCUIElementQuery`, and supports continuous integration through `xcodebuild` ([Apple, *User Interface Testing*](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html)). This preserves the current skill's desired user boundary much better than model-only tests or database seeding.

A UI test can set `XCUIApplication.launchArguments` and `launchEnvironment` before `launch()` ([Apple: `launchEnvironment`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launchenvironment)). Therefore the current disposable `HOME`/`CFFIXED_USER_HOME` convention can move into a UI-test launch helper rather than relying on direct shell execution. `ProcessInfo.processInfo.environment` exposes inherited launch environment inside the app ([Apple: `ProcessInfo.environment`](https://developer.apple.com/documentation/foundation/processinfo/environment)).

Apple supports command-line `xcodebuild test`, `build-for-testing`, and `test-without-building`, including macOS destinations and test selection ([Apple TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)). The shell does not itself call AX or post events. However, XCTest's macOS automation remains Accessibility-backed. The official Appium Mac2 project, which is implemented on Apple's XCTest framework, explicitly requires Accessibility for the bundled Xcode Helper ([Appium Mac2, *Getting Started — Device Preparation*](https://appium.github.io/appium-mac2-driver/latest/getting-started/)). Thus the defensible expectation is:

- **No Accessibility grant to Terminal/pi/`osascript` is required.**
- **A one-time grant to the Xcode/XCTest helper may still be required.**
- An active, logged-in GUI session is still required; XCUITest is not headless macOS automation.

### Artifacts

Use `XCUIElement.screenshot()`, `XCUIApplication`/window screenshots, or `XCUIScreen.main.screenshot()`, wrap them in `XCTAttachment`, and set `attachment.lifetime = .keepAlways` for proof from successful tests ([Apple: `XCUIScreenshot`](https://developer.apple.com/documentation/xcuiautomation/xcuiscreenshot), [Apple: adding attachments](https://developer.apple.com/documentation/xctest/adding-attachments-to-tests-activities-and-issues)). Xcode also records UI-test diagnostics and failure snapshots. Write a deterministic result bundle with `xcodebuild -resultBundlePath ...`; inspect it in Xcode or export attachments with `xcresulttool` ([Apple, WWDC23: *Meet the test report with video replay*](https://developer.apple.com/videos/play/wwdc2023/10175/)).

This should replace `screenshot-desktop.sh` in the normal proof path. Apple's privacy settings treat screen recording as a separate capability ([Apple Support: Screen & System Audio Recording](https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac)). Apple documents XCTest screenshots but does not state on those API pages that Terminal must receive Screen Recording permission. Treat built-in XCTest screenshots as the intended path and add an installation preflight; retain `screencapture` only as an explicitly permission-dependent fallback.

## Permission details and dead ends

### Accessibility and direct AX

Apple says third-party software that controls the Mac through accessibility features must be explicitly authorized in Privacy & Security ([Apple Support: Allow accessibility apps](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)). `AXIsProcessTrustedWithOptions` checks/request-prompts for trust, and `AXUIElementCreateApplication(pid)` creates the target application's AX object ([Apple: `AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions), [Apple: `AXUIElementCreateApplication`](https://developer.apple.com/documentation/applicationservices/1459374-axuielementcreateapplication)). Reimplementing `ax-dump.sh` in Swift would improve typing and errors, but the new executable—not `osascript`—would still need trust. It does not solve the policy problem.

### AppleScript/System Events

Apple's own UI-scripting guide says an app without permission to use Accessibility produces an error, and shows that System Events exposes processes, windows, buttons, fields, and other controls through the accessibility hierarchy ([Apple, *Automating the User Interface*](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AutomatetheUserInterface.html)). Separately, macOS's **Automation** privacy pane governs one app controlling another ([Apple Support: Allow apps to automate and control other apps](https://support.apple.com/guide/mac-help/allow-apps-to-automate-and-control-other-apps-mchl108e1718/mac)). Therefore switching AppleScript syntax, nesting, or target PID cannot bypass the Accessibility denial. Exposing a scriptable Fission Apple Event API could avoid GUI scripting, but would retain Automation consent and offers less convenient structured bidirectional testing than a launch-gated local test channel.

### CGEvent, Input Monitoring, and capture

Core Graphics exposes separate checks for event **listening** and event **synthesis**: `CGPreflightListenEventAccess`/`CGRequestListenEventAccess` and `CGPreflightPostEventAccess`/`CGRequestPostEventAccess` ([Apple: `CGPreflightListenEventAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()), [Apple: `CGPreflightPostEventAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess())). Apple describes Input Monitoring as permission to monitor keyboard, mouse, or trackpad while other apps are in use ([Apple Support: Input Monitoring](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)). Practical consequences:

- Merely synthesizing clicks/keystrokes does not make Input Monitoring useful or necessary, but posting still has its own protected event-synthesis access. It is not a no-consent substitute for System Events.
- Adding an event tap to observe global input introduces the separate listening/Input Monitoring boundary.
- CGEvent has no element semantics; robust targeting still needs AX, while coordinate targeting is fragile.
- Pixel capture is separate. `CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess` exist specifically for screen-capture authorization ([Apple: `CGPreflightScreenCaptureAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())).

### Swift Testing

Swift Testing is appropriate for Fission's existing model, persistence, and command-layer tests. Apple says it works side-by-side with XCTest, allowing incremental use of both frameworks ([Apple: Swift Testing](https://developer.apple.com/xcode/swift-testing/)). Its official migration guide likewise permits XCTest and Testing in the same source/test system and documents interoperability ([swiftlang/swift-testing: *Migrating from XCTest*](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/MigratingFromXCTest.md)). The external UI automation classes are still XCUIAutomation/XCTest APIs, so changing assertion syntax to `#expect` does not provide app launch, element query, or event synthesis. Use `XCTestCase` for the UI bundle and Swift Testing for code-level tests.

### Appium Mac2 and other wrappers

The official Appium Mac2 repository states that it automates macOS applications using Apple's XCTest framework ([Appium Mac2 repository](https://github.com/appium/appium-mac2-driver)). Its setup requires Xcode Helper Accessibility. Its recording documentation says ffmpeg recording requires Screen & System Audio Recording for the Appium process, and native-recording retrieval can require Full Disk Access ([Appium Mac2 execute methods](https://appium.github.io/appium-mac2-driver/latest/reference/execute-methods/)). Appium is useful when a project needs a WebDriver protocol, cross-language clients, or a long-lived remote automation server. Fission needs none of those today; direct XCUITest is shallower, version-aligned with Xcode, and naturally produces Xcode artifacts.

Tools that simply wrap AX, CGEvent, AppleScript, or screen recognition inherit those APIs' permissions. A library cannot legitimately remove TCC requirements imposed on the underlying operation. No such wrapper is recommended for the verification skill.

## App-internal semantic control channel

If Xcode Helper cannot be authorized, the only robust autonomous route is to avoid controlling another process through protected OS-wide input/AX APIs.

A suitable design would be:

1. Compile the server only under `DEBUG` (or a dedicated `UI_TESTING` build condition).
2. Require an explicit launch environment value such as `FISSION_TEST_CONTROL_SOCKET=/tmp/.../control.sock` and a per-run random token. Do not bind a public TCP interface, advertise Bonjour, or enable it in Release.
3. Accept typed, high-level commands: `newThread(project:createWorktree:)`, `selectThread`, `renameThread`, `settle`, `reopen`, `addTerminalTab`, `selectTerminalTab`, and—only if it passes through the same terminal input adapter—`sendTerminalText`.
4. Route every command through the same closures/coordinators/application services used by SwiftUI. **Never** update SQLite, `UserDefaults`, or observable model properties solely to manufacture a visual state.
5. Return command acknowledgements only after the resulting main-actor transition, and publish structured observations (selected thread, sheet presentation, thread summaries, active tab, errors). Include app logs and an optional app-owned view/window snapshot where technically accurate.
6. Make tests assert both semantic state and a user-visible/accessibility result whenever XCUITest is available.

This preserves *application semantics* and process boundaries, but not *physical user interaction semantics*. It cannot prove that a button is hittable, keyboard focus works, an AX label is present, or a Ghostty surface receives synthesized keys. Accordingly:

- Use the channel for isolated launch readiness and deterministic setup even in XCUITest runs.
- Use XCUITest to click/type and inspect normal SwiftUI controls.
- For a custom Ghostty/Metal terminal surface that XCUITest cannot reliably type into or screenshot, use the channel to exercise the same terminal-input path, then observe terminal/application state and retain a clearly stated verification limitation.

## Concrete migration for `.agents/skills/verify-fission`

### Phase 1 — prove the XCTest route without app changes beyond testability hooks

1. In `Apps/Desktop/FissionDesktop.xcodeproj`, add `FissionDesktopUITests` as a **UI Testing Bundle** targeting `FissionDesktop`; keep `FissionDesktopTests` as the existing hosted unit bundle.
2. Add the UI target to the shared `FissionDesktop` scheme's Build and Test actions.
3. Create a base `XCTestCase` that:
   - creates `/tmp/fission-verification-$UID/<test-id>/home`;
   - sets `app.launchEnvironment["HOME"]` and `app.launchEnvironment["CFFIXED_USER_HOME"]` before `app.launch()`;
   - waits for a stable root element rather than polling System Events;
   - calls `app.terminate()` in teardown;
   - captures and retains a named screenshot attachment on the asserted state and on failure.
4. Add stable accessibility identifiers to major controls and states: root window/content, New Thread toolbar button, new-thread sheet, project-path field, worktree toggle, create/cancel buttons, thread list/rows, rename field, settled section, workspace, and terminal tabs. Continue providing meaningful labels for users; identifiers are non-localized automation keys.
5. Start with one smoke flow matching the current harness: clean launch → assert “No Threads” → open New Thread → enter a temporary project path → create → assert selected thread/workspace. Add rename/settle/reopen and terminal-tab flows incrementally.
6. Run from the skill with a command shaped like:

   ```bash
   xcodebuild \
     -project Apps/Desktop/FissionDesktop.xcodeproj \
     -scheme FissionDesktop \
     -destination 'platform=macOS' \
     -derivedDataPath Apps/Desktop/.derivedData \
     -resultBundlePath "/tmp/fission-verification-$UID/FissionDesktopUITests.xcresult" \
     -only-testing:FissionDesktopUITests \
     test
   ```

7. Add a preflight message that distinguishes identities: if UI automation is denied, request Accessibility for **Xcode Helper/XCTest's helper**, not Terminal/pi. Do not claim that running `xcodebuild` itself eliminates all Accessibility consent.

### Phase 2 — replace harness responsibilities

- Replace `launch-desktop.sh`'s direct launch and System Events readiness loop with the UI test's `XCUIApplication.launch()` and an element existence wait.
- Replace `ax-dump.sh` with targeted XCUITest `debugDescription`/element-query diagnostics emitted as test attachments or logs. Avoid making full-tree dumps the normal locator strategy.
- Replace `screenshot-desktop.sh` with XCTest screenshot attachments and the `.xcresult` artifact path.
- Replace `stop-desktop.sh` for test-owned processes with `app.terminate()` plus teardown cleanup. Keep an emergency process cleanup script only for crashed test runners.
- Update the skill's completion evidence to name the test method/flow, assertions, `.xcresult`, retained screenshots, deterministic unit/build/lint commands, and any unavailable boundary.

### Phase 3 — add the semantic channel only where needed

Add the DEBUG-only control channel if either:

- organizational policy prevents authorizing Xcode Helper;
- autonomous setup through UI is too slow/flaky; or
- Ghostty's custom view cannot expose reliable XCUI actions/observations.

Use it as a transport into the app's command layer, not as a backdoor into persistence. Document each flow as **semantic integration proof** versus **physical UI proof** so the skill does not overclaim.

## Recommended acceptance check

Before committing to the migration, make a throwaway UI-testing target/test and answer these on the actual host:

1. Does `xcodebuild ... -only-testing:FissionDesktopUITests test` prompt for or require only Xcode Helper Accessibility, while Terminal remains disabled?
2. Can XCUI locate the SwiftUI toolbar and New Thread sheet after adding identifiers?
3. Does text entry work in ordinary SwiftUI fields and in the Ghostty terminal surface?
4. Are explicit screenshot attachments present in the `.xcresult` without granting Terminal Screen Recording?
5. Does forwarding `HOME` and `CFFIXED_USER_HOME` keep Fission's database/preferences under the disposable directory?

If 1, 2, 4, and 5 pass, migrate the default verification path to XCUITest. If 3 fails only for Ghostty, use the hybrid semantic channel for terminal input rather than falling back wholesale to System Events.
