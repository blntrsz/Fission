export type ThreadStatus = "active" | "settled" | "completed" | "failed" | "cancelled";

export type AgentActivityState = "idle" | "running" | "blocked" | "finished";

export type AgentThread = {
  id: string;
  title: string;
  status: ThreadStatus;
  workingDirectory: string | null;
  projectName: string | null;
  remoteMachineID: string | null;
  remoteCommand: string | null;
  createdAt: number;
  updatedAt: number;
  sortIndex: number;
};

export type RemoteMachine = {
  id: string;
  name: string;
  username: string;
  host: string;
  sshPort: number | null;
  projectPath: string | null;
};

export type ProjectPath = {
  path: string;
  displayPath: string;
  name: string;
};

export type TerminalTabRecord = {
  id: string;
  number: number;
  title: string;
  isSelected: boolean;
};

export type NewThreadRequest =
  | {
      kind: "local";
      directory: string;
      createIsolate: boolean;
      branchName: string | null;
    }
  | {
      kind: "remote";
      machineID: string;
      projectPath: string;
    };

export function isSettled(thread: AgentThread): boolean {
  return thread.status === "settled";
}

export function isRemoteThread(thread: AgentThread): boolean {
  return thread.remoteCommand != null || thread.remoteMachineID != null;
}

export function projectDisplayName(thread: Pick<AgentThread, "projectName" | "workingDirectory">): string {
  if (thread.projectName && thread.projectName.length > 0) {
    return thread.projectName;
  }
  if (!thread.workingDirectory) {
    return "No Project";
  }
  const name = lastPathComponent(thread.workingDirectory);
  return name.length === 0 ? thread.workingDirectory : name;
}

export function lastPathComponent(path: string): string {
  const trimmed = path.replace(/\/+$/, "");
  const slash = trimmed.lastIndexOf("/");
  return slash === -1 ? trimmed : trimmed.slice(slash + 1);
}

export function newThreadId(): string {
  return crypto.randomUUID().toUpperCase();
}

export function nowEpochSeconds(): number {
  return Date.now() / 1000;
}
