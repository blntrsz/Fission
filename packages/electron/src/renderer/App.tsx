import { useCallback, useEffect, useMemo, useState } from "react";
import {
  isRemoteThread,
  isSettled,
  projectDisplayName,
  type AgentThread,
  type NewThreadRequest,
  type RemoteMachine
} from "@shared/types";
import * as navigation from "@shared/navigation";
import type { AppSettings } from "@shared/settings";
import type { TerminalAppearance } from "@shared/ghosttyConfig";
import { Sidebar } from "./Sidebar";
import { NewThreadModal } from "./NewThreadModal";
import { ActiveThreadPicker } from "./ActiveThreadPicker";
import { SettingsModal } from "./SettingsModal";
import { TerminalWorkspace } from "./TerminalWorkspace";

type Bootstrap = {
  threads: AgentThread[];
  machines: RemoteMachine[];
  recentProjects: string[];
  settings: AppSettings;
  homePath: string;
  username: string;
  terminalAppearance: TerminalAppearance;
};

export function App() {
  const [ready, setReady] = useState(false);
  const [threads, setThreads] = useState<AgentThread[]>([]);
  const [machines, setMachines] = useState<RemoteMachine[]>([]);
  const [recentProjects, setRecentProjects] = useState<string[]>([]);
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [homePath, setHomePath] = useState("");
  const [username, setUsername] = useState("");
  const [appearance, setAppearance] = useState<TerminalAppearance | null>(null);
  const [nav, setNav] = useState(navigation.createNavigation());
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [creating, setCreating] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [renameSignal, setRenameSignal] = useState(0);
  const [tabCommand, setTabCommand] = useState<{ kind: "add" } | { kind: "select"; index: number } | { kind: "search"; command: string } | null>(null);
  const [focused, setFocused] = useState(true);
  const [activity, setActivity] = useState<Record<string, string[]>>({});
  const [createdThreadID, setCreatedThreadID] = useState<string | null>(null);

  const activeThreads = useMemo(
    () => threads.filter((thread) => !isSettled(thread)),
    [threads]
  );
  const selected = threads.find((thread) => thread.id === nav.selectedThreadID) ?? null;

  const applyThreads = useCallback((next: AgentThread[]) => {
    setThreads(next);
    setNav((current) =>
      navigation.synchronizeNavigation(
        current,
        next.filter((thread) => !isSettled(thread)).map((thread) => thread.id)
      )
    );
  }, []);

  useEffect(() => {
    void window.fission.bootstrap().then((payload: Bootstrap) => {
      setMachines(payload.machines);
      setRecentProjects(payload.recentProjects);
      setSettings(payload.settings);
      setHomePath(payload.homePath);
      setUsername(payload.username);
      setAppearance(payload.terminalAppearance);
      applyThreads(payload.threads);
      setReady(true);
    });
  }, [applyThreads]);

  useEffect(() => {
    return window.fission.activity.onChanged(setActivity);
  }, []);

  useEffect(() => {
    if (!ready) {
      return;
    }
    void window.fission.activity.attention(nav.selectedThreadID, focused);
  }, [nav.selectedThreadID, focused, ready]);

  useEffect(() => {
    return window.fission.menu.on((channel, payload) => {
      switch (channel) {
        case "menu:new-thread":
          setCreating(true);
          break;
        case "menu:open-thread":
          if (activeThreads.length > 0) {
            setSwitching(true);
          }
          break;
        case "menu:open-thread-id":
          if (typeof payload === "string") {
            setNav((current) => navigation.selectThread(current, payload));
          }
          break;
        case "menu:rename-thread":
          setRenameSignal((value) => value + 1);
          break;
        case "menu:new-tab":
          setTabCommand({ kind: "add" });
          break;
        case "menu:select-tab":
          setTabCommand({ kind: "select", index: payload as number });
          break;
        case "menu:search":
          setTabCommand({ kind: "search", command: payload as string });
          break;
        case "menu:toggle-sidebar":
          setSidebarOpen((open) => !open);
          break;
        case "menu:settings":
          setSettingsOpen(true);
          break;
        case "app:focus":
          setFocused(Boolean(payload));
          break;
        default:
          break;
      }
    });
  }, [activeThreads.length]);

  async function updateSettings(patch: Partial<AppSettings>) {
    if (patch.notifyWhenAgentFinishes) {
      await window.fission.notifications.request();
    }
    setSettings(await window.fission.settings.update(patch));
  }

  async function createThread(request: NewThreadRequest) {
    try {
      const result = await window.fission.threads.create(request);
      applyThreads(result.threads);
      setRecentProjects(result.recentProjects);
      setMachines(result.machines);
      setNav(navigation.selectThread(nav, result.thread.id));
      setCreatedThreadID(result.thread.id);
      setCreating(false);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : String(error));
    }
  }

  if (!ready || !settings) {
    return <div className="empty">Loading Threads…</div>;
  }

  return (
    <div className={`app${sidebarOpen ? "" : " sidebar-collapsed"}`}>
      <Sidebar
        threads={threads}
        selectedThreadID={nav.selectedThreadID}
        activity={activity}
        renameSignal={renameSignal}
        createdThreadID={createdThreadID}
        onSelect={(id) => setNav(navigation.selectThread(nav, id))}
        onCreate={() => setCreating(true)}
        onRename={async (id, title) => applyThreads(await window.fission.threads.rename(id, title))}
        onSettle={async (id) => applyThreads(await window.fission.threads.settle(id))}
        onReopen={async (id) => {
          applyThreads(await window.fission.threads.reopen(id));
          setNav(navigation.selectThread(nav, id));
        }}
        onDelete={async (ids) => applyThreads(await window.fission.threads.delete(ids))}
        onReorder={async (ids) => applyThreads(await window.fission.threads.reorder(ids))}
      />
      <section className="workspace">
        <header className="workspace-header">
          {selected ? (
            <div
              data-testid="selected-thread-title"
              title={selected.workingDirectory ?? selected.title}
            >
              <span>{isRemoteThread(selected) ? "↗" : "📁"}</span>{" "}
              <span>{projectDisplayName(selected)}</span>
              <span> / </span>
              <span className="header-title">{selected.title}</span>
            </div>
          ) : (
            <span>Select a Thread</span>
          )}
        </header>
        {selected && !isSettled(selected) ? (
          <TerminalWorkspace
            thread={selected}
            command={tabCommand}
            appearance={appearance}
            onCommandHandled={() => setTabCommand(null)}
          />
        ) : (
          <div className="empty">
            <div>
              <strong>Select a Thread</strong>
              <p>Choose a Thread to open its terminal workspace.</p>
            </div>
          </div>
        )}
      </section>

      {creating && (
        <NewThreadModal
          recentPaths={recentProjects}
          machines={machines}
          threads={threads}
          settings={settings}
          homePath={homePath}
          onSettingsChange={updateSettings}
          onCreate={createThread}
          onOpenSettings={() => {
            setCreating(false);
            setSettingsOpen(true);
          }}
          onCancel={() => setCreating(false)}
        />
      )}
      {switching && (
        <ActiveThreadPicker
          threads={activeThreads}
          selectedThreadID={nav.selectedThreadID}
          onSelect={(id) => {
            setSwitching(false);
            setNav(navigation.selectThread(nav, id));
          }}
          onCancel={() => setSwitching(false)}
        />
      )}
      {settingsOpen && (
        <SettingsModal
          settings={settings}
          machines={machines}
          username={username}
          onSettingsChange={updateSettings}
          onMachinesChange={setMachines}
          onClose={() => setSettingsOpen(false)}
        />
      )}
      {errorMessage && (
        <div className="alert">
          <div className="alert-card">
            <h3>Something went wrong</h3>
            <p>{errorMessage}</p>
            <button className="primary" type="button" onClick={() => setErrorMessage(null)}>
              OK
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
