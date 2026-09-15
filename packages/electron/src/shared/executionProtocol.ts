export const executionProtocolVersion = 3;
export const replayByteLimit = 4 * 1024 * 1024;

export type ExecutionRequestKind = "attachOrCreate" | "input" | "resize" | "terminate";
export type ExecutionResponseKind = "attached" | "output" | "exited" | "failure";

export type ExecutionRequest = {
  version: number;
  kind: ExecutionRequestKind;
  sessionID: string;
  threadID?: string;
  workingDirectory?: string | null;
  startupCommand?: string | null;
  environment?: Record<string, string>;
  data?: string;
  columns?: number;
  rows?: number;
  resumeOffset?: number;
};

export type ExecutionResponse = {
  version: number;
  kind: ExecutionResponseKind;
  sessionID: string;
  data?: string;
  exitCode?: number;
  runtimeMilliseconds?: number;
  message?: string;
  offset?: number;
};

export function encodeMessage(message: object): Buffer {
  return Buffer.from(`${JSON.stringify(message)}\n`, "utf8");
}

export function decodeLines(buffer: Buffer): { messages: string[]; rest: Buffer } {
  const messages: string[] = [];
  let rest: Buffer = buffer;
  while (true) {
    const index = rest.indexOf(0x0a);
    if (index === -1) {
      return { messages, rest };
    }
    messages.push(rest.subarray(0, index).toString("utf8"));
    rest = Buffer.from(rest.subarray(index + 1));
  }
}

export function appendReplay(
  replay: Buffer,
  startOffset: number,
  chunk: Buffer
): { replay: Buffer; startOffset: number; nextOffset: number } {
  const nextOffset = startOffset + replay.length + chunk.length;
  let next = Buffer.concat([replay, chunk]);
  let nextStart = startOffset;
  const excess = next.length - replayByteLimit;
  if (excess > 0) {
    next = next.subarray(excess);
    nextStart += excess;
  }
  return { replay: next, startOffset: nextStart, nextOffset };
}

export function fnv1a64(value: string): string {
  let hash = 14_695_981_039_346_656_037n;
  for (const byte of Buffer.from(value, "utf8")) {
    hash ^= BigInt(byte);
    hash = (hash * 1_099_511_628_211n) & 0xffff_ffff_ffff_ffffn;
  }
  return hash.toString(16);
}

export function defaultSocketPath(applicationSupportPath: string, uid: number, channel?: string): string {
  const resolvedChannel = channel ?? process.env.FISSION_EXECUTION_CHANNEL ?? "com.fission.desktop";
  const hash = fnv1a64(`${applicationSupportPath}|${resolvedChannel}|v${executionProtocolVersion}`);
  return `/tmp/fission-execution-${uid}-${hash}.sock`;
}
