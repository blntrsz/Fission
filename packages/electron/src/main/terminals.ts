import { spawn as spawnProcess } from "node:child_process";
import { createConnection, type Socket } from "node:net";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { BrowserWindow } from "electron";
import {
  decodeLines,
  defaultSocketPath,
  encodeMessage,
  executionProtocolVersion,
  type ExecutionRequest,
  type ExecutionResponse
} from "@shared/executionProtocol";
import { dataDirectory } from "./paths";

export type SessionSpec = {
  tabID: string;
  threadID: string;
  cwd: string | null;
  startupCommand: string | null;
  environment: Record<string, string>;
};

type ClientSession = {
  spec: SessionSpec;
  socket: Socket | null;
  resumeOffset: number;
  connecting: boolean;
};

export class TerminalManager {
  private readonly sessions = new Map<string, ClientSession>();
  private window: BrowserWindow | null = null;
  private readonly socketPath = process.env.FISSION_EXECUTION_SOCKET ??
    defaultSocketPath(dataDirectory(), process.getuid?.() ?? 0);

  attach(window: BrowserWindow): void {
    this.window = window;
  }

  async create(spec: SessionSpec): Promise<void> {
    const existing = this.sessions.get(spec.tabID);
    if (existing) {
      existing.spec = spec;
      if (!existing.socket) {
        await this.connect(existing);
      }
      return;
    }
    const session: ClientSession = {
      spec,
      socket: null,
      resumeOffset: 0,
      connecting: false
    };
    this.sessions.set(spec.tabID, session);
    await this.connect(session);
  }

  write(tabID: string, data: string): void {
    const session = this.sessions.get(tabID);
    if (!session?.socket) {
      return;
    }
    this.send(session, {
      version: executionProtocolVersion,
      kind: "input",
      sessionID: tabID,
      data: Buffer.from(data, "utf8").toString("base64")
    });
  }

  resize(tabID: string, cols: number, rows: number): void {
    const nextCols = Math.floor(Number(cols));
    const nextRows = Math.floor(Number(rows));
    if (!Number.isFinite(nextCols) || !Number.isFinite(nextRows) || nextCols < 2 || nextRows < 1) {
      return;
    }
    const session = this.sessions.get(tabID);
    if (!session?.socket) {
      return;
    }
    this.send(session, {
      version: executionProtocolVersion,
      kind: "resize",
      sessionID: tabID,
      columns: nextCols,
      rows: nextRows
    });
  }

  terminate(tabIDs: string[]): void {
    for (const tabID of tabIDs) {
      const session = this.sessions.get(tabID);
      if (session?.socket) {
        this.send(session, {
          version: executionProtocolVersion,
          kind: "terminate",
          sessionID: tabID
        });
        session.socket.destroy();
      }
      this.sessions.delete(tabID);
    }
  }

  detach(): void {
    for (const session of this.sessions.values()) {
      session.socket?.destroy();
      session.socket = null;
    }
  }

  private async connect(session: ClientSession): Promise<void> {
    if (session.connecting) {
      return;
    }
    session.connecting = true;
    try {
      await ensureDaemon(this.socketPath);
      const socket = await connectSocket(this.socketPath);
      session.socket = socket;
      let buffer = Buffer.alloc(0);
      socket.on("data", (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        const decoded = decodeLines(buffer);
        buffer = Buffer.from(decoded.rest);
        for (const line of decoded.messages) {
          try {
            this.handle(JSON.parse(line) as ExecutionResponse, session);
          } catch {
            continue;
          }
        }
      });
      socket.on("close", () => {
        if (session.socket === socket) {
          session.socket = null;
        }
      });
      socket.on("error", () => {
        if (session.socket === socket) {
          session.socket = null;
        }
      });
      this.send(session, {
        version: executionProtocolVersion,
        kind: "attachOrCreate",
        sessionID: session.spec.tabID,
        threadID: session.spec.threadID,
        workingDirectory: session.spec.cwd,
        startupCommand: session.spec.startupCommand,
        environment: session.spec.environment,
        resumeOffset: session.resumeOffset
      });
    } finally {
      session.connecting = false;
    }
  }

  private handle(response: ExecutionResponse, session: ClientSession): void {
    if (response.version !== executionProtocolVersion) {
      return;
    }
    switch (response.kind) {
      case "attached":
      case "output": {
        const bytes = response.data ? Buffer.from(response.data, "base64") : Buffer.alloc(0);
        if (typeof response.offset === "number") {
          session.resumeOffset = response.offset + bytes.length;
        } else {
          session.resumeOffset += bytes.length;
        }
        if (bytes.length > 0) {
          this.window?.webContents.send("terminal:data", session.spec.tabID, bytes.toString("utf8"));
        }
        break;
      }
      case "exited":
        this.window?.webContents.send("terminal:exit", session.spec.tabID);
        break;
      case "failure":
        if (response.message) {
          this.window?.webContents.send(
            "terminal:data",
            session.spec.tabID,
            `\r\n[Fission execution error: ${response.message}]\r\n`
          );
        }
        break;
      default:
        break;
    }
  }

  private send(session: ClientSession, request: ExecutionRequest): void {
    try {
      session.socket?.write(encodeMessage(request));
    } catch {
      return;
    }
  }
}

function daemonScript(): string {
  return fileURLToPath(new URL("./executionDaemon.js", import.meta.url));
}

async function ensureDaemon(socketPath: string): Promise<void> {
  if (await canConnect(socketPath)) {
    return;
  }
  const script = daemonScript();
  spawnProcess(process.execPath, [script, "--socket", socketPath], {
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: "1",
      FISSION_EXECUTION_DAEMON: "1"
    },
    detached: true,
    stdio: "ignore"
  }).unref();

  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    if (await canConnect(socketPath)) {
      return;
    }
    await delay(50);
  }
  throw new Error("Fission execution daemon did not start.");
}

function canConnect(socketPath: string): Promise<boolean> {
  if (!existsSync(socketPath)) {
    return Promise.resolve(false);
  }
  return new Promise((resolve) => {
    const socket = createConnection(socketPath);
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
}

function connectSocket(socketPath: string): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const socket = createConnection(socketPath);
    socket.once("connect", () => resolve(socket));
    socket.once("error", reject);
  });
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}
