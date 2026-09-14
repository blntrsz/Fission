import { contextBridge, ipcRenderer } from "electron";
import type { NewThreadRequest, ProjectPath, RemoteMachine, TerminalTabRecord } from "@shared/types";
import type { AppSettings } from "@shared/settings";

const api = {
  bootstrap: () => ipcRenderer.invoke("bootstrap"),
  threads: {
    create: (request: NewThreadRequest) => ipcRenderer.invoke("threads:create", request),
    rename: (threadID: string, title: string) => ipcRenderer.invoke("threads:rename", threadID, title),
    settle: (threadID: string) => ipcRenderer.invoke("threads:settle", threadID),
    reopen: (threadID: string) => ipcRenderer.invoke("threads:reopen", threadID),
    delete: (ids: string[]) => ipcRenderer.invoke("threads:delete", ids),
    reorder: (ids: string[]) => ipcRenderer.invoke("threads:reorder", ids),
    gitBranch: (workingDirectory: string | null) =>
      ipcRenderer.invoke("threads:git-branch", workingDirectory) as Promise<string | null>
  },
  projects: {
    list: (query: string) => ipcRenderer.invoke("projects:list", query) as Promise<ProjectPath[]>,
    listRemote: (machineID: string, projectPath: string) =>
      ipcRenderer.invoke("projects:list-remote", machineID, projectPath)
  },
  machines: {
    list: () => ipcRenderer.invoke("machines:list") as Promise<RemoteMachine[]>,
    upsert: (machine: RemoteMachine) => ipcRenderer.invoke("machines:upsert", machine),
    remove: (id: string) => ipcRenderer.invoke("machines:remove", id) as Promise<RemoteMachine[]>
  },
  settings: {
    get: () => ipcRenderer.invoke("settings:get") as Promise<AppSettings>,
    update: (patch: Partial<AppSettings>) => ipcRenderer.invoke("settings:update", patch) as Promise<AppSettings>
  },
  workspace: {
    load: (threadID: string) => ipcRenderer.invoke("workspace:load", threadID) as Promise<TerminalTabRecord[]>,
    save: (threadID: string, tabs: TerminalTabRecord[]) =>
      ipcRenderer.invoke("workspace:save", threadID, tabs),
    nextTabTitle: (titles: string[]) =>
      ipcRenderer.invoke("workspace:next-tab-title", titles) as Promise<{ number: number; title: string }>
  },
  terminal: {
    create: (spec: {
      tabID: string;
      threadID: string;
      cwd: string | null;
      startupCommand: string | null;
    }) => ipcRenderer.invoke("terminal:create", spec),
    write: (tabID: string, data: string) => ipcRenderer.send("terminal:write", tabID, data),
    resize: (tabID: string, cols: number, rows: number) =>
      ipcRenderer.send("terminal:resize", tabID, cols, rows),
    terminate: (tabIDs: string[], threadID: string) =>
      ipcRenderer.invoke("terminal:terminate", tabIDs, threadID),
    onData: (handler: (tabID: string, data: string) => void) => {
      const listener = (_event: unknown, tabID: string, data: string) => handler(tabID, data);
      ipcRenderer.on("terminal:data", listener);
      return () => {
        ipcRenderer.removeListener("terminal:data", listener);
      };
    }
  },
  activity: {
    states: (threadID: string, tabIDs: string[]) =>
      ipcRenderer.invoke("activity:states", threadID, tabIDs),
    attention: (selectedThreadID: string | null, isAppActive: boolean) =>
      ipcRenderer.invoke("activity:attention", selectedThreadID, isAppActive),
    onChanged: (handler: (snapshot: Record<string, string[]>) => void) => {
      const listener = (_event: unknown, snapshot: Record<string, string[]>) => handler(snapshot);
      ipcRenderer.on("activity:changed", listener);
      return () => {
        ipcRenderer.removeListener("activity:changed", listener);
      };
    }
  },
  menu: {
    on: (handler: (channel: string, payload?: unknown) => void) => {
      const channels = [
        "menu:new-thread",
        "menu:open-thread",
        "menu:rename-thread",
        "menu:new-tab",
        "menu:select-tab",
        "menu:search",
        "menu:toggle-sidebar",
        "menu:settings",
        "app:focus"
      ];
      const listeners = channels.map((channel) => {
        const listener = (_event: unknown, payload?: unknown) => handler(channel, payload);
        ipcRenderer.on(channel, listener);
        return () => {
          ipcRenderer.removeListener(channel, listener);
        };
      });
      return () => {
        listeners.forEach((unsubscribe) => unsubscribe());
      };
    }
  },
  shell: {
    openExternal: (url: string) => ipcRenderer.invoke("shell:open-external", url)
  }
};

contextBridge.exposeInMainWorld("fission", api);

export type FissionAPI = typeof api;

declare global {
  interface Window {
    fission: FissionAPI;
  }
}
