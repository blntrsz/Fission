import { existsSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import * as query from "./projectPathQuery";
import type { ProjectPath } from "./types";

export function makeProjectPath(path: string, displayPath?: string): ProjectPath {
  return {
    path,
    displayPath: displayPath ?? path,
    name: (() => {
      const last = query.lastComponent(path);
      return last.length === 0 ? path : last;
    })()
  };
}

export function projectPathFromAbsolute(path: string, homePath = homedir()): ProjectPath {
  const standardized = resolve(path);
  return makeProjectPath(standardized, abbreviate(standardized, homePath));
}

export function abbreviate(path: string, homePath = homedir()): string {
  if (!path.startsWith(homePath)) {
    return path;
  }
  return `~${path.slice(homePath.length)}`;
}

export function localProjects(matching: string, recentPaths: string[], homePath = homedir()): ProjectPath[] {
  const trimmedQuery = matching.trim();
  if (!query.isPathQuery(trimmedQuery)) {
    return recentLocalProjects(recentPaths, trimmedQuery);
  }

  const relativeBase = recentPaths[0] ?? homePath;
  const relative = query.expandRelative(trimmedQuery, relativeBase);
  const expanded = relative.startsWith("~")
    ? expandTilde(relative, homePath)
    : relative;
  const splitQuery =
    trimmedQuery.endsWith("/") && !expanded.endsWith("/") ? `${expanded}/` : expanded;
  const target = query.listingTarget(splitQuery, null);
  if (!target) {
    return [];
  }

  let directoryPath = resolve(target.directory);
  let namePrefix = target.namePrefix;
  if (namePrefix.length > 0) {
    const candidate = query.join(directoryPath, namePrefix);
    if (isDirectory(candidate)) {
      directoryPath = resolve(candidate);
      namePrefix = "";
    }
  }

  let names: string[] = [];
  try {
    names = readdirSync(directoryPath).filter((name) => {
      if (name.startsWith(".")) {
        return false;
      }
      return isDirectory(join(directoryPath, name));
    });
  } catch {
    return [];
  }

  return query
    .pickerPaths(directoryPath, namePrefix, names, true)
    .map((path) => projectPathFromAbsolute(path, homePath));
}

export function remoteProjects(
  directory: string,
  namePrefix: string,
  listing: { kind: string; names?: string[] } | null
): ProjectPath[] {
  if (listing?.kind !== "contents" || listing.names == null) {
    return [];
  }
  return query.pickerPaths(directory, namePrefix, listing.names, true).map((path) =>
    makeProjectPath(path)
  );
}

function recentLocalProjects(paths: string[], matching: string): ProjectPath[] {
  return query.recentProjects(paths, matching).flatMap((path) => {
    if (!isDirectory(path)) {
      return [];
    }
    return [projectPathFromAbsolute(path)];
  });
}

function expandTilde(path: string, homePath: string): string {
  if (path === "~") {
    return homePath;
  }
  if (path.startsWith("~/")) {
    return join(homePath, path.slice(2));
  }
  return path;
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

export function pathExists(path: string): boolean {
  return existsSync(path);
}

export function folderName(path: string): string {
  const name = basename(path);
  return name.length === 0 ? path : name;
}
