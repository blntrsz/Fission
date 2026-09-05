# Desktop

The Fission macOS application uses SwiftUI and feature-oriented MVVM. Its terminal workspaces embed libghostty through the `GhosttyTerminal` Swift package, including Ghostty's Metal renderer, PTY-backed shell sessions, input handling, and runtime resources.

## Run

From the repository root, launch the Debug app in development mode:

```bash
mise run desktop
```

The task watches the desktop and Core Swift sources. When they change, it rebuilds and relaunches the app. Stop it with `Ctrl-C`. To build and launch only once, run `mise run desktop:launch`.

You can also open `FissionDesktop.xcodeproj`, select **My Mac**, and press Run. The app persists Threads in SQLite through the local `FissionCore` package.

### Persistent terminals

Fission embeds and launches the `FissionExecution` helper on demand. The helper owns terminal PTYs
and keeps them running when the window closes or the app quits. Reopening Fission reattaches the
Ghostty renderer and replays up to 4 MiB of recent output per terminal.

Closing a terminal tab or settling its Thread intentionally terminates its shell. The helper does
not yet restore work through logout, reboot, or a helper crash, and Pi activity notifications still
belong to the GUI process even though the underlying Pi process continues.

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

Local packages use an ad-hoc signature and do not start the updater. Official builds are produced by `.github/workflows/release-desktop.yml` on every push to `main`. The workflow:

1. Developer ID-signs the app, execution helper, and Sparkle components.
2. Notarizes and staples both the app and DMG.
3. EdDSA-signs the DMG and generates `appcast.xml`.
4. Uploads all artifacts to a draft `desktop-<run number>` GitHub release.
5. Verifies the staged assets before publishing the release as `latest`.

Official builds check this stable Sparkle feed automatically:

```text
https://github.com/blntrsz/Fission/releases/latest/download/appcast.xml
```

Users can also choose **Fission → Check for Updates…**. Sparkle verifies the appcast signature before installing and relaunching the application. Active terminal sessions remain owned by the existing `FissionExecution` helper during a GUI relaunch; helper-version handoff is tracked separately and automatic download/install-on-quit should not be enabled until that lifecycle is implemented.

### Release secrets

Configure these GitHub Actions secrets before enabling the release workflow:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting the `.p12` |
| `MACOS_KEYCHAIN_PASSWORD` | Random password for the temporary CI keychain |
| `APPLE_ID` | Apple ID used by `notarytool` |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `SPARKLE_PRIVATE_KEY` | Private EdDSA key consumed by Sparkle's `sign_update` |
| `SPARKLE_PUBLIC_KEY` | Matching public key embedded in official builds |

Generate the Sparkle key pair once with Sparkle's `generate_keys` utility, back up the private key securely, and never commit it. Rotating this key requires a signed transition release; losing it prevents existing installations from trusting subsequent updates.
