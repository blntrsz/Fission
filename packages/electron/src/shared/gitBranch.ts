import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

export function currentBranch(workingDirectory: string | null | undefined): string | null {
  if (!workingDirectory) {
    return null;
  }
  const gitDirectory = findGitDirectory(resolve(workingDirectory));
  if (!gitDirectory) {
    return null;
  }
  try {
    const head = readFileSync(join(gitDirectory, "HEAD"), "utf8").trim();
    const prefix = "ref: refs/heads/";
    if (head.startsWith(prefix)) {
      return head.slice(prefix.length);
    }
    return head.length === 0 ? null : head.slice(0, 7);
  } catch {
    return null;
  }
}

function findGitDirectory(workingDirectory: string): string | null {
  let directory = workingDirectory;
  while (directory !== "/") {
    const candidate = join(directory, ".git");
    try {
      const info = statSync(candidate);
      if (info.isDirectory()) {
        return candidate;
      }
      return worktreeGitDirectory(candidate, directory);
    } catch {
      directory = dirname(directory);
    }
  }
  return null;
}

function worktreeGitDirectory(file: string, directory: string): string | null {
  try {
    const contents = readFileSync(file, "utf8");
    if (!contents.startsWith("gitdir: ")) {
      return null;
    }
    const path = contents.slice("gitdir: ".length).trim();
    if (path.startsWith("/")) {
      return path;
    }
    return resolve(directory, path);
  } catch {
    return null;
  }
}

export function gitDirectoryExists(workingDirectory: string): boolean {
  return existsSync(join(workingDirectory, ".git"));
}
