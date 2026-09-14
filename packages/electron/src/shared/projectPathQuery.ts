import { posixQuote } from "./moshCommand";

export type ListingTarget = {
  directory: string;
  namePrefix: string;
};

export function isPathQuery(query: string): boolean {
  return query.startsWith("./") || query.startsWith("~/") || query.startsWith("/");
}

export function normalizeRemoteQuery(query: string): string {
  const trimmed = query.trim();
  if (trimmed.length === 0 || trimmed === "~") {
    return "~/";
  }
  if (isPathQuery(trimmed)) {
    return trimmed;
  }
  return `~/${trimmed}`;
}

export function listingTarget(query: string, relativeBase: string | null): ListingTarget | null {
  const trimmed = query.trim();
  if (!isPathQuery(trimmed)) {
    return null;
  }
  const expanded = expandRelative(trimmed, relativeBase);
  if (trimmed.endsWith("/")) {
    return { directory: stripTrailingSlashes(expanded), namePrefix: "" };
  }
  return { directory: parentDirectory(expanded), namePrefix: lastComponent(expanded) };
}

export function resolvedListingTarget(
  query: string,
  relativeBase: string | null,
  exactChildNames?: (directory: string) => string[] | null
): ListingTarget | null {
  const target = listingTarget(query, relativeBase);
  if (!target) {
    return null;
  }
  if (target.namePrefix.length === 0) {
    return target;
  }
  const names = exactChildNames?.(target.directory);
  const exact = names?.find(
    (name) => name.localeCompare(target.namePrefix, undefined, { sensitivity: "accent" }) === 0
  );
  if (!exact) {
    return target;
  }
  return { directory: join(target.directory, exact), namePrefix: "" };
}

export function pickerPaths(
  directory: string,
  namePrefix: string,
  childNames: string[],
  includeCurrentDirectory: boolean
): string[] {
  const children = childProjects(directory, childNames, namePrefix);
  const current = normalizedDirectory(directory);
  if (
    !includeCurrentDirectory ||
    namePrefix.length > 0 ||
    current == null ||
    current === "/" ||
    current === "~" ||
    current === "."
  ) {
    return children;
  }
  return [current, ...children.filter((path) => path !== current)];
}

export function expandRelative(path: string, base: string | null): string {
  if (!path.startsWith("./")) {
    return path;
  }
  const rest = path.slice(2);
  if (base == null || base.length === 0) {
    return path;
  }
  if (rest.length === 0 || rest === "/") {
    return stripTrailingSlashes(base);
  }
  return join(stripTrailingSlashes(base), rest);
}

export function join(directory: string, child: string): string {
  if (child.length === 0) {
    return directory;
  }
  if (directory === "/") {
    return child.startsWith("/") ? child : `/${child}`;
  }
  if (directory.endsWith("/")) {
    return directory + child;
  }
  return `${directory}/${child}`;
}

export function parentDirectory(path: string): string {
  const trimmed = stripTrailingSlashes(path);
  if (trimmed === "/" || trimmed === "~" || trimmed === ".") {
    return trimmed;
  }
  const slash = trimmed.lastIndexOf("/");
  if (slash === -1) {
    return ".";
  }
  const parent = trimmed.slice(0, slash);
  return parent.length === 0 ? "/" : parent;
}

export function lastComponent(path: string): string {
  const trimmed = stripTrailingSlashes(path);
  if (trimmed === "/") {
    return "/";
  }
  if (trimmed === "~") {
    return "~";
  }
  const slash = trimmed.lastIndexOf("/");
  if (slash === -1) {
    return trimmed;
  }
  const name = trimmed.slice(slash + 1);
  return name.length === 0 ? trimmed : name;
}

export function matchesPrefix(name: string, prefix: string): boolean {
  return prefix.length === 0 || name.toLowerCase().startsWith(prefix.toLowerCase());
}

export function matchesRecent(path: string, query: string): boolean {
  return (
    query.length === 0 ||
    lastComponent(path).toLowerCase().includes(query.toLowerCase()) ||
    path.toLowerCase().includes(query.toLowerCase())
  );
}

export function completedInput(
  query: string,
  path: string,
  homePath: string | null,
  relativeBase: string | null
): string {
  const withSlash = path.endsWith("/") || path === "/" ? path : `${path}/`;

  if (query.startsWith("./") && relativeBase) {
    const base = stripTrailingSlashes(relativeBase);
    if (path === base) {
      return "./";
    }
    const prefix = `${base}/`;
    if (path.startsWith(prefix)) {
      return `./${path.slice(prefix.length)}${path.endsWith("/") ? "" : "/"}`;
    }
  }

  if (homePath) {
    const home = stripTrailingSlashes(homePath);
    if (
      query.startsWith("~/") ||
      (!query.startsWith("/") && path.startsWith(`${home}/`)) ||
      path === home
    ) {
      if (path === home) {
        return "~/";
      }
      if (path.startsWith(home)) {
        return `~${path.slice(home.length)}${path.endsWith("/") ? "" : "/"}`;
      }
    }
  }

  if (path.startsWith("~")) {
    return withSlash;
  }

  return withSlash;
}

export function recentProjects(paths: string[], matching: string, limit = 9): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const path of paths) {
    const normalized = normalizedDirectory(path);
    if (normalized == null || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    if (!matchesRecent(normalized, matching)) {
      continue;
    }
    result.push(normalized);
    if (result.length === limit) {
      break;
    }
  }
  return result;
}

export function childProjects(
  directory: string,
  names: string[],
  namePrefix: string,
  limit = 50
): string[] {
  return names
    .filter((name) => matchesPrefix(name, namePrefix))
    .sort((left, right) => left.localeCompare(right, undefined, { sensitivity: "accent" }))
    .slice(0, limit)
    .map((name) => join(directory, name));
}

export function stripTrailingSlashes(path: string): string {
  let trimmed = path;
  while (trimmed.length > 1 && trimmed.endsWith("/")) {
    trimmed = trimmed.slice(0, -1);
  }
  return trimmed;
}

export function normalizedDirectory(path: string | null | undefined): string | null {
  if (path == null) {
    return null;
  }
  let trimmed = path.trim();
  if (trimmed.length === 0) {
    return null;
  }
  while (trimmed.length > 1 && trimmed.endsWith("/")) {
    trimmed = trimmed.slice(0, -1);
  }
  return trimmed;
}

export function posixQuotePath(value: string): string {
  return posixQuote(value);
}
