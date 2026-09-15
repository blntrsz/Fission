import { existsSync, realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { extname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { displayString, handlerDescription } from "./terminalURLDisplay";

export { displayString, handlerDescription };

export type TerminalDetectedURLKind = "unknown" | "text" | "html";

export type TerminalURLSource = "osc8" | { detected: TerminalDetectedURLKind } | "fissionOwned";

export type TerminalURLOpenMethod = "defaultApplication" | "textEditor";

export type TerminalURLDenialReason =
  | "malformedURL"
  | "unsafeCharacters"
  | "remoteFile"
  | "inaccessibleFile"
  | "unsafeFile";

export type TerminalURLDecision =
  | { kind: "open"; url: string; method: TerminalURLOpenMethod }
  | { kind: "confirm"; url: string }
  | { kind: "deny"; reason: TerminalURLDenialReason };

export type TerminalURLTarget = {
  rawValue: string;
  source: TerminalURLSource;
};

export const denialMessage: Record<TerminalURLDenialReason, string> = {
  malformedURL: "The target is not a valid absolute web, mail, or file URL.",
  unsafeCharacters:
    "The target contains invisible, control, bidirectional, or line-breaking characters.",
  remoteFile: "Terminal links cannot open files on a remote host.",
  inaccessibleFile: "The local target does not exist or is not a regular file or directory.",
  unsafeFile: "Opening this local target could execute code."
};

const unsafePathExtensions = new Set([
  "action",
  "app",
  "applescript",
  "class",
  "command",
  "desktop",
  "inetloc",
  "jar",
  "mobileconfig",
  "mpkg",
  "pkg",
  "scpt",
  "terminal",
  "tool",
  "url",
  "webloc",
  "workflow",
  "sh",
  "bash",
  "zsh",
  "csh",
  "ksh",
  "fish",
  "py",
  "rb",
  "pl",
  "php",
  "ps1",
  "bat",
  "cmd",
  "exe",
  "bin",
  "dylib",
  "so"
]);

const unsafeCharacterPattern = /\p{Cc}|\p{Cf}|\p{Zl}|\p{Zp}/u;

export function decision(target: TerminalURLTarget): TerminalURLDecision {
  const rawValue = target.rawValue;
  if (rawValue.length === 0) {
    return { kind: "deny", reason: "malformedURL" };
  }
  if (unsafeCharacterPattern.test(rawValue)) {
    return { kind: "deny", reason: "unsafeCharacters" };
  }
  if (!hasValidPercentEscapes(rawValue)) {
    return { kind: "deny", reason: "malformedURL" };
  }

  const url = resolvedURL(target);
  if (!url) {
    return { kind: "deny", reason: "malformedURL" };
  }

  const scheme = url.protocol.replace(/:$/, "").toLowerCase();
  if (!scheme) {
    return { kind: "deny", reason: "malformedURL" };
  }

  switch (scheme) {
    case "http":
    case "https":
      if (!url.hostname) {
        return { kind: "deny", reason: "malformedURL" };
      }
      return { kind: "open", url: url.href, method: "defaultApplication" };
    case "mailto":
      if (!isValidMailURL(url)) {
        return { kind: "deny", reason: "malformedURL" };
      }
      return { kind: "open", url: url.href, method: "defaultApplication" };
    case "file":
      return fileDecision(url, target.source);
    default:
      return { kind: "confirm", url: url.href };
  }
}

function resolvedURL(target: TerminalURLTarget): URL | null {
  const parsed = parseAbsoluteURL(target.rawValue);
  if (parsed) {
    return parsed;
  }
  if (!isDetected(target.source)) {
    return null;
  }
  const path = expandTilde(target.rawValue);
  if (!path.startsWith("/")) {
    return null;
  }
  return pathToFileURL(path);
}

function parseAbsoluteURL(rawValue: string): URL | null {
  const schemeMatch = rawValue.match(/^([A-Za-z][A-Za-z0-9+.-]*):/);
  if (!schemeMatch) {
    return null;
  }
  const scheme = schemeMatch[1].toLowerCase();
  if ((scheme === "http" || scheme === "https") && !rawValue.slice(schemeMatch[0].length).startsWith("//")) {
    return null;
  }
  if ((scheme === "http" || scheme === "https") && /^[a-z]+:\/\/\//i.test(rawValue)) {
    return null;
  }
  try {
    const url = new URL(rawValue);
    if ((scheme === "http" || scheme === "https") && !url.hostname) {
      return null;
    }
    return url;
  } catch {
    return null;
  }
}

function isValidMailURL(url: URL): boolean {
  const recipients = decodeURIComponent(url.pathname);
  if (recipients.length === 0) {
    return false;
  }
  return recipients.split(",").every((recipient) => {
    const parts = recipient.split("@");
    return (
      parts.length === 2 &&
      parts[0].length > 0 &&
      parts[1].length > 0 &&
      !/\s/.test(recipient)
    );
  });
}

function fileDecision(url: URL, source: TerminalURLSource): TerminalURLDecision {
  if (url.search || url.hash) {
    return { kind: "deny", reason: "malformedURL" };
  }
  const host = url.hostname;
  if (host && host.toLowerCase() !== "localhost") {
    return { kind: "deny", reason: "remoteFile" };
  }

  const path = canonicalFilePath(url);
  if (!path) {
    return { kind: "deny", reason: "inaccessibleFile" };
  }

  let stats;
  try {
    stats = statSync(path);
  } catch {
    return { kind: "deny", reason: "inaccessibleFile" };
  }
  if (!stats.isDirectory() && !stats.isFile()) {
    return { kind: "deny", reason: "inaccessibleFile" };
  }
  if (isUnsafeFile(path, stats.isDirectory(), stats.mode)) {
    return { kind: "deny", reason: "unsafeFile" };
  }

  const method: TerminalURLOpenMethod =
    isDetected(source) && source.detected === "text" && !stats.isDirectory()
      ? "textEditor"
      : "defaultApplication";
  return { kind: "open", url: pathToFileURL(path).href, method };
}

function isUnsafeFile(path: string, isDirectory: boolean, mode: number): boolean {
  const extension = extname(path).replace(/^\./, "").toLowerCase();
  if (unsafePathExtensions.has(extension)) {
    return true;
  }
  return !isDirectory && (mode & 0o111) !== 0;
}

function hasValidPercentEscapes(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    if (value[index] !== "%") {
      continue;
    }
    const first = value[index + 1];
    const second = value[index + 2];
    if (!isASCIIHexDigit(first) || !isASCIIHexDigit(second)) {
      return false;
    }
  }
  return true;
}

function isASCIIHexDigit(value: string | undefined): boolean {
  if (!value) {
    return false;
  }
  const code = value.charCodeAt(0);
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102);
}

function canonicalFilePath(url: URL): string | null {
  const path = filePathFromURL(url);
  try {
    if (!existsSync(path) && !existsSync(filePathFromURL(url))) {
      return null;
    }
    return realpathSync(path);
  } catch {
    return null;
  }
}

function filePathFromURL(url: URL): string {
  return fileURLToPath(url);
}

function expandTilde(value: string): string {
  if (value === "~") {
    return homedir();
  }
  if (value.startsWith("~/")) {
    return `${homedir()}${value.slice(1)}`;
  }
  return value;
}

function isDetected(source: TerminalURLSource): source is { detected: TerminalDetectedURLKind } {
  return typeof source === "object" && "detected" in source;
}
