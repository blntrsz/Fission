import { spawn, type IPty } from "node-pty";
import { createServer, type Socket } from "node:net";
import { existsSync, unlinkSync } from "node:fs";
import { homedir } from "node:os";
import {
  appendReplay,
  decodeLines,
  encodeMessage,
  executionProtocolVersion,
  type ExecutionRequest,
  type ExecutionResponse
} from "@shared/executionProtocol";

type HostedTerminal = {
  id: string;
  pty: IPty;
  replay: Buffer;
  replayStartOffset: number;
  nextOutputOffset: number;
  startedAt: number;
  clients: Set<Socket>;
  exitStatus: { code: number; runtime: number } | null;
  removeWhenExited: boolean;
};

const terminals = new Map<string, HostedTerminal>();
const clients = new Set<Socket>();

export function runExecutionDaemon(socketPath: string): void {
  if (existsSync(socketPath)) {
    try {
      unlinkSync(socketPath);
    } catch {
      process.exit(0);
    }
  }

  const server = createServer((socket) => {
    clients.add(socket);
    let buffer = Buffer.alloc(0);
    let sessionID: string | null = null;
    socket.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
        const decoded = decodeLines(buffer);
        buffer = Buffer.from(decoded.rest);
      for (const line of decoded.messages) {
        try {
          const request = JSON.parse(line) as ExecutionRequest;
          sessionID = handle(request, socket, sessionID);
        } catch {
          send(
            {
              version: executionProtocolVersion,
              kind: "failure",
              sessionID: sessionID ?? "00000000-0000-0000-0000-000000000000",
              message: "Malformed request"
            },
            socket
          );
        }
      }
    });
    socket.on("close", () => {
      clients.delete(socket);
      if (sessionID) {
        terminals.get(sessionID)?.clients.delete(socket);
      }
    });
    socket.on("error", () => {
      clients.delete(socket);
    });
  });

  server.listen(socketPath, () => {
    // Socket is ready for the GUI client.
  });
  server.on("error", () => {
    process.exit(0);
  });
}

function handle(request: ExecutionRequest, socket: Socket, currentSession: string | null): string | null {
  if (request.version !== executionProtocolVersion) {
    sendFailure("Unsupported protocol version", request.sessionID, socket);
    return currentSession;
  }
  switch (request.kind) {
    case "attachOrCreate":
      return attachOrCreate(request, socket, currentSession);
    case "input": {
      if (currentSession !== request.sessionID) {
        return currentSession;
      }
      const terminal = terminals.get(request.sessionID);
      if (!terminal || terminal.exitStatus || !request.data) {
        return currentSession;
      }
      terminal.pty.write(Buffer.from(request.data, "base64").toString("utf8"));
      return currentSession;
    }
    case "resize": {
      if (currentSession !== request.sessionID) {
        return currentSession;
      }
      const terminal = terminals.get(request.sessionID);
      const cols = Math.floor(Number(request.columns));
      const rows = Math.floor(Number(request.rows));
      if (
        !terminal ||
        terminal.exitStatus ||
        !Number.isFinite(cols) ||
        !Number.isFinite(rows) ||
        cols < 2 ||
        rows < 1
      ) {
        return currentSession;
      }
      try {
        terminal.pty.resize(cols, rows);
      } catch {
        return currentSession;
      }
      return currentSession;
    }
    case "terminate": {
      const terminal = terminals.get(request.sessionID);
      if (!terminal) {
        return currentSession;
      }
      terminal.removeWhenExited = true;
      if (terminal.exitStatus) {
        terminals.delete(terminal.id);
      } else {
        terminal.pty.kill("SIGHUP");
      }
      return currentSession;
    }
    default:
      return currentSession;
  }
}

function attachOrCreate(
  request: ExecutionRequest,
  socket: Socket,
  currentSession: string | null
): string {
  if (currentSession) {
    terminals.get(currentSession)?.clients.delete(socket);
  }

  let terminal = terminals.get(request.sessionID);
  if (!terminal) {
    if (!request.threadID) {
      sendFailure("A new terminal requires a Thread ID", request.sessionID, socket);
      return currentSession ?? request.sessionID;
    }
    terminal = spawnTerminal(request);
    terminals.set(terminal.id, terminal);
  }

  terminal.clients.add(socket);
  const requestedOffset = request.resumeOffset ?? 0;
  const replayOffset =
    requestedOffset > terminal.nextOutputOffset
      ? terminal.replayStartOffset
      : Math.min(Math.max(requestedOffset, terminal.replayStartOffset), terminal.nextOutputOffset);
  const replayIndex = replayOffset - terminal.replayStartOffset;
  send(
    {
      version: executionProtocolVersion,
      kind: "attached",
      sessionID: terminal.id,
      data: terminal.replay.subarray(replayIndex).toString("base64"),
      offset: replayOffset
    },
    socket
  );
  if (terminal.exitStatus) {
    send(
      {
        version: executionProtocolVersion,
        kind: "exited",
        sessionID: terminal.id,
        exitCode: terminal.exitStatus.code,
        runtimeMilliseconds: terminal.exitStatus.runtime
      },
      socket
    );
  }
  return terminal.id;
}

function spawnTerminal(request: ExecutionRequest): HostedTerminal {
  const shell = process.env.SHELL ?? (process.platform === "win32" ? "powershell.exe" : "/bin/bash");
  const pty = spawn(shell, ["-l"], {
    name: "xterm-256color",
    cols: 80,
    rows: 24,
    cwd: request.workingDirectory && request.workingDirectory.length > 0 ? request.workingDirectory : homedir(),
    env: {
      ...process.env,
      ...request.environment,
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      TERM_PROGRAM: "Fission"
    }
  });
  const terminal: HostedTerminal = {
    id: request.sessionID,
    pty,
    replay: Buffer.alloc(0),
    replayStartOffset: 0,
    nextOutputOffset: 0,
    startedAt: Date.now(),
    clients: new Set(),
    exitStatus: null,
    removeWhenExited: false
  };
  pty.onData((data) => {
    const chunk = Buffer.from(data, "utf8");
    const outputOffset = terminal.nextOutputOffset;
    const next = appendReplay(terminal.replay, terminal.replayStartOffset, chunk);
    terminal.replay = next.replay;
    terminal.replayStartOffset = next.startOffset;
    terminal.nextOutputOffset = next.nextOffset;
    broadcast(
      {
        version: executionProtocolVersion,
        kind: "output",
        sessionID: terminal.id,
        data: chunk.toString("base64"),
        offset: outputOffset
      },
      terminal
    );
  });
  pty.onExit(({ exitCode }) => {
    terminal.exitStatus = { code: exitCode, runtime: Math.max(0, Date.now() - terminal.startedAt) };
    broadcast(
      {
        version: executionProtocolVersion,
        kind: "exited",
        sessionID: terminal.id,
        exitCode: terminal.exitStatus.code,
        runtimeMilliseconds: terminal.exitStatus.runtime
      },
      terminal
    );
    if (terminal.removeWhenExited) {
      terminals.delete(terminal.id);
    }
  });
  if (request.startupCommand) {
    pty.write(`${request.startupCommand}\n`);
  }
  return terminal;
}

function broadcast(response: ExecutionResponse, terminal: HostedTerminal): void {
  for (const client of terminal.clients) {
    send(response, client);
  }
}

function sendFailure(message: string, sessionID: string, socket: Socket): void {
  send(
    {
      version: executionProtocolVersion,
      kind: "failure",
      sessionID,
      message
    },
    socket
  );
}

function send(response: ExecutionResponse, socket: Socket): void {
  try {
    socket.write(encodeMessage(response));
  } catch {
    return;
  }
}

const socketIndex = process.argv.indexOf("--socket");
if (process.argv[1]?.includes("executionDaemon") || process.env.FISSION_EXECUTION_DAEMON === "1") {
  const socketPath = socketIndex >= 0 ? process.argv[socketIndex + 1] : process.env.FISSION_EXECUTION_SOCKET;
  if (!socketPath) {
    process.stderr.write("FissionExecution: missing --socket\n");
    process.exit(1);
  }
  runExecutionDaemon(socketPath);
}
