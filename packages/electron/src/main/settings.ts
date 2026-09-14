import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { defaultSettings, type AppSettings } from "@shared/settings";

export type { AppSettings };

export class SettingsStore {
  private value: AppSettings;

  constructor(private readonly filePath: string) {
    this.value = load(filePath);
  }

  get(): AppSettings {
    return this.value;
  }

  update(patch: Partial<AppSettings>): AppSettings {
    this.value = { ...this.value, ...patch };
    mkdirSync(dirname(this.filePath), { recursive: true });
    writeFileSync(this.filePath, JSON.stringify(this.value));
    return this.value;
  }
}

function load(filePath: string): AppSettings {
  if (!existsSync(filePath)) {
    return { ...defaultSettings };
  }
  try {
    const parsed = JSON.parse(readFileSync(filePath, "utf8")) as Partial<AppSettings>;
    return { ...defaultSettings, ...parsed };
  } catch {
    return { ...defaultSettings };
  }
}
