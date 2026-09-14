import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { normalizeMachine, isValidMachine } from "@shared/remoteMachine";
import { newThreadId, type RemoteMachine } from "@shared/types";

export class RemoteMachineStore {
  private machines: RemoteMachine[];

  constructor(private readonly filePath: string) {
    this.machines = load(filePath);
  }

  list(): RemoteMachine[] {
    return this.machines;
  }

  upsert(machine: RemoteMachine): RemoteMachine | null {
    const normalized = normalizeMachine(machine);
    if (!isValidMachine(normalized)) {
      return null;
    }
    const index = this.machines.findIndex((item) => item.id === normalized.id);
    if (index >= 0) {
      this.machines[index] = normalized;
    } else {
      this.machines.push(normalized);
    }
    this.persist();
    return normalized;
  }

  remove(id: string): void {
    this.machines = this.machines.filter((machine) => machine.id !== id);
    this.persist();
  }

  machine(id: string): RemoteMachine | null {
    return this.machines.find((machine) => machine.id === id) ?? null;
  }

  private persist(): void {
    mkdirSync(dirname(this.filePath), { recursive: true });
    writeFileSync(this.filePath, JSON.stringify(this.machines, null, 0));
  }
}

export function newMachineDraft(username: string): RemoteMachine {
  return {
    id: newThreadId(),
    name: "",
    username,
    host: "",
    sshPort: null,
    projectPath: null
  };
}

function load(filePath: string): RemoteMachine[] {
  if (!existsSync(filePath)) {
    return [];
  }
  try {
    const parsed: unknown = JSON.parse(readFileSync(filePath, "utf8"));
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed.flatMap((item) => {
      if (item == null || typeof item !== "object") {
        return [];
      }
      const record = item as Partial<RemoteMachine>;
      if (typeof record.id !== "string" || typeof record.host !== "string") {
        return [];
      }
      return [
        normalizeMachine({
          id: record.id,
          name: typeof record.name === "string" ? record.name : "",
          username: typeof record.username === "string" ? record.username : "",
          host: record.host,
          sshPort: typeof record.sshPort === "number" ? record.sshPort : null,
          projectPath: typeof record.projectPath === "string" ? record.projectPath : null
        })
      ];
    });
  } catch {
    return [];
  }
}
