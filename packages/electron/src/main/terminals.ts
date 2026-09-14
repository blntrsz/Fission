import { spawn, type IPty } from "node-pty";
import { homedir } from "node:os";
import type { BrowserWindow } from "electron";

export type SessionSpec = {
  tabID: string;
  cwd: string | null;
  startupCommand: string | null;
  environment: Record<string, string>;
};

export class TerminalManager {
  private readonly sessions = new Map<string, IPty>();
  private window: BrowserWindow | null = null;

  attach(window: BrowserWindow): void {
    this.window = window;
  }

  create(spec: SessionSpec): void {
    if (this.sessions.has(spec.tabID)) {
      return;
    }
    const shell = process.env.SHELL ?? (process.platform === "win32" ? "powershell.exe" : "/bin/bash");
    const pty = spawn(shell, ["-l"], {
      name: "xterm-256color",
      cols: 120,
      rows: 32,
      cwd: spec.cwd && spec.cwd.length > 0 ? spec.cwd : homedir(),
      env: {
        ...process.env,
        ...spec.environment,
        TERM: "xterm-256color",
        COLORTERM: "truecolor"
      }
    });
    pty.onData((data) => {
      this.window?.webContents.send("terminal:data", spec.tabID, data);
    });
    pty.onExit(() => {
      this.sessions.delete(spec.tabID);
      this.window?.webContents.send("terminal:exit", spec.tabID);
    });
    this.sessions.set(spec.tabID, pty);
    if (spec.startupCommand) {
      pty.write(`${spec.startupCommand}\n`);
    }
  }

  write(tabID: string, data: string): void {
    this.sessions.get(tabID)?.write(data);
  }

  resize(tabID: string, cols: number, rows: number): void {
    this.sessions.get(tabID)?.resize(Math.max(cols, 2), Math.max(rows, 1));
  }

  terminate(tabIDs: string[]): void {
    for (const tabID of tabIDs) {
      const session = this.sessions.get(tabID);
      if (!session) {
        continue;
      }
      session.kill();
      this.sessions.delete(tabID);
    }
  }

  terminateAll(): void {
    this.terminate([...this.sessions.keys()]);
  }
}
