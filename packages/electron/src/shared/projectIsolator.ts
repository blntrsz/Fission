import { existsSync, mkdirSync, rmSync, statSync, cpSync, constants } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { execFileSync } from "node:child_process";
import * as gitWorktreeBranch from "./gitWorktreeBranch";

export class IsolateError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IsolateError";
  }
}

export function defaultIsolateRoot(): string {
  return join(homedir(), ".fission", "worktrees");
}

export function createIsolate(input: {
  workingDirectory: string;
  isolateRoot?: string;
  requestedBranch?: string | null;
  makeIdentifier?: () => string;
}): string {
  const isolateRoot = resolve(input.isolateRoot ?? defaultIsolateRoot());
  const selectedDirectory = resolve(input.workingDirectory);
  const sourceRoot = resolvedSourceRoot(selectedDirectory);
  const relativePath = relativeSubpath(selectedDirectory, sourceRoot);
  const projectName = basename(sourceRoot);
  if (projectName.length === 0) {
    throw new IsolateError("The selected project folder is invalid.");
  }

  const repositoryIsolates = join(isolateRoot, projectName);
  const resolved = resolveBranchAndIsolate({
    requestedBranch: input.requestedBranch ?? null,
    sourceRoot,
    repositoryIsolates,
    projectName,
    makeIdentifier: input.makeIdentifier ?? randomIdentifier
  });

  mkdirSync(resolved.isolateDirectory, { recursive: true });
  try {
    awaitTestDelayIfRequested();
    cloneDirectory(sourceRoot, resolved.destination);
    createBranchIfNeeded(resolved.destination, resolved.branch);
  } catch (error) {
    rmSync(resolved.isolateDirectory, { recursive: true, force: true });
    throw error;
  }

  if (relativePath.length === 0) {
    return resolved.destination;
  }
  return join(resolved.destination, relativePath);
}

export function removeIsolate(workingDirectory: string | null, isolateRoot?: string): void {
  const isolateDirectory = isolateDirectoryFor(
    workingDirectory,
    resolve(isolateRoot ?? defaultIsolateRoot())
  );
  if (!isolateDirectory) {
    return;
  }
  rmSync(isolateDirectory, { recursive: true, force: true });
}

export function isolateDirectoryFor(
  workingDirectory: string | null | undefined,
  isolateRoot: string
): string | null {
  if (!workingDirectory) {
    return null;
  }
  const cwd = resolve(workingDirectory);
  const root = resolve(isolateRoot);
  const prefix = root.endsWith("/") ? root : `${root}/`;
  if (!cwd.startsWith(prefix)) {
    return null;
  }
  const parts = cwd.slice(prefix.length).split("/").filter(Boolean);
  const project = parts[0];
  if (!project) {
    return null;
  }
  const leafIndex = parts.findIndex((part, index) => index > 0 && part === project);
  if (leafIndex === -1) {
    return null;
  }
  return join(root, ...parts.slice(0, leafIndex));
}

function resolveBranchAndIsolate(input: {
  requestedBranch: string | null;
  sourceRoot: string;
  repositoryIsolates: string;
  projectName: string;
  makeIdentifier: () => string;
}): { branch: string; isolateDirectory: string; destination: string } {
  if (input.requestedBranch) {
    if (!gitWorktreeBranch.isValid(input.requestedBranch)) {
      throw new IsolateError("Enter a valid Git branch name.");
    }
    const isolateDirectory = join(input.repositoryIsolates, input.requestedBranch);
    if (existsSync(isolateDirectory)) {
      throw new IsolateError(
        `An isolated workspace for "${input.requestedBranch}" already exists.`
      );
    }
    if (sourceHasGitBranch(input.requestedBranch, input.sourceRoot)) {
      throw new IsolateError(`A branch named "${input.requestedBranch}" already exists.`);
    }
    return {
      branch: input.requestedBranch,
      isolateDirectory,
      destination: join(isolateDirectory, input.projectName)
    };
  }

  let branch = "";
  let isolateDirectory = input.repositoryIsolates;
  do {
    branch = `fission-${input.makeIdentifier()}`;
    isolateDirectory = join(input.repositoryIsolates, branch);
  } while (existsSync(isolateDirectory) || sourceHasGitBranch(branch, input.sourceRoot));

  return {
    branch,
    isolateDirectory,
    destination: join(isolateDirectory, input.projectName)
  };
}

function resolvedSourceRoot(selectedDirectory: string): string {
  const repository = gitToplevel(selectedDirectory);
  if (!repository) {
    return selectedDirectory;
  }
  const git = join(repository, ".git");
  if (!existsSync(git)) {
    throw new IsolateError("The selected Git repository could not be read.");
  }
  if (!statSync(git).isDirectory()) {
    throw new IsolateError(
      "Linked Git worktrees cannot be isolated. Choose the main repository folder."
    );
  }
  return repository;
}

function relativeSubpath(selectedDirectory: string, sourceRoot: string): string {
  const value = relative(sourceRoot, selectedDirectory);
  return value === "." ? "" : value;
}

function gitToplevel(directory: string): string | null {
  try {
    return runGit(["-C", directory, "rev-parse", "--show-toplevel"]);
  } catch {
    return null;
  }
}

function sourceHasGitBranch(branch: string, sourceRoot: string): boolean {
  try {
    const listed = runGit(["-C", sourceRoot, "branch", "--list", "--", branch]);
    return listed.length > 0;
  } catch {
    return false;
  }
}

function createBranchIfNeeded(destination: string, branch: string): void {
  const git = join(destination, ".git");
  if (!existsSync(git) || !statSync(git).isDirectory()) {
    return;
  }
  try {
    const head = runGit(["-C", destination, "rev-parse", "--verify", "HEAD"]);
    if (head.length === 0) {
      return;
    }
    runGit(["-C", destination, "switch", "-c", branch]);
  } catch {
    return;
  }
}

function cloneDirectory(source: string, destination: string): void {
  mkdirSync(dirname(destination), { recursive: true });
  try {
    if (process.platform === "darwin") {
      assertCopyOnWriteAvailable(source, dirname(destination));
      try {
        cpSync(source, destination, {
          recursive: true,
          verbatimSymlinks: true,
          mode: copyOnWriteMode()
        });
        return;
      } catch (error) {
        if (error instanceof IsolateError) {
          throw error;
        }
        throw new IsolateError(
          "The project must be on APFS on the same volume as ~/.fission/worktrees."
        );
      }
    }
    cpSync(source, destination, { recursive: true, verbatimSymlinks: true });
  } catch (error) {
    if (error instanceof IsolateError) {
      throw error;
    }
    throw new IsolateError("The project folder could not be copied.");
  }
}

function copyOnWriteMode(): number {
  const flags = constants as unknown as Record<string, number | undefined>;
  return flags.COPYFILE_FICLONE_FORCE ?? flags.COPYFILE_FICLONE ?? 0;
}

function assertCopyOnWriteAvailable(source: string, destinationParent: string): void {
  try {
    const sourceDevice = statSync(source).dev;
    mkdirSync(destinationParent, { recursive: true });
    const destinationDevice = statSync(destinationParent).dev;
    if (sourceDevice !== destinationDevice) {
      throw new IsolateError(
        "The project must be on APFS on the same volume as ~/.fission/worktrees."
      );
    }
  } catch (error) {
    if (error instanceof IsolateError) {
      throw error;
    }
  }
}

function awaitTestDelayIfRequested(): void {
  const raw = process.env.FISSION_ISOLATE_DELAY_MS;
  if (!raw) {
    return;
  }
  const milliseconds = Number.parseInt(raw, 10);
  if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
    return;
  }
  const capped = Math.min(milliseconds, 10_000);
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, capped);
}

function randomIdentifier(): string {
  const characters = "abcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  for (let index = 0; index < 6; index += 1) {
    result += characters[Math.floor(Math.random() * characters.length)];
  }
  return result;
}

function runGit(arguments_: string[]): string {
  try {
    return execFileSync("git", arguments_, { encoding: "utf8" }).trim();
  } catch {
    throw new IsolateError("Git could not be started.");
  }
}
