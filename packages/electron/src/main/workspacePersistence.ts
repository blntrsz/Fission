import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { TerminalTabRecord } from "@shared/types";

type WorkspaceFile = Record<string, TerminalTabRecord[]>;

export class WorkspacePersistence {
  constructor(private readonly filePath: string) {}

  load(threadID: string): TerminalTabRecord[] {
    return this.read()[threadID] ?? [];
  }

  save(threadID: string, tabs: TerminalTabRecord[]): void {
    const data = this.read();
    data[threadID] = tabs;
    this.write(data);
  }

  remove(threadID: string): void {
    const data = this.read();
    delete data[threadID];
    this.write(data);
  }

  private read(): WorkspaceFile {
    if (!existsSync(this.filePath)) {
      return {};
    }
    try {
      const parsed: unknown = JSON.parse(readFileSync(this.filePath, "utf8"));
      return parsed && typeof parsed === "object" ? (parsed as WorkspaceFile) : {};
    } catch {
      return {};
    }
  }

  private write(data: WorkspaceFile): void {
    mkdirSync(dirname(this.filePath), { recursive: true });
    writeFileSync(this.filePath, JSON.stringify(data));
  }
}
