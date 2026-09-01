# Architecture

Fission uses feature-oriented MVVM for its desktop and mobile applications, with dependency inversion at the Core package.

## Dependency rule

Dependencies point inward:

```text
Desktop / Mobile UI → Core ← Server
```

`FissionCore` must not import SwiftUI or depend on app or server frameworks. Apps may depend on Core.

## Applications

Desktop and Mobile organize presentation code by feature. Each feature owns its SwiftUI views, observable view models, and navigation. App-wide composition and entry points belong in `Sources/App`.

The Server is also organized by feature, but does not use MVVM. Its `Sources/App` directory owns startup and dependency composition.

## Core

- `Domains` contains domain entities and behavior.
- `UseCases` coordinates domain operations.
- `Interfaces` contains dependency seams required by use cases.

Concrete adapters for persistence, networking, and agent providers live under `FissionCore/Persistence` or an equivalent infrastructure directory. Add an interface only when a use case needs the dependency and at least one concrete adapter is being introduced.

## Core package

`FissionCore` is a single library containing domain entities, use cases, dependency interfaces, and persistence adapters.
