# Architecture

Fission uses feature-oriented MVVM for its desktop and mobile applications, with dependency inversion at the Core package.

## Dependency rule

Dependencies point inward:

```text
Desktop / Mobile UI → Core ← Server
```

`FissionCore` must not import SwiftUI or depend on app or server frameworks. Apps may depend on Core.

## Applications

### Desktop execution

Desktop terminal processes are owned by the bundled `FissionExecution` helper, not by the SwiftUI
scene or Ghostty renderer. The app and helper communicate over a versioned, user-only Unix-domain
socket. Ghostty uses its in-memory backend as the rendering adapter: input and viewport changes go
to the helper, while PTY output and bounded replay come back to the renderer.

Closing a window or quitting Desktop therefore detaches presentation without terminating the shell.
Terminal IDs and tab presentation are persisted so a later Desktop process can attach to the same
helper-owned PTY. Explicitly closing a tab or settling its Thread terminates that PTY.

The helper is launched on demand and survives its launching app process. This supports app close and
quit, but is not reboot recovery: a later module will need launchd registration plus durable Run
records to recover or classify sessions after logout, reboot, helper failure, and app updates.

Desktop and Mobile organize presentation code by feature. Each feature owns its SwiftUI views, platform-specific presentation state, and navigation. Shared observable state and workflows used by multiple applications belong in Core. App-wide composition and entry points belong in `Sources/App`.

The Server is also organized by feature, but does not use MVVM. Its `Sources/App` directory owns startup and dependency composition.

## Core

- `Domains` contains domain entities and behavior.
- `UseCases` coordinates domain operations and owns shared, platform-neutral observable state.
- `Interfaces` contains dependency seams required by use cases.

Concrete adapters for persistence, networking, and agent providers live under `FissionCore/Persistence` or an equivalent infrastructure directory. Add an interface only when a use case needs the dependency and at least one concrete adapter is being introduced.

## Core package

`FissionCore` is a single library containing domain entities, use cases, dependency interfaces, and persistence adapters.
