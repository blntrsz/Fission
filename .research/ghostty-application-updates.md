# Ghostty application updates and a Fission adoption plan

**Status:** implementation research and recommendation
**Current as of / sources accessed:** 2026-09-05
**Source snapshots:** Fission `8098b56`; vendored Ghostty reference `3c1ef5b32`
**Scope:** desktop application discovery, download, installation, relaunch, presentation, configuration, release engineering, and the interaction with Fission's persistent execution helper. Mobile OS-managed updates are out of scope.

## Executive summary

**Fission should adopt Sparkle 2 for direct-distribution macOS updates, but copy Ghostty's boundaries and release discipline rather than copying all of its custom UI immediately.** Ghostty delegates the security-sensitive mechanics—scheduled checks, appcast/version selection, download, signature verification, extraction, replacement, and relaunch—to Sparkle. Its own code is primarily (1) a small controller, (2) a custom `SPUUserDriver` that projects Sparkle callbacks into an explicit UI state machine, (3) a delegate that selects stable versus tip feeds, and (4) release automation that signs the DMG, updates an appcast, and publishes the payload before the appcast (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateController.swift`, `UpdateDriver`, `UpdateDelegate`; `.agents/references/ghostty/.github/workflows/release-tag.yml:339-401`; `.agents/references/ghostty/.github/workflows/publish-tag.yml:43-73`).

The recommended sequence for Fission is:

1. **Make distribution trustworthy first:** Developer ID-sign and notarize the app and its nested `FissionExecution` helper. Fission currently creates an ad-hoc-signed DMG and publishes only a SHA-256 sidecar; its own README says this is not ready for warning-free external distribution (`Apps/Desktop/README.md:64-76`; `scripts/package-desktop.sh:15-40`; `.github/workflows/release-desktop.yml:38-72`).
2. **Add Sparkle with standard UI and one channel:** pin Sparkle in `Apps/Desktop/FissionDesktop.xcodeproj/project.pbxproj`, add an update owner under `Apps/Desktop/Sources/Updates/`, expose “Check for Updates…” in `FissionDesktopApp.AppKeyboardCommands`, and use the existing monotonically increasing GitHub run number as Sparkle's internal version while replacing the hard-coded marketing version (`Apps/Desktop/FissionDesktop.xcodeproj/project.pbxproj:487-515`; `scripts/package-desktop.sh:10-22`).
3. **Publish safely:** generate an EdDSA-signed appcast, upload the immutable DMG first, verify it is reachable, then publish the appcast. Ghostty's tagged flow deliberately stages the appcast because changing the feed triggers clients (`.agents/references/ghostty/.github/workflows/release-tag.yml:339-401`; `.agents/references/ghostty/.github/workflows/publish-tag.yml:43-73`).
4. **Only then add Ghostty-like unobtrusive presentation:** an observable update state, toolbar/status pill, progress popover, settings, and a deterministic simulator. The custom driver is reusable in shape, but its terminal-window discovery and AppKit-specific quit handling are not.
5. **Resolve the execution-helper lifecycle before calling relaunch a complete upgrade.** Fission's detached `FissionExecution` survives the GUI, and its socket identity is keyed to protocol version rather than app build. A newly updated GUI can therefore reconnect to an old helper process indefinitely (`ARCHITECTURE.md`, “Desktop execution”; `Apps/Desktop/Sources/Terminal/TerminalExecutionProtocol.swift:115-130`; `Apps/Desktop/Sources/Terminal/TerminalExecutionClient.swift`, `TerminalDaemonLauncher.launch()`). This preserves terminals, but helper fixes do not take effect. Fission needs an explicit compatibility/deferred-restart policy before shipping updater-triggered relaunches.

## What Ghostty actually implements

### Responsibility split

| Layer | Ghostty responsibility | Sparkle responsibility |
|---|---|---|
| Configuration | Maps `off` / `check` / `download`, chooses stable or tip feed | Persists updater preferences and schedules checks |
| Discovery | Starts updater and invokes manual/background checks | Fetches/parses appcast and compares `sparkle:version` against bundle version |
| Presentation | Converts callbacks into `UpdateState`; titlebar/overlay pill, popover, command palette, no-window fallback | Supplies standard fallback dialogs |
| Transfer/install | Displays byte and extraction progress; forwards cancel/install choices | Downloads, validates, extracts, replaces app, installs on quit, relaunches |
| Publishing | Builds/signs/notarizes DMG, EdDSA-signs it, writes and uploads appcast | Supplies `sign_update` and consumes appcast/signature |

Ghostty pins Sparkle `2.9.6` as an exact Swift Package dependency and links its product into the macOS app (`.agents/references/ghostty/macos/Ghostty.xcodeproj/project.pbxproj:1098-1112`). It does not implement a downloader, archive extractor, privileged installer, app replacement algorithm, or launcher itself.

### Runtime architecture

#### 1. Composition and startup

`AppDelegate` owns one process-wide `UpdateController` and exposes its shared `UpdateViewModel` (`.agents/references/ghostty/macos/Sources/App/AppDelegate.swift:151-155`). During application launch it first applies configuration, then calls `updateController.startUpdater()` (`.agents/references/ghostty/macos/Sources/App/AppDelegate.swift:230-233`).

`UpdateController.init()` creates:

- one `UpdateViewModel`;
- one custom `UpdateDriver`, which conforms to both `SPUUserDriver` and (in an extension) `SPUUpdaterDelegate`;
- one `SPUUpdater` using the main bundle as both host and application bundle.

`startUpdater()` catches startup/configuration failures and turns them into retryable/dismissible `.error` state (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateController.swift`, `init()` and `startUpdater()`).

#### 2. Configuration, persistence, and scheduling

Ghostty's user configuration has two separate concepts:

- `auto-update`: `off`, `check`, or `download`; `null` means defer to Sparkle's persisted user-default behavior (`.agents/references/ghostty/src/config/Config.zig:3895-3919`, `AutoUpdate` at line 9833).
- `auto-update-channel`: `stable` or `tip`; if omitted, finalization derives it from the build's release channel (`.agents/references/ghostty/src/config/Config.zig:3921-3941`, `4873-4877`). The build channel itself is stable for a semantic version without prerelease data and tip otherwise (`.agents/references/ghostty/src/build/Config.zig:693-702`, `ReleaseChannel` at lines 850-858). A config test proves that finalization fills this default (`.agents/references/ghostty/macos/Tests/Ghostty/ConfigTests.swift:192-196`).

On each config change, `AppDelegate.ghosttyConfigDidChange(config:)` maps these values onto `SPUUpdater.automaticallyChecksForUpdates` and `.automaticallyDownloadsUpdates` (`.agents/references/ghostty/macos/Sources/App/AppDelegate.swift:779-798`). The checked-in plist explicitly sets `SUEnableAutomaticChecks=false`, keeping ordinary/dev builds inert; production workflows delete that key so user/config/Sparkle policy can apply, and replace the public EdDSA key (`.agents/references/ghostty/macos/Ghostty-Info.plist:107-110`; `.agents/references/ghostty/.github/workflows/release-tag.yml:191-203`).

Ghostty does not maintain a second updater database. Sparkle documents that runtime automatic-check/download settings are stored in the host application's defaults and warns against resetting them on every launch ([Sparkle customization](https://sparkle-project.org/documentation/customization/), “Updating the User's Preferences”). Ghostty's optional config is an intentional external override; when it is absent, Sparkle owns persistence and first-run permission.

#### 3. Feed and version/channel selection

`UpdateDriver.feedURLString(for:)` returns a completely separate HTTPS appcast URL for each channel rather than using Sparkle channel tags in one feed:

- tip: `https://tip.files.ghostty.org/appcast.xml`
- stable: `https://release.files.ghostty.org/appcast.xml`

(`.agents/references/ghostty/macos/Sources/Features/Update/UpdateDelegate.swift:4-16`). A channel change requires application restart because feed selection reads application configuration at updater operation time and the documented setting is restart-scoped (`.agents/references/ghostty/src/config/Config.zig:3921-3941`).

Both appcast generators use a monotonically increasing build number as `sparkle:version`, while user-facing `sparkle:shortVersionString` is either a semantic tag or a commit/date. Each item also carries publication date, minimum macOS version, description, download URL, and all signature/length attributes emitted by `sign_update` (`.agents/references/ghostty/dist/macos/update_appcast_tag.py`, appcast item construction; `.agents/references/ghostty/dist/macos/update_appcast_tip.py`, appcast item construction). They remove duplicate internal versions—explicitly to avoid Sparkle selecting an enclosure with the wrong signature—and retain only 15 older entries (the `duplicate internal versions` loop and `prune_amount` in those same files).

#### 4. Manual and scheduled discovery

The app menu/action route is `AppDelegate.checkForUpdates(_:)` → `UpdateController.checkForUpdates()` (`.agents/references/ghostty/macos/Sources/App/AppDelegate.swift:961-963`). An idle controller calls `SPUUpdater.checkForUpdates()`. If another cancellable flow is active, it cancels it and retries after 100 ms; if an update has already silently installed, it presents a restart reminder rather than asking Sparkle to start an impossible second check (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateController.swift:62-100`). Scheduled background checks are Sparkle-owned once the updater has started and automatic checks are enabled.

#### 5. UI state and notification strategy

`UpdateDriver` translates every significant `SPUUserDriver` callback into one enum:

```text
idle
  → permissionRequest
  → checking
  → updateAvailable | notFound | error
  → downloading
  → extracting
  → installing
  → idle after relaunch acknowledgement
```

It retains callback closures in state so UI actions remain thin: `.confirm()` replies `.install` or asks Sparkle to retry termination; `.cancel()` invokes check/download cancellation, dismiss, skip, or acknowledgement as appropriate (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateViewModel.swift`, `UpdateState`, `cancelAction`, and `confirm()`). `UpdateViewModel` derives labels, icon, colors, descriptions, badges, and stable progress width from that state rather than duplicating operational state in views (same file, `text`, `maxWidthText`, `iconName`, `description`, `badge`).

Presentation is deliberately unobtrusive when a terminal or quick-terminal window is visible:

- a titlebar accessory pill on supported titled terminal windows (`.agents/references/ghostty/macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift:146-154`, `UpdateAccessoryView`);
- an overlay pill for another terminal view style (`.agents/references/ghostty/macos/Sources/Features/Terminal/TerminalView.swift:135-140`);
- a popover with permission, cancel, skip, later, install/relaunch, progress, release metadata, retry, and acknowledgement controls (`.agents/references/ghostty/macos/Sources/Features/Update/UpdatePopoverView.swift`, view types by state);
- install/cancel actions in the command palette (`.agents/references/ghostty/macos/Sources/Features/Command Palette/TerminalCommandPalette.swift:87-121`).

This is an in-app status surface, **not a macOS `UNUserNotificationCenter` notification**. When no visible terminal target exists, `UpdateDriver.hasUnobtrusiveTarget` falls back to `SPUStandardUserDriver`; closing the final target cancels custom state after a short delay so a later manual check can initialize standard presentation (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateDriver.swift`, `handleTerminalWindowWillClose()`, `hasUnobtrusiveTarget`, and each `standard.show…` fallback). “No updates” auto-dismisses after five seconds (`UpdatePill.swift`, `.onChange(of: model.state)`).

Release-note URLs are Ghostty-specific. Exact `x.y.z` versions link to Ghostty documentation; strings containing a Git hash link to that commit or a comparison from the bundle's `GhosttyCommit` (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateViewModel.swift`, `UpdateState.ReleaseNotes`). Sparkle release-note callbacks are intentionally ignored (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateDriver.swift`, `showUpdateReleaseNotes`), so the custom popover owns this link UX.

#### 6. Download, install, quit, and relaunch

After the user chooses install, Sparkle drives the transfer. `UpdateDriver` only records expected content length and accumulated bytes, then extraction fraction (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateDriver.swift`, `showDownloadInitiated`, `showDownloadDidReceiveExpectedContentLength`, `showDownloadDidReceiveData`, `showDownloadDidStartExtractingUpdate`, and `showExtractionReceivedProgress`). It forwards cancellations supplied by Sparkle.

When ready:

- with custom UI available, `showReady(toInstallAndRelaunch:)` immediately replies `.install`; Sparkle then performs termination, installation, and relaunch;
- without custom UI, the standard driver presents its normal confirmation;
- `showInstallingUpdate` stores Sparkle's `retryTerminatingApplication` closure;
- after relaunch, `showUpdateInstalledAndRelaunched` delegates acknowledgement to standard UI and returns custom state to idle.

(`.agents/references/ghostty/macos/Sources/Features/Update/UpdateDriver.swift`, the named callbacks.)

For a user-confirmed restart, `UpdateState.confirm()` removes the appcast marker before invoking the retry-termination closure. That makes `shouldTerminateWithoutWarning` true, and `AppDelegate.applicationShouldTerminate(_:)` bypasses Ghostty's usual live-terminal quit confirmation (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateViewModel.swift:192-201`, `confirm()`; `.agents/references/ghostty/macos/Sources/App/AppDelegate.swift:387-400`).

With `auto-update=download`, Sparkle can schedule installation on ordinary app quit. `SPUUpdaterDelegate.updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` records a hidden `.installing` state with release metadata and accepts the schedule; Ghostty only surfaces a restart reminder if the user manually checks (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateDelegate.swift:18-35`; `.agents/references/ghostty/macos/Sources/Features/Update/UpdateViewModel.swift`, `isHidden`). This is “download now, install when the app quits,” not unattended forced termination.

### Release, security, and signing flow

Ghostty uses two complementary trust layers:

1. **Apple platform trust:** the workflow imports a Developer ID identity, signs every nested Sparkle XPC/helper executable and framework, signs the app with hardened runtime, creates a signed DMG, notarizes it, and staples both DMG and app (`.agents/references/ghostty/.github/workflows/release-tag.yml:205-275`). Ghostty is not App Sandbox-enabled; its workflow says the bundled Sparkle XPC services are unused but still must be signed (`.agents/references/ghostty/.github/workflows/release-tag.yml:224-237`).
2. **Sparkle update trust:** the production public EdDSA key is embedded in the app, while the private key remains a CI secret used by Sparkle's `sign_update`; emitted signature/length attributes are copied to the appcast enclosure (`.agents/references/ghostty/.github/workflows/release-tag.yml:191-203`, `339-351`; `.agents/references/ghostty/dist/macos/update_appcast_tag.py`, `sign_update.txt` parsing and enclosure construction). Sparkle's own security guidance treats code signing and EdDSA as complementary checks and recommends HTTPS feeds ([Sparkle security and reliability](https://sparkle-project.org/documentation/security-and-reliability/)).

The stable release workflow uploads binaries and a staged appcast but does not activate the feed. A separate manually dispatched publish workflow verifies every release URL returns HTTP 200 and only then replaces the root appcast (`.agents/references/ghostty/.github/workflows/release-tag.yml:384-414`; `.agents/references/ghostty/.github/workflows/publish-tag.yml:33-73`). Tip automation uses the same crucial ordering—payload first, appcast second (`.agents/references/ghostty/.github/workflows/release-tip.yml:724-780`). This prevents a client from discovering a signed update whose payload is not yet available.

Sparkle 2.9 also supports signed feeds (`SURequireSignedFeed`) and pre-extraction verification (`SUVerifyUpdateBeforeExtraction`). Ghostty's reviewed plist does not enable either; Fission should evaluate enabling both rather than assuming Ghostty's exact settings are the ceiling ([Sparkle security and reliability](https://sparkle-project.org/documentation/security-and-reliability/)).

### Platform differences

Ghostty explicitly supports this updater only on macOS because its Linux builds are expected to be managed by distribution package managers (`.agents/references/ghostty/src/config/Config.zig:3895-3902`, `3937-3941`). There is no corresponding Linux runtime update implementation. Within macOS, its shipped DMG/appcast is universal and appcast minimum system version is `13.0.0` (`.agents/references/ghostty/dist/macos/update_appcast_tag.py`, `sparkle:minimumSystemVersion`; `.agents/references/ghostty/.github/workflows/release-tag.yml`, macOS artifact names).

For Fission, Sparkle belongs only to `FissionDesktop`. `FissionMobile` must continue using App Store/TestFlight/MDM update mechanisms; it should not receive this dependency. The repository's dependency rule also argues against putting a macOS installer framework in `FissionCore` (`ARCHITECTURE.md`, “Dependency rule” and “Applications”).

### Tests and development tooling

Ghostty has useful but incomplete coverage:

- `UpdateStateTests` verifies enum equality, hidden auto-install state, and termination-warning semantics (`.agents/references/ghostty/macos/Tests/Update/UpdateStateTests.swift`).
- `UpdateViewModelTests` verifies labels and progress formatting (`.agents/references/ghostty/macos/Tests/Update/UpdateViewModelTests.swift`).
- `ReleaseNotesTests` covers tagged, short/full hash, compare, and invalid version forms (`.agents/references/ghostty/macos/Tests/Update/ReleaseNotesTests.swift`).
- `ConfigTests.defaultConfigIsLoaded` covers build-channel default finalization (`.agents/references/ghostty/macos/Tests/Ghostty/ConfigTests.swift:192-196`).
- `UpdateSimulator` provides happy, unavailable, error, slow download, permission, cancellation, installation, and silent-auto-update scenarios, but its documented use is a manual source override and the call in `AppDelegate.checkForUpdates` remains commented out (`.agents/references/ghostty/macos/Sources/Features/Update/UpdateSimulator.swift`, cases and `simulate(with:)`; `.agents/references/ghostty/macos/Sources/App/AppDelegate.swift:961-963`).

The reviewed tests do not directly exercise `UpdateController`, delegate feed selection, no-window fallback, Sparkle preference mapping, appcast generator scripts, signature failure, real installation/relaunch, or release publication ordering. Fission should retain Ghostty's deterministic state simulation but add dependency seams and pipeline tests so these omissions are not inherited.

## What Fission can and cannot reuse

### Reusable with light adaptation

- **Sparkle itself and the controller boundary.** Fission is also a direct-distribution Swift macOS app with hardened runtime, so `SPUUpdater` is a strong fit (`Apps/Desktop/FissionDesktop.xcodeproj/project.pbxproj:485-516`).
- **A callback-backed update state machine.** Keeping Sparkle reply/cancel closures in transient state makes UI actions declarative and testable.
- **Standard-driver fallback.** Fission can start with `SPUStandardUpdaterController`, then retain a `SPUStandardUserDriver` fallback if it adds a custom toolbar surface.
- **Separate internal/display versions.** `github.run_number` is already injected into `CURRENT_PROJECT_VERSION`; use it for `sparkle:version`, and introduce an honest display version instead of permanent `MARKETING_VERSION=1.0` (`scripts/package-desktop.sh:10-22`; project file lines 487-515).
- **Payload-before-feed publishing, EdDSA signing, exact dependency pinning, nested-code signing, notarization, and stapling.** These are the most valuable pieces to copy.
- **Scenario simulator.** A launch argument/environment-selected simulated update service is better than Ghostty's commented source edit and would fit Fission's existing UI-test style.

### Not reusable verbatim

- **Window detection and titlebar hosting.** `TerminalWindow`, `QuickTerminalWindow`, `NonDraggableHostingView`, and Ghostty's titlebar accessories are Ghostty-specific. Fission is a SwiftUI `WindowGroup` with its root toolbar in `ThreadListView` (`Apps/Desktop/Sources/App/FissionDesktopApp.swift:91-106`; `Apps/Desktop/Sources/Threads/ThreadListView.swift:34-50`).
- **Ghostty config plumbing.** Fission has no Zig configuration layer. Its existing user toggles use `@AppStorage` / `UserDefaults` (`Apps/Desktop/Sources/App/NotificationSettingsView.swift:4-34`; `Apps/Desktop/Sources/Threads/NewThreadSheet.swift:10`; `Apps/Desktop/Sources/Terminal/TerminalWorkspaceView.swift:254-268`). Updater preferences should use Sparkle's updater properties as the source of truth, not duplicate `@AppStorage`, unless Fission deliberately wants managed overrides.
- **Ghostty release notes.** Fission needs release-page or commit-comparison URLs based on its own version strategy; no `GhosttyCommit` equivalent currently exists.
- **Ghostty's quit bypass.** Fission has no current quit-confirmation delegate. More importantly, its detached PTY helper changes what “relaunch” means; blindly copying the bypass would conceal the stale-helper problem.
- **Separate stable/tip feeds today.** Fission currently has only one every-main-commit release stream (`.github/workflows/release-desktop.yml:1-14`, `48-72`). A channel switcher is premature until stable releases have separate cadence, versioning, and retention.
- **Appcast generator code verbatim.** It hard-codes Ghostty URLs, minimum OS 13, retention, and release-note shape. Reuse the schema and invariants, not the script.

## Proposed Fission architecture

Keep this desktop-only and feature-oriented, consistent with `ARCHITECTURE.md`.

### Runtime modules and exact likely files

```text
Apps/Desktop/Sources/Updates/
  ApplicationUpdateController.swift   // owns SPUUpdater; start/check; narrow app API
  ApplicationUpdateDriver.swift       // optional phase 2 SPUUserDriver + delegate
  ApplicationUpdateModel.swift        // @MainActor observable state and derived presentation
  ApplicationUpdateViews.swift        // toolbar pill/popover and settings section
  ApplicationUpdateConfiguration.swift// feed URL/channel/build metadata validation

Apps/Desktop/Tests/
  ApplicationUpdateModelTests.swift
  ApplicationUpdateDriverTests.swift
  ApplicationUpdateConfigurationTests.swift

scripts/
  generate-appcast.py                  // or use Sparkle generate_appcast where sufficient
  package-desktop.sh                   // production signing/notarization + metadata inputs

.github/workflows/
  release-desktop.yml                  // build/sign/notarize, sign payload, upload payload, verify
  publish-desktop-appcast.yml          // optional stable promotion gate
```

Project wiring belongs in `Apps/Desktop/FissionDesktop.xcodeproj/project.pbxproj`: add an exact Sparkle package reference/product, link it only to `FissionDesktop`, add update sources to the app target and tests to `FissionDesktopTests`, and add generated plist keys (`SUPublicEDKey`, optionally `SUFeedURL`, `SUEnableAutomaticChecks`; evaluate `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`). Do not link Sparkle to `FissionExecution`, `FissionCore`, or Mobile.

### App composition and UI integration

`FissionDesktopApp` is the process-wide composition root. It should create one long-lived `ApplicationUpdateController` and model in `init()`, start it once, inject the model into `ThreadListView`, and add a `CommandGroup(after: .appInfo)` button labelled “Check for Updates…” (`Apps/Desktop/Sources/App/FissionDesktopApp.swift`, `init()`, `body`, and `AppKeyboardCommands`). If Sparkle termination callbacks require AppKit lifecycle hooks, add a small `DesktopAppDelegate` through `@NSApplicationDelegateAdaptor`; do not move updater mechanics into the view hierarchy.

For custom presentation, add an update `ToolbarItem` beside `ThreadToolbarContent` in `ThreadListView.toolbar` or a root overlay anchored to the window, not inside `TerminalWorkspaceView` (`Apps/Desktop/Sources/Threads/ThreadListView.swift:34-50`). It must remain available when there is no selected Thread. Keep standard Sparkle dialogs as fallback until multi-window targeting and focus behavior are proven.

Replace the current one-purpose Settings scene content with a small `DesktopSettingsView` containing Notifications and Updates sections/tabs; reuse `NotificationSettingsView`, and add automatic-check/download controls bound through controller accessors (`Apps/Desktop/Sources/App/FissionDesktopApp.swift:104-106`; `NotificationSettingsView.swift`). Do not request `UNUserNotificationCenter` authorization for app updates merely to mimic the Ghostty pill—Ghostty does not use OS notifications for updates.

### Update service seam

Unlike Ghostty, define a narrow protocol used by the model, for example `start()`, `check()`, `cancel()`, and state callbacks. The production adapter wraps Sparkle; a deterministic fake drives UI tests. Keep Sparkle types inside the adapter where practical, and expose Fission-owned metadata (`version`, `size`, `date`, `releaseNotesURL`) to views. This makes UI and policy tests independent of Sparkle's concrete Objective-C objects and avoids `SUAppcastItem` test construction hacks.

### Release and feed design

For the first release stream:

- Use `CURRENT_PROJECT_VERSION=${{ github.run_number }}` / `sparkle:version` as the monotonically increasing comparison value.
- Set `MARKETING_VERSION` / `sparkle:shortVersionString` from an explicit release version or, for continuing main snapshots, a short commit plus date. Do not advertise every build forever as `1.0`.
- Host one HTTPS appcast at a stable URL. Its enclosure may point to an immutable GitHub Release asset or dedicated object storage; confirm redirects and range requests in an end-to-end test.
- Keep the EdDSA private key only in CI secrets. Inject the public key into the production app at build time. Keep Debug automatic checks disabled and provide a local/simulated feed.
- Sign the nested `FissionExecution` helper, Sparkle's nested code, then the containing app; create/notarize/staple the DMG; run `codesign --verify --deep --strict`, `spctl`, `stapler validate`, and `hdiutil verify` before publication.
- Upload the DMG, verify the final enclosure URL and hash/signature, then atomically publish the appcast. A GitHub Release marked “latest” is not itself a safe discovery protocol.

### Persistent execution-helper policy

This is the Fission-specific design decision Ghostty cannot answer.

Today, `FissionExecution` launches from `Fission.app/Contents/Helpers`, deliberately outlives the GUI, owns PTYs, and uses a socket path derived from application-support location, bundle/channel, and protocol version (`Apps/Desktop/Sources/Terminal/TerminalExecutionClient.swift`, `TerminalDaemonLauncher.launch()`; `Apps/Desktop/Sources/Terminal/TerminalExecutionProtocol.swift:115-130`; `Apps/Desktop/Sources/Execution/main.swift`, `TerminalExecutionDaemon`). Replacing and relaunching the app does not replace the already-running process image. The new GUI reconnects if the wire protocol version is unchanged; if it changes, the new socket path launches a second daemon while the old daemon and its PTYs remain orphaned from the new GUI.

Before updater rollout, choose and document one of these policies:

1. **Recommended near-term: compatibility plus deferred helper upgrade.** Add a daemon handshake reporting protocol version and helper build. Keep N/N-1 protocol compatibility. After GUI relaunch, show “terminal engine update pending; it will apply after active sessions end” when builds differ. Add a daemon shutdown-when-empty command so it exits after the final PTY closes and the next connection launches the new bundled helper. Never kill active shells to complete an app update.
2. **Stronger later: supervised durable sessions.** Implement the launchd/durable Run work already called out in `ARCHITECTURE.md`, enabling explicit recovery/classification and controlled helper replacement across app updates.
3. **Do not choose silently:** force-killing the helper on “Install and Relaunch.” It would violate Fission's stated persistent-terminal behavior and can destroy user work.

The appcast minimum-version and rollout policy must prevent a GUI that cannot communicate with the live previous helper from being offered as a normal in-place update.

## Staged implementation plan

### Stage 0 — production distribution baseline

1. Provision Developer ID Application and App Store Connect notarization credentials.
2. Update `scripts/package-desktop.sh` and `release-desktop.yml` to sign `FissionExecution` and the app inside-out, notarize, staple, and validate.
3. Replace fixed display versioning with an explicit policy; keep run number monotonic.
4. Prove a clean-machine install and launch before adding Sparkle.

**Exit gate:** the exact DMG intended for update delivery passes Gatekeeper offline and online, and both app and helper show the expected Team ID and hardened runtime.

### Stage 1 — safe minimum updater

1. Pin Sparkle and add `ApplicationUpdateController` using standard Sparkle UI.
2. Add “Check for Updates…” and start Sparkle once at app startup.
3. Ship production public key/feed configuration; disable real checks in Debug.
4. Generate/sign an appcast in CI; publish payload before feed.
5. Offer manual checks first. Enable scheduled checks only after telemetry-free consent/default policy is decided.

**Exit gate:** an installed old build discovers, validates, installs, and relaunches into a newer signed/notarized build; tampered payload and stale/lower version are rejected.

### Stage 2 — Fission-native state and settings

1. Add Fission-owned state/model and custom driver with standard fallback.
2. Add toolbar pill/popover, cancellation, progress, error/retry, release notes, skip/later/install/relaunch, and accessibility labels.
3. Add Updates settings bound to Sparkle's persisted properties.
4. Add a launch-argument-selected simulator covering every state.

**Exit gate:** all states work with no selected Thread, multiple windows, reduced motion, VoiceOver, keyboard-only use, and window closure during an update.

### Stage 3 — helper compatibility and automatic download

1. Add helper build/protocol handshake and shutdown-when-empty/deferred-update behavior.
2. Test GUI N+1 against live helper N and incompatible protocol behavior.
3. Only after that, consider automatic download/install-on-quit.
4. Add a stable channel only when Fission has a genuine stable release process; use a separate feed as Ghostty does or deliberately adopt Sparkle channels with tests.

**Exit gate:** updater relaunch never loses a PTY, never strands a session invisibly, and accurately reports whether both GUI and helper are on the new build.

## Risks and decisions required

| Risk / decision | Why it matters | Recommendation |
|---|---|---|
| Signing/notarization is absent | Sparkle does not turn an ad-hoc build into a trusted distribution | Block updater release on Stage 0 |
| Private EdDSA key compromise | An attacker could sign a malicious update | Dedicated CI secret, restricted environment, rotation/recovery runbook; never write it to artifacts/logs |
| Appcast publication race | Clients can discover an unavailable package | Upload and verify immutable payload before feed; serialize releases |
| Rollback/version monotonicity | Sparkle compares internal versions, not Git history | Keep run number monotonic; define emergency forward-fix process rather than reusing a version |
| Existing `desktop-<run>` stream is neither clearly stable nor nightly | Channel/default UX will be misleading | Start with one explicitly named channel; add stable promotion later |
| Helper remains old after GUI relaunch | Fixes and protocol changes may not apply; killing it loses shells | Compatibility handshake plus shutdown-when-empty and visible deferred status |
| User preference ownership | Duplicate `@AppStorage` and Sparkle defaults can drift | Treat Sparkle updater properties/defaults as source of truth; only add explicit managed overrides |
| Multi-window custom UI | One process-wide update can appear in several windows or nowhere | Standard UI first; define active/key-window targeting before custom pill |
| App installed on read-only/nonstandard volume | Replacement may fail or require authorization | Exercise Sparkle standard error/authorization paths; preserve actionable fallback download link |
| Supply-chain dependency | Sparkle itself is privileged update code | Exact pin, dependency review, prompt security updates, release SBOM/lock evidence |
| Signed feed options | Ghostty signs enclosures but does not enable reviewed signed-feed/pre-extraction flags | Evaluate and preferably enable `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` with rotation plan |
| Skipping versions | Useful for stable releases, confusing for continuous snapshots | Omit “Skip” for main snapshots; retain “Later.” Define skip semantics before stable UI |
| Privacy/default checks | A network request reveals normal connection metadata | Explain behavior; never send Sparkle system profile; choose opt-in or a clear documented default |

## Recommended tests

### Unit and model tests

- Every legal state transition, action (`install`, `later`, `skip`, `cancel`, `retry`, acknowledge), derived label/icon/progress, and cancellation race.
- Clamp malformed progress, unknown length, zero length, and callbacks arriving after cancellation/dismissal.
- Feed selection and build metadata for Debug, production, and any future channel; reject non-HTTPS production feeds.
- Release-note URL construction and untrusted metadata rendering.
- Preference mapping without resetting Sparkle-persisted user choice at launch.
- Helper compatibility matrix: GUI/helper builds N-1, N, N+1 and protocol versions; shutdown-when-empty semantics.

### Appcast and release-pipeline tests

- Parse generated XML; require unique monotonic `sparkle:version`, correct display version, minimum OS 14.0+, enclosure URL, size, MIME type, EdDSA signature, and release notes.
- Generate two releases concurrently in a test bucket and prove serialization/atomic feed publication.
- Verify enclosure returns success before appcast promotion; test redirects, partial/range download, interrupted retry, and missing artifact.
- Tamper one byte in DMG, alter appcast metadata, use wrong key, expire/rotate key, and verify rejection.
- Verify every nested binary's signing identity and hardened runtime, notarization ticket, stapling, DMG integrity, and clean-host Gatekeeper launch.
- Upgrade from the oldest supported app version and from the immediately previous version; reject same/older internal versions.

### Runtime integration tests

- Manual check: update available, no update, offline, TLS failure, malformed feed, HTTP error, and timeout.
- Download cancel/retry; quit during download; window closes during each phase; app has no windows; multiple windows observe one coherent operation.
- Install now, install on quit, relaunch failure, app moved after download, destination not writable, and insufficient disk space.
- Preserve Fission database, `UserDefaults` terminal tabs, notification preference, recent paths, selected Thread, and active terminal output across app replacement (`Apps/Desktop/Sources/App/FissionDesktopApp.swift`, `databasePath`; `Apps/Desktop/Sources/Terminal/TerminalWorkspaceView.swift`, `TabPersistence`; `Apps/Desktop/Sources/App/AgentTaskNotificationCoordinator.swift`, `NotificationPreferences`).
- Keep active PTYs alive across GUI install/relaunch; prove the updated GUI reattaches without duplicated/lost output and reports an old helper; close final PTY and prove the next helper is the new build.
- If protocol changes, prove old sessions remain discoverable/recoverable rather than silently launching a disconnected second world.

### UI and accessibility tests

- Menu item enablement and standard fallback with no selected Thread.
- Custom pill/popover keyboard order, VoiceOver labels/status announcements, Dynamic Type-like text sizing behavior, Increase Contrast, Reduce Motion, and long localized errors/version strings.
- Permission/default-choice screen never requests system profile data.
- “No updates” and errors remain understandable without relying on color or transient animation.
- Simulator scenarios selectable by UI-test launch environment, with no production network access.

## Bottom line

Ghostty's core lesson is not “write an updater”; it is **let Sparkle own the dangerous mechanics, model the user-visible workflow explicitly, and make release publication a security-critical two-phase operation**. Fission can adopt that design cleanly in its desktop app. Its blockers are not SwiftUI integration: they are production signing/notarization, truthful version/channel policy, appcast publication infrastructure, and the unique fact that updating/relaunching the GUI does not update its persistent terminal helper.

Implement standard Sparkle UI only after the distribution baseline is trustworthy, then add Ghostty-like custom presentation, and do not enable automatic download/install-on-quit until the helper compatibility/deferred-restart policy is implemented and tested.

## Primary sources

### Repository sources

- Ghostty updater runtime: `.agents/references/ghostty/macos/Sources/Features/Update/`
- Ghostty app composition and quit/config behavior: `.agents/references/ghostty/macos/Sources/App/AppDelegate.swift`
- Ghostty update configuration/version channel: `.agents/references/ghostty/src/config/Config.zig`; `.agents/references/ghostty/src/build/Config.zig`; `.agents/references/ghostty/macos/Sources/Ghostty/Ghostty.Config.swift`
- Ghostty appcast generation and release automation: `.agents/references/ghostty/dist/macos/update_appcast_tag.py`; `.agents/references/ghostty/dist/macos/update_appcast_tip.py`; `.agents/references/ghostty/.github/workflows/release-tag.yml`; `.agents/references/ghostty/.github/workflows/release-tip.yml`; `.agents/references/ghostty/.github/workflows/publish-tag.yml`
- Ghostty update tests: `.agents/references/ghostty/macos/Tests/Update/`; `.agents/references/ghostty/macos/Tests/Ghostty/ConfigTests.swift`
- Fission desktop composition/build/release: `Apps/Desktop/Sources/App/FissionDesktopApp.swift`; `Apps/Desktop/FissionDesktop.xcodeproj/project.pbxproj`; `scripts/package-desktop.sh`; `.github/workflows/release-desktop.yml`; `Apps/Desktop/README.md`
- Fission persistent execution design: `ARCHITECTURE.md`; `Apps/Desktop/Sources/Terminal/TerminalExecutionProtocol.swift`; `Apps/Desktop/Sources/Terminal/TerminalExecutionClient.swift`; `Apps/Desktop/Sources/Execution/main.swift`

### Official upstream documentation

- Sparkle, [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)
- Sparkle, [Customization and preference persistence](https://sparkle-project.org/documentation/customization/)
- Sparkle, [Security and reliability](https://sparkle-project.org/documentation/security-and-reliability/)
- Sparkle, [Publishing an update](https://sparkle-project.org/documentation/publishing/)
- Sparkle, [Sandboxing](https://sparkle-project.org/documentation/sandboxing/)
