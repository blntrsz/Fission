# Desktop

The Fission macOS application uses SwiftUI and feature-oriented MVVM. Its terminal workspaces embed libghostty through the `GhosttyTerminal` Swift package, including Ghostty's Metal renderer, PTY-backed shell sessions, input handling, and runtime resources.

## Run

From the repository root, launch the Debug app in development mode:

```bash
mise run desktop
```

The task watches the desktop and Core Swift sources. When they change, it rebuilds and relaunches the app. Stop it with `Ctrl-C`. To build and launch only once, run `mise run desktop:launch`.

You can also open `FissionDesktop.xcodeproj`, select **My Mac**, and press Run. The app persists Threads in SQLite through the local `FissionCore` package.

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
open Apps/Desktop/.derivedData/Build/Products/Debug/FissionDesktop.app
```
