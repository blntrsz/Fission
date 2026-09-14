# Electron Desktop

Fission's desktop app is an Electron shell around the same Thread, Remote Machine, and isolate workflows as the previous SwiftUI app.

## Run

From the repository root:

```bash
mise run desktop
```

Or from this package:

```bash
npm install
npm test
npm run dev
```

`mise run desktop:launch` builds once and starts Electron. Isolated data can be pointed at a temp directory with `FISSION_DATA_DIR`.

## Persistence

Threads are stored in SQLite (`fission.sqlite`) with the same schema as `FissionCore`. Remote machines live in `fission-remote-machines.json`. Terminal tab layout is saved beside those files.

On macOS those files stay in Application Support so an existing Fission database can be reused.

## Terminals

Each tab is an xterm.js surface attached to a `node-pty` session in the Electron main process. Closing a tab or settling its Thread terminates that PTY. Quitting the app currently ends sessions with the GUI process; the old `FissionExecution` helper is not used.

Remote Threads still start a login shell that execs mosh into the selected project path.

## Pi activity

On launch, Fission installs `resources/fission-pi-agent-state.ts` at `~/.pi/agent/extensions/fission-agent-state.ts` (or under `PI_CODING_AGENT_DIR`).
