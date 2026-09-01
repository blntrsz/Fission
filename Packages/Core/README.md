# Fission Core

Shared domain logic and persistence for Fission applications, exposed through the single `FissionCore` library.

```swift
import FissionCore

let repository = try SQLiteThreadRepository(path: databaseURL.path)
```

The SQLite repository uses GRDB, creates its schema through a migration when opened, and serializes access through a database queue. Use `:memory:` for tests.
