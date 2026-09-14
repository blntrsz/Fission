import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createThreadInput, ThreadRepository } from "@shared/threadRepository";
import { currentBranch } from "@shared/gitBranch";
import * as gitWorktreeBranch from "@shared/gitWorktreeBranch";
import { createIsolate, removeIsolate } from "@shared/projectIsolator";
import { loginShellCommand, normalizedDirectory } from "@shared/moshCommand";
import {
  isSettled,
  nowEpochSeconds,
  projectDisplayName,
  type AgentThread,
  type NewThreadRequest
} from "@shared/types";
import { isValidMachine, machineTarget, projectNameFromPath } from "@shared/remoteMachine";
import type { RemoteMachineStore } from "./remoteStore";

export class ThreadService {
  private didLoad = false;

  constructor(
    readonly repository: ThreadRepository,
    private readonly remotes: RemoteMachineStore
  ) {}

  static async create(databasePath: string, remotes: RemoteMachineStore): Promise<ThreadService> {
    return new ThreadService(await ThreadRepository.open(databasePath), remotes);
  }

  load(): AgentThread[] {
    if (!this.didLoad) {
      if (this.repository.list().length === 0) {
        this.repository.create(createThreadInput({ title: "Explore Fission" }));
      }
      this.didLoad = true;
    }
    return this.repository.list();
  }

  list(): AgentThread[] {
    return this.repository.list();
  }

  create(request: NewThreadRequest): AgentThread {
    if (request.kind === "local") {
      return this.createLocal(request.directory, request.createIsolate, request.branchName);
    }
    return this.createRemote(request.machineID, request.projectPath);
  }

  rename(threadID: string, title: string): AgentThread[] {
    const thread = this.repository.thread(threadID);
    const trimmed = title.trim();
    if (!thread || trimmed.length === 0 || trimmed === thread.title) {
      return this.list();
    }
    this.repository.update({
      ...thread,
      title: trimmed,
      updatedAt: nowEpochSeconds()
    });
    return this.list();
  }

  settle(threadID: string): AgentThread[] {
    this.removeIsolates([threadID]);
    return this.transition(threadID, "settled");
  }

  reopen(threadID: string): AgentThread[] {
    return this.transition(threadID, "active");
  }

  delete(ids: string[]): AgentThread[] {
    this.removeIsolates(ids);
    for (const id of ids) {
      this.repository.delete(id);
    }
    return this.list();
  }

  reorderActive(ids: string[]): AgentThread[] {
    const activeIDs = this.list()
      .filter((thread) => !isSettled(thread))
      .map((thread) => thread.id);
    if (ids.length !== activeIDs.length || !sameSet(ids, activeIDs)) {
      return this.list();
    }
    this.repository.reorder(ids);
    return this.list();
  }

  private createLocal(
    workingDirectory: string,
    createInIsolate: boolean,
    branchName: string | null
  ): AgentThread {
    const projectName = projectDisplayName({
      projectName: null,
      workingDirectory
    });
    const resolvedWorkingDirectory = createInIsolate
      ? createIsolate({
          workingDirectory,
          requestedBranch: gitWorktreeBranch.normalized(branchName)
        })
      : workingDirectory;
    const title = currentBranch(resolvedWorkingDirectory) ?? "local";
    return this.repository.create(
      createThreadInput({
        title,
        workingDirectory: resolvedWorkingDirectory,
        projectName: projectName.length === 0 ? null : projectName
      })
    );
  }

  private createRemote(machineID: string, projectPath: string): AgentThread {
    const machine = this.remotes.machine(machineID);
    if (!machine || !isValidMachine(machine)) {
      throw new Error("The remote machine needs a host.");
    }
    const directory = normalizedDirectory(projectPath);
    if (!directory) {
      throw new Error("The remote Thread needs a project path.");
    }
    const remembered = this.remotes.upsert({
      ...machine,
      projectPath: directory
    });
    if (!remembered) {
      throw new Error("The remote machine needs a host.");
    }
    return this.repository.create(
      createThreadInput({
        title: machineTarget(remembered),
        workingDirectory: directory,
        projectName: projectNameFromPath(directory) ?? (remembered.name || machineTarget(remembered)),
        remoteMachineID: remembered.id,
        remoteCommand: loginShellCommand(
          machineTarget(remembered),
          remembered.sshPort,
          directory
        )
      })
    );
  }

  private transition(threadID: string, status: AgentThread["status"]): AgentThread[] {
    const thread = this.repository.thread(threadID);
    if (!thread) {
      return this.list();
    }
    this.repository.update({
      ...thread,
      status,
      updatedAt: nowEpochSeconds()
    });
    return this.list();
  }

  private removeIsolates(ids: string[]): void {
    for (const id of ids) {
      const thread = this.repository.thread(id);
      if (!thread || thread.remoteCommand || thread.remoteMachineID) {
        continue;
      }
      removeIsolate(thread.workingDirectory);
    }
  }
}

export class RecentProjectStore {
  constructor(private readonly filePath: string) {}

  load(): string[] {
    const saved = this.read();
    if (saved.length === 0) {
      const home = homedir();
      const projects = join(home, "Projects");
      return existsSync(projects) ? [projects, home] : [home];
    }
    return saved;
  }

  record(path: string): string[] {
    const paths = [path, ...this.load().filter((item) => item !== path)].slice(0, 9);
    mkdirSync(dirname(this.filePath), { recursive: true });
    writeFileSync(this.filePath, JSON.stringify(paths));
    return paths;
  }

  private read(): string[] {
    if (!existsSync(this.filePath)) {
      return [];
    }
    try {
      const parsed: unknown = JSON.parse(readFileSync(this.filePath, "utf8"));
      return Array.isArray(parsed) ? parsed.filter((item) => typeof item === "string") : [];
    } catch {
      return [];
    }
  }
}

function sameSet(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((id) => right.includes(id));
}
