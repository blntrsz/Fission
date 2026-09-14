import { loginShellCommand, normalizedDirectory } from "./moshCommand";
import { lastPathComponent, type RemoteMachine } from "./types";

export function machineTarget(machine: Pick<RemoteMachine, "username" | "host">): string {
  const user = machine.username.trim();
  const hostname = machine.host.trim();
  if (user.length === 0) {
    return hostname;
  }
  return `${user}@${hostname}`;
}

export function machineDisplayName(machine: RemoteMachine): string {
  const trimmed = machine.name.trim();
  return trimmed.length === 0 ? machineTarget(machine) : trimmed;
}

export function isValidMachine(machine: Pick<RemoteMachine, "host" | "sshPort">): boolean {
  if (machine.host.trim().length === 0) {
    return false;
  }
  if (machine.sshPort != null) {
    return machine.sshPort >= 1 && machine.sshPort <= 65_535;
  }
  return true;
}

export function projectNameFromPath(path: string): string | null {
  let trimmed = path.trim();
  while (trimmed.length > 1 && trimmed.endsWith("/")) {
    trimmed = trimmed.slice(0, -1);
  }
  if (trimmed.length === 0 || trimmed === "~" || trimmed === "/") {
    return null;
  }
  const name = lastPathComponent(trimmed);
  return name.length === 0 ? null : name;
}

export function moshCommandFor(machine: RemoteMachine): string {
  return loginShellCommand(machineTarget(machine), machine.sshPort, machine.projectPath);
}

export function normalizeMachine(machine: RemoteMachine): RemoteMachine {
  return {
    ...machine,
    projectPath: normalizedDirectory(machine.projectPath)
  };
}
