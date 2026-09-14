import { posixQuote } from "./moshCommand";
import { isValidMachine, machineTarget } from "./remoteMachine";
import type { RemoteMachine } from "./types";

export type RemoteDirectoryListing =
  | { kind: "missing" }
  | { kind: "failed" }
  | { kind: "contents"; names: string[] };

export const notADirectoryStatus = 2;

const listingScript = `path=$1
case "$path" in
~) dir="$HOME" ;;
~/*) dir="$HOME/\${path#~/}" ;;
*) dir="$path" ;;
esac
[ -d "$dir" ] || exit 2
find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' -print 2>/dev/null | while IFS= read -r p; do
  [ -d "$p" ] || continue
  printf '%s\\n' "\${p##*/}"
done`;

export function remoteCommand(directory: string): string {
  return `sh -c ${posixQuote(listingScript)} -- ${posixQuote(directory)}`;
}

export function processArguments(machine: RemoteMachine, directory: string): string[] {
  const arguments_ = [
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=4",
    "-o",
    "LogLevel=ERROR"
  ];
  if (machine.sshPort != null && machine.sshPort !== 22) {
    arguments_.push("-p", String(machine.sshPort));
  }
  arguments_.push(machineTarget(machine), remoteCommand(directory));
  return arguments_;
}

export function parseOutput(output: string): string[] {
  const seen = new Set<string>();
  const names: string[] = [];
  for (const line of output.split(/\r?\n/)) {
    const name = line;
    if (name.length === 0 || name === "." || name === ".." || name.startsWith(".")) {
      continue;
    }
    if (seen.has(name)) {
      continue;
    }
    seen.add(name);
    names.push(name);
  }
  return names.sort((left, right) =>
    left.localeCompare(right, undefined, { sensitivity: "accent" })
  );
}

export function parseFixtureJSON(json: string): Record<string, string[]> | null {
  try {
    const parsed: unknown = JSON.parse(json);
    if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return null;
    }
    const result: Record<string, string[]> = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
        return null;
      }
      result[key] = value;
    }
    return result;
  } catch {
    return null;
  }
}

export function listingResult(status: number, output: string): RemoteDirectoryListing {
  if (status === 0) {
    return { kind: "contents", names: parseOutput(output) };
  }
  if (status === notADirectoryStatus) {
    return { kind: "missing" };
  }
  return { kind: "failed" };
}

export function canList(machine: RemoteMachine): boolean {
  return isValidMachine(machine);
}
