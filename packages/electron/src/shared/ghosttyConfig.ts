import { existsSync, readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type TerminalAppearance = {
  fontFamily: string;
  fontSize: number;
  theme: {
    background: string;
    foreground: string;
    cursor?: string;
    cursorAccent?: string;
    selectionBackground?: string;
    selectionForeground?: string;
    black?: string;
    red?: string;
    green?: string;
    yellow?: string;
    blue?: string;
    magenta?: string;
    cyan?: string;
    white?: string;
    brightBlack?: string;
    brightRed?: string;
    brightGreen?: string;
    brightYellow?: string;
    brightBlue?: string;
    brightMagenta?: string;
    brightCyan?: string;
    brightWhite?: string;
  };
};

const defaultAppearance: TerminalAppearance = {
  fontFamily: "Menlo, Monaco, ui-monospace, monospace",
  fontSize: 13,
  theme: {
    background: "#111111",
    foreground: "#f5f5f7"
  }
};

const paletteKeys = [
  "black",
  "red",
  "green",
  "yellow",
  "blue",
  "magenta",
  "cyan",
  "white",
  "brightBlack",
  "brightRed",
  "brightGreen",
  "brightYellow",
  "brightBlue",
  "brightMagenta",
  "brightCyan",
  "brightWhite"
] as const;

export function ghosttyConfigPaths(home = homedir(), xdgConfigHome = process.env.XDG_CONFIG_HOME): string[] {
  const xdgDirectory =
    xdgConfigHome && xdgConfigHome.startsWith("/") ? xdgConfigHome : join(home, ".config");
  const xdgGhostty = join(xdgDirectory, "ghostty");
  const appSupport = join(home, "Library/Application Support/com.mitchellh.ghostty");
  return [
    join(xdgGhostty, "config"),
    join(xdgGhostty, "config.ghostty"),
    join(appSupport, "config"),
    join(appSupport, "config.ghostty")
  ];
}

export function parseGhosttyConfig(contents: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const rawLine of contents.split("\n")) {
    const line = rawLine.trim();
    if (line.length === 0 || line.startsWith("#")) {
      continue;
    }
    const index = line.indexOf("=");
    if (index === -1) {
      continue;
    }
    const key = line.slice(0, index).trim();
    const value = line.slice(index + 1).trim().replace(/^"|"$/g, "");
    if (key === "palette") {
      const match = value.match(/^(\d+)\s*=\s*(.+)$/);
      if (match) {
        values[`palette.${match[1]}`] = match[2].trim();
      }
      continue;
    }
    values[key] = value;
  }
  return values;
}

export function appearanceFromGhosttyValues(
  values: Record<string, string>,
  fallback = defaultAppearance
): TerminalAppearance {
  const theme = { ...fallback.theme };
  if (values.background) {
    theme.background = values.background;
  }
  if (values.foreground) {
    theme.foreground = values.foreground;
  }
  if (values["cursor-color"]) {
    theme.cursor = values["cursor-color"];
  }
  if (values["cursor-text"]) {
    theme.cursorAccent = values["cursor-text"];
  }
  if (values["selection-background"]) {
    theme.selectionBackground = values["selection-background"];
  }
  if (values["selection-foreground"]) {
    theme.selectionForeground = values["selection-foreground"];
  }
  for (let index = 0; index < paletteKeys.length; index += 1) {
    const color = values[`palette.${index}`];
    if (color) {
      theme[paletteKeys[index]] = color;
    }
  }

  const fontSize = Number.parseFloat(values["font-size"] ?? "");
  return {
    fontFamily: values["font-family"]
      ? `${values["font-family"]}, ui-monospace, monospace`
      : fallback.fontFamily,
    fontSize: Number.isFinite(fontSize) && fontSize > 0 ? fontSize : fallback.fontSize,
    theme
  };
}

export function loadGhosttyAppearance(home = homedir()): TerminalAppearance {
  const merged: Record<string, string> = {};
  for (const path of ghosttyConfigPaths(home)) {
    if (!existsSync(path)) {
      continue;
    }
    try {
      Object.assign(merged, parseGhosttyConfig(readFileSync(path, "utf8")));
    } catch {
      continue;
    }
  }
  const themeName = merged.theme;
  let themeValues: Record<string, string> = {};
  if (themeName && !themeName.includes("/") && !themeName.includes(":")) {
    themeValues = loadNamedTheme(themeName, home);
  } else if (themeName?.startsWith("/")) {
    try {
      themeValues = parseGhosttyConfig(readFileSync(themeName, "utf8"));
    } catch {
      themeValues = {};
    }
  }
  return appearanceFromGhosttyValues({ ...themeValues, ...merged });
}

function loadNamedTheme(name: string, home: string): Record<string, string> {
  const unquoted = name.replaceAll('"', "");
  const directories = [
    join(home, ".config/ghostty/themes"),
    join(home, "Library/Application Support/com.mitchellh.ghostty/themes")
  ];
  for (const directory of directories) {
    if (!existsSync(directory)) {
      continue;
    }
    try {
      const matching = readdirSync(directory).find(
        (entry) => entry.localeCompare(unquoted, undefined, { sensitivity: "accent" }) === 0
      );
      if (matching) {
        return parseGhosttyConfig(readFileSync(join(directory, matching), "utf8"));
      }
    } catch {
      continue;
    }
  }
  return {};
}
