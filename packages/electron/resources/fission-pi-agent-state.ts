// installed and managed by Fission
// FISSION_INTEGRATION_ID=pi
// FISSION_INTEGRATION_VERSION=1

import dgram from "node:dgram";

const port = Number.parseInt(process.env.FISSION_AGENT_PORT ?? "", 10);
const token = process.env.FISSION_AGENT_TOKEN;
const threadId = process.env.FISSION_THREAD_ID;
const tabId = process.env.FISSION_TAB_ID;
const enabled = Number.isInteger(port) && port > 0 && !!token && !!threadId && !!tabId;

type AgentState = "idle" | "running" | "blocked" | "finished";

let sequence = Date.now() * 1000;

function report(state: AgentState): void {
  if (!enabled) return;

  const socket = dgram.createSocket("udp4");
  const payload = Buffer.from(JSON.stringify({
    version: 1,
    token,
    threadId,
    tabId,
    agent: "pi",
    state,
    sequence: ++sequence,
  }));

  socket.send(payload, port, "127.0.0.1", () => socket.close());
  socket.on("error", () => socket.close());
}

export default function (pi: any): void {
  if (!enabled) return;

  let baseState: Exclude<AgentState, "blocked"> = "idle";
  let blockedPromptCount = 0;
  let rootSession = false;
  let lastState: AgentState | undefined;

  function publish(force = false): void {
    const state: AgentState = blockedPromptCount > 0 ? "blocked" : baseState;
    if (!force && state === lastState) return;
    lastState = state;
    report(state);
  }

  pi.on("session_start", (_event: unknown, ctx: any) => {
    if (ctx?.mode !== "tui") return;
    rootSession = true;
    baseState = ctx?.isIdle?.() === false ? "running" : "idle";
    publish(true);
  });

  pi.on("agent_start", () => {
    if (!rootSession) return;
    baseState = "running";
    publish();
  });

  pi.on("ui_prompt_start", () => {
    if (!rootSession) return;
    blockedPromptCount += 1;
    publish();
  });

  pi.on("ui_prompt_end", () => {
    if (!rootSession) return;
    blockedPromptCount = Math.max(0, blockedPromptCount - 1);
    publish();
  });

  pi.on("agent_settled", (_event: unknown, ctx: any) => {
    if (!rootSession || ctx?.isIdle?.() !== true) return;
    baseState = "finished";
    publish();
  });

  pi.on("session_shutdown", (event: any) => {
    if (!rootSession || event?.reason !== "quit") return;
    rootSession = false;
    blockedPromptCount = 0;
    baseState = "idle";
    publish();
  });
}
