# Architecture

Fission uses feature-oriented MVVM for its Swift applications, with dependency inversion at the Core package. Desktop now ships as an Electron app in `packages/electron`.

## Dependency rule

Dependencies point inward:

```text
Desktop (Electron) / Mobile UI → Core ← Server
```

`FissionCore` must not import SwiftUI or depend on app or server frameworks. The Electron desktop reimplements the Core Thread schema, Remote Machines, and isolate workflows in TypeScript so the renderer never talks to SQLite directly.

## Applications

### Desktop execution

The Electron main process owns `node-pty` sessions. The renderer attaches xterm.js to those PTYs over IPC. Closing a tab or settling its Thread terminates that PTY. Terminal tab presentation is persisted so the same Thread restores its tabs after a relaunch. PTYs currently live with the GUI process, so quitting Electron ends open shells.

Remote Threads still start a login shell that execs mosh into the selected project path.

The previous SwiftUI/Ghostty/`FissionExecution` desktop remains under `Apps/Desktop` as a reference implementation.

Mobile organizes presentation code by feature. Shared Swift domain types remain in Core. The Electron app's shared TypeScript lives in `packages/electron/src/shared`.

The Server is also organized by feature, but does not use MVVM. Its `Sources/App` directory owns startup and dependency composition.

## Core

- `Domains` contains domain entities and behavior.
- `UseCases` coordinates domain operations and owns shared, platform-neutral observable state.
- `Interfaces` contains dependency seams required by use cases.

Concrete adapters for persistence, networking, and agent providers live under `FissionCore/Persistence` or an equivalent infrastructure directory. Add an interface only when a use case needs the dependency and at least one concrete adapter is being introduced.

## Core package

`FissionCore` is a single library containing domain entities, use cases, dependency interfaces, and persistence adapters.
