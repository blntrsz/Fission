import { mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const shellMetacharacters = new Set([
  "\\",
  " ",
  "(",
  ")",
  "[",
  "]",
  "{",
  "}",
  "<",
  ">",
  '"',
  "'",
  "`",
  "!",
  "#",
  "$",
  "&",
  ";",
  "|",
  "*",
  "?",
  "\t"
]);

export type PasteboardImageFormat = "png" | "jpeg" | "heic" | "gif" | "tiff";

export function shellEscape(value: string): string {
  return [...value].reduce((result, character) => {
    if (shellMetacharacters.has(character)) {
      return `${result}\\${character}`;
    }
    return `${result}${character}`;
  }, "");
}

export function pasteText(urls: string[], string: string | null | undefined): string | null {
  if (urls.length > 0) {
    return urls
      .map((url) => (isFileURL(url) ? shellEscape(filePathFromURL(url)) : url))
      .join(" ");
  }
  if (!string || string.length === 0) {
    return null;
  }
  return string;
}

export function pasteImageDirectory(): string {
  return join(tmpdir(), "fission-terminal-paste");
}

export function storePastedImage(data: Uint8Array, format: PasteboardImageFormat): string {
  const directory = pasteImageDirectory();
  mkdirSync(directory, { recursive: true });
  removeStaleFiles(directory);
  const destination = join(directory, `image-${crypto.randomUUID()}.${format}`);
  writeFileSync(destination, data);
  return destination;
}

function removeStaleFiles(directory: string): void {
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
  let files: string[] = [];
  try {
    files = readdirSync(directory);
  } catch {
    return;
  }
  for (const name of files) {
    const path = join(directory, name);
    try {
      if (statSync(path).mtimeMs < cutoff) {
        rmSync(path, { force: true });
      }
    } catch {
      continue;
    }
  }
}

function isFileURL(value: string): boolean {
  return value.startsWith("file:") || value.startsWith("/");
}

function filePathFromURL(value: string): string {
  if (value.startsWith("/")) {
    return value;
  }
  try {
    return decodeURIComponent(new URL(value).pathname);
  } catch {
    return value.replace(/^file:\/\//, "");
  }
}
