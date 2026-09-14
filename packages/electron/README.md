# Electron

Bun workspace package that launches a Chromium Electron shell.

Lives under lowercase `packages/` so Bun workspace globs match. Swift stays in `Packages/Core`. Those paths are distinct on Linux and collide on case-insensitive disks.

## Run

From the repository root:

```bash
bun install
bun run electron
```

Headless smoke (quits after the app is ready):

```bash
bun run electron:smoke
```
