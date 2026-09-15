import { createSocket } from "node:dgram";
import { copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentActivityState, AgentThread } from "@shared/types";
import type { BrowserWindow } from "electron";

type SessionID = string;

type Activity = {
  state: AgentActivityState;
  reportedState: AgentActivityState;
  sequence: number;
};

export class AgentActivityService {
  readonly token = crypto.randomUUID();
  port = 0;
  private readonly socket = createSocket("udp4");
  private readonly activities = new Map<string, Map<string, Activity>>();
  private readonly threadsWithAgentRun = new Set<string>();
  private readonly activeSessions = new Set<SessionID>();
  private threadMetadata = new Map<string, Pick<AgentThread, "title" | "workingDirectory" | "projectName">>();
  private selectedThreadID: string | null = null;
  private isAppActive = false;
  notifyWhenFinished = false;
  tabIDsForThread: (threadID: string) => string[] = () => [];
  private window: BrowserWindow | null = null;

  constructor(
    private readonly createNotification: (title: string, body: string, threadID: string) => void
  ) {
    this.socket.on("message", (message) => this.accept(message));
    this.socket.bind(0, "127.0.0.1", () => {
      const address = this.socket.address();
      this.port = typeof address === "string" ? 0 : address.port;
    });
  }

  attach(window: BrowserWindow): void {
    this.window = window;
  }

  environment(threadID: string, tabID: string): Record<string, string> {
    this.activeSessions.add(sessionKey(threadID, tabID));
    return {
      FISSION_AGENT_PORT: String(this.port),
      FISSION_AGENT_TOKEN: this.token,
      FISSION_THREAD_ID: threadID,
      FISSION_TAB_ID: tabID
    };
  }

  states(threadID: string, tabIDs: string[]): AgentActivityState[] {
    if (!this.threadsWithAgentRun.has(threadID)) {
      return [];
    }
    const activities = this.activities.get(threadID) ?? new Map();
    return tabIDs.flatMap((tabID) => {
      const activity = activities.get(tabID);
      return activity ? [activity.state] : [];
    }).slice(0, 10);
  }

  snapshot(tabIDsForThread?: (threadID: string) => string[]): Record<string, AgentActivityState[]> {
    const result: Record<string, AgentActivityState[]> = {};
    for (const threadID of this.threadsWithAgentRun) {
      const tabIDs = tabIDsForThread?.(threadID) ?? [...(this.activities.get(threadID)?.keys() ?? [])];
      result[threadID] = this.states(threadID, tabIDs);
    }
    return result;
  }

  updateAttention(selectedThreadID: string | null, isAppActive: boolean): void {
    this.selectedThreadID = selectedThreadID;
    this.isAppActive = isAppActive;
    if (selectedThreadID) {
      this.acknowledgeFinished(selectedThreadID);
    }
    this.publish();
  }

  synchronizeThreads(threads: AgentThread[]): void {
    this.threadMetadata = new Map(
      threads.map((thread) => [
        thread.id,
        {
          title: thread.title,
          workingDirectory: thread.workingDirectory,
          projectName: thread.projectName
        }
      ])
    );
  }

  forget(threadID: string, tabID?: string): void {
    if (tabID) {
      this.activeSessions.delete(sessionKey(threadID, tabID));
      this.activities.get(threadID)?.delete(tabID);
      if ((this.activities.get(threadID)?.size ?? 0) === 0) {
        this.activities.delete(threadID);
        this.threadsWithAgentRun.delete(threadID);
      }
    } else {
      for (const key of [...this.activeSessions]) {
        if (key.startsWith(`${threadID}:`)) {
          this.activeSessions.delete(key);
        }
      }
      this.activities.delete(threadID);
      this.threadsWithAgentRun.delete(threadID);
      this.threadMetadata.delete(threadID);
    }
    this.publish();
  }

  close(): void {
    this.socket.close();
  }

  private accept(data: Buffer): void {
    try {
      const report = JSON.parse(data.toString("utf8")) as {
        version: number;
        token: string;
        threadId: string;
        tabId: string;
        agent: string;
        state: AgentActivityState;
        sequence: number;
      };
      if (
        report.version !== 1 ||
        report.token !== this.token ||
        report.agent !== "pi" ||
        !this.activeSessions.has(sessionKey(report.threadId, report.tabId))
      ) {
        return;
      }
      const previous = this.activities.get(report.threadId)?.get(report.tabId);
      if (previous && report.sequence <= previous.sequence) {
        return;
      }
      if (report.state !== "idle") {
        this.threadsWithAgentRun.add(report.threadId);
      }
      const threadActivities = this.activities.get(report.threadId) ?? new Map();
      threadActivities.set(report.tabId, {
        state: report.state,
        reportedState: report.state,
        sequence: report.sequence
      });
      this.activities.set(report.threadId, threadActivities);
      const enteredFinished = report.state === "finished" && previous?.reportedState !== "finished";
      if (
        enteredFinished &&
        !(this.isAppActive && this.selectedThreadID === report.threadId) &&
        this.notifyWhenFinished
      ) {
        const metadata = this.threadMetadata.get(report.threadId);
        this.createNotification(
          `"${metadata?.title ?? "Thread"}" finished`,
          metadata?.projectName ?? projectNameFromPath(metadata?.workingDirectory),
          report.threadId
        );
      }
      if (this.selectedThreadID === report.threadId) {
        this.acknowledgeFinished(report.threadId);
      }
      this.publish();
    } catch {
      return;
    }
  }

  private acknowledgeFinished(threadID: string): void {
    const threadActivities = this.activities.get(threadID);
    if (!threadActivities) {
      return;
    }
    for (const [tabID, activity] of threadActivities) {
      if (activity.state === "finished") {
        threadActivities.set(tabID, { ...activity, state: "idle" });
      }
    }
  }

  private publish(): void {
    this.window?.webContents.send("activity:changed", this.snapshot(this.tabIDsForThread));
  }
}

export function installPiExtension(): void {
  const source = fileURLToPath(
    new URL("../../resources/fission-pi-agent-state.ts", import.meta.url)
  );
  if (!existsSync(source)) {
    return;
  }
  const agentDirectory = process.env.PI_CODING_AGENT_DIR?.startsWith("/")
    ? process.env.PI_CODING_AGENT_DIR
    : join(homedir(), ".pi", "agent");
  const destination = join(agentDirectory, "extensions", "fission-agent-state.ts");
  try {
    if (existsSync(destination) && readFileSync(destination).equals(readFileSync(source))) {
      return;
    }
    mkdirSync(dirname(destination), { recursive: true });
    copyFileSync(source, destination);
  } catch {
    return;
  }
}

function sessionKey(threadID: string, tabID: string): SessionID {
  return `${threadID}:${tabID}`;
}

function projectNameFromPath(workingDirectory: string | null | undefined): string {
  if (!workingDirectory) {
    return "";
  }
  const trimmed = workingDirectory.replace(/\/+$/, "");
  const slash = trimmed.lastIndexOf("/");
  return slash === -1 ? trimmed : trimmed.slice(slash + 1);
}
