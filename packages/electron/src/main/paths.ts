import { app } from "electron";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export function dataDirectory(): string {
  const override = process.env.FISSION_DATA_DIR;
  if (override && override.startsWith("/")) {
    mkdirSync(override, { recursive: true });
    return override;
  }
  let directory: string;
  try {
    directory = process.platform === "darwin" ? app.getPath("appData") : app.getPath("userData");
  } catch {
    directory = process.platform === "darwin"
      ? join(homedir(), "Library", "Application Support")
      : join(homedir(), ".config", "Fission");
  }
  mkdirSync(directory, { recursive: true });
  return directory;
}

export function databasePath(): string {
  if (process.env.FISSION_DATABASE_PATH) {
    return process.env.FISSION_DATABASE_PATH;
  }
  return join(dataDirectory(), "fission.sqlite");
}

export function remoteMachinesPath(): string {
  if (process.env.FISSION_REMOTE_MACHINES_PATH) {
    return process.env.FISSION_REMOTE_MACHINES_PATH;
  }
  return join(dataDirectory(), "fission-remote-machines.json");
}

export function workspaceStatePath(): string {
  return join(dataDirectory(), "fission-terminal-workspaces.json");
}

export function recentProjectsPath(): string {
  return join(dataDirectory(), "fission-recent-projects.json");
}

export function settingsPath(): string {
  return join(dataDirectory(), "fission-settings.json");
}

export function homePath(): string {
  return homedir();
}
