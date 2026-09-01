# Mobile

The Fission iOS application uses SwiftUI and feature-oriented MVVM.

## Run

From the repository root, launch the Debug app in development mode:

```bash
mise run mobile
```

The task watches the mobile and Core Swift sources. When they change, it rebuilds, reinstalls, and relaunches the app in Simulator. Stop it with `Ctrl-C`. To build and launch only once, run `mise run mobile:launch`.

The task defaults to the newest available `iPhone 17 Pro` runtime. Choose another installed Simulator by name with:

```bash
IOS_SIMULATOR='iPhone 17' mise run mobile
```

You can also open `FissionMobile.xcodeproj`, select an iPhone simulator, and press Run. The app persists Threads in SQLite through the local `FissionCore` package.

To build it directly with Xcode:

```bash
xcodebuild \
  -project Apps/Mobile/FissionMobile.xcodeproj \
  -scheme FissionMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```
