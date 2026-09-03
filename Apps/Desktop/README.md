# Desktop

The Fission macOS application uses SwiftUI and feature-oriented MVVM. Its terminal workspaces embed libghostty through the `GhosttyTerminal` Swift package, including Ghostty's Metal renderer, PTY-backed shell sessions, input handling, and runtime resources.

## Run

From the repository root, launch the Debug app in development mode:

```bash
mise run desktop
```

The task watches the desktop and Core Swift sources. When they change, it rebuilds and relaunches the app. Stop it with `Ctrl-C`. To build and launch only once, run `mise run desktop:launch`.

You can also open `FissionDesktop.xcodeproj`, select **My Mac**, and press Run. The app persists Threads in SQLite through the local `FissionCore` package.

### Pi activity integration

On launch, Fission installs its bundled Pi extension at
`~/.pi/agent/extensions/fission-agent-state.ts` (or under `PI_CODING_AGENT_DIR` when set).
The extension is inactive outside Fission terminals. Inside Fission it reports Pi's idle, running,
blocked, and finished states to the sidebar over a token-authenticated loopback socket. Restart Pi
after first launching Fission so the newly installed extension is loaded.

To build it directly with Xcode:

```bash
xcodebuild \
  -project Apps/Desktop/FissionDesktop.xcodeproj \
  -scheme FissionDesktop \
  -destination 'platform=macOS' \
  -derivedDataPath Apps/Desktop/.derivedData \
  build
```

Launch the built app from Xcode or with:

```bash
open Apps/Desktop/.derivedData/Build/Products/Debug/FissionDev.app
```

## UI verification

Run the serial macOS UI test suite with isolated per-test application data:

```bash
.agents/skills/verify-fission/scripts/run-desktop-ui-tests.sh
```

The harness writes screenshots and diagnostics to
`/tmp/fission-verification-$UID/FissionDesktopUITests.xcresult`. macOS may require a one-time
Accessibility grant for the Xcode/XCTest helper; Terminal itself does not need the grant.

## Package

Build an optimized universal macOS app and package it as a drag-to-Applications DMG:

```bash
mise run desktop:package
```

The resulting disk image is written to `dist/Fission.dmg`.

Every push to `main` also runs `.github/workflows/release-desktop.yml`. It creates a `desktop-<run number>` GitHub release containing the DMG and its SHA-256 checksum. A failed workflow can be rerun safely without creating a duplicate release.

The default and automated builds use an ad-hoc signature, which is suitable for local installation. Distribution to other users without Gatekeeper warnings requires signing with a Developer ID Application certificate and notarizing the disk image through Apple.
