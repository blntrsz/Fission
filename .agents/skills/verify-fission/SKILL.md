---
name: verify-fission
description: Prove Fission changes through builds, tests, and user-visible app behavior. Use after changing Desktop or Mobile UI, terminal interactions, navigation, persistence, or other behavior that should be exercised in the real app.
---

# Verify Fission

Produce evidence at the same boundary the user experiences. A green build alone is supporting evidence, not UI proof.

## Choose the surface

- Core-only behavior: run Core tests and the smallest relevant app build.
- Desktop behavior: run the serial XCUITest harness below.
- Mobile behavior: run `mise run mobile:launch`, exercise through an available simulator-driving tool, and capture a screenshot with `xcrun simctl io booted screenshot <path>`. State the limitation when no interaction tool is available.

## Deterministic checks

Run the checks covering the changed area:

```bash
swift test --package-path Packages/Core
xcodebuild -project Apps/Desktop/FissionDesktop.xcodeproj \
  -scheme FissionDesktop -destination 'platform=macOS' \
  -derivedDataPath Apps/Desktop/.derivedData \
  -parallel-testing-enabled NO test
mise run lint
```

A pre-existing failure is evidence to report with its exact command and output; it does not erase the need to exercise unaffected behavior.

## Desktop user-flow proof

Run all Desktop UI tests serially:

```bash
.agents/skills/verify-fission/scripts/run-desktop-ui-tests.sh
```

Pass XCTest identifiers to select flows:

```bash
.agents/skills/verify-fission/scripts/run-desktop-ui-tests.sh \
  FissionDesktopUITests/FissionDesktopUITests/testUserCanCreateThreadFromFreshState
```

Each test owns a unique temporary `HOME`, `CFFIXED_USER_HOME`, `PI_CODING_AGENT_DIR`, and project directory; teardown terminates the app and removes that state. Keep tests independent of execution order. Keep macOS UI tests serial because application focus, clipboard state, and the desktop session are machine-global.

XCUITest drives Fission through accessibility identifiers and retains screenshots in:

```text
/tmp/fission-verification-$UID/FissionDesktopUITests.xcresult
```

Inspect the result bundle in Xcode or with `xcrun xcresulttool`. When UI automation cannot initialize, request a one-time Accessibility grant for the Xcode/XCTest helper—not Terminal/pi—under **System Settings → Privacy & Security → Accessibility**. An active logged-in GUI session is required.

Add user-flow coverage as vertical slices: one failing XCUITest, the smallest app/testability change that makes it pass, then the next flow. Prefer stable `.accessibilityIdentifier(...)` keys while preserving meaningful user-facing labels.

## Evidence

A complete proof names:

1. the test method and user flow exercised,
2. the visible/accessibility assertion,
3. deterministic checks run,
4. the `.xcresult` artifact path,
5. any unverified boundary.

Completion means the relevant user flow was exercised and observed, checks were recorded, and any environmental blocker was reported exactly.
