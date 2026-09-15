import { app, BrowserWindow, Menu, Notification, ipcMain, shell, dialog, clipboard } from "electron";
import { userInfo } from "node:os";
import { readdirSync, statSync } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { AgentActivityService, installPiExtension } from "./activity";
import {
  databasePath,
  recentProjectsPath,
  remoteMachinesPath,
  settingsPath,
  workspaceStatePath,
  homePath
} from "./paths";
import { RemoteMachineStore } from "./remoteStore";
import { RecentProjectStore, ThreadService } from "./threadService";
import { TerminalManager } from "./terminals";
import { WorkspacePersistence } from "./workspacePersistence";
import { SettingsStore } from "./settings";
import { listRemoteDirectories } from "./remoteDirectories";
import { localProjects, remoteProjects } from "@shared/projectPathResolver";
import { resolvedListingTarget, normalizeRemoteQuery } from "@shared/projectPathQuery";
import { nextNumber, title as tabTitle } from "@shared/terminalTabNaming";
import { currentBranch } from "@shared/gitBranch";
import { newThreadId, type TerminalTabRecord } from "@shared/types";
import {
  decision,
  denialMessage,
  displayString,
  handlerDescription,
  type TerminalURLSource
} from "@shared/terminalURLPolicy";
import { pasteText, storePastedImage } from "@shared/terminalInput";
import { loadGhosttyAppearance } from "@shared/ghosttyConfig";

process.on("uncaughtException", (error) => {
  console.error(error);
});

installPiExtension();

if (process.platform === "linux") {
  app.commandLine.appendSwitch("no-sandbox");
  app.disableHardwareAcceleration();
}

let remotes: RemoteMachineStore;
let threads: ThreadService;
let recents: RecentProjectStore;
let workspaces: WorkspacePersistence;
let settings: SettingsStore;
const terminals = new TerminalManager();
const activity = new AgentActivityService((title, body, threadID) => {
  if (!Notification.isSupported()) {
    return;
  }
  const notification = new Notification({ title, body: body || undefined });
  notification.on("click", () => {
    mainWindow?.show();
    mainWindow?.webContents.send("menu:open-thread-id", threadID);
  });
  notification.show();
});

let mainWindow: BrowserWindow | null = null;

function showUpdateUnavailable(): void {
  dialog.showMessageBox({
    type: "info",
    message: "Updates are unavailable in this build",
    detail: "Development builds do not contact the production update feed."
  });
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 900,
    minHeight: 560,
    title: "Fission",
    backgroundColor: "#1c1c1e",
    trafficLightPosition: { x: 16, y: 16 },
    titleBarStyle: process.platform === "darwin" ? "hiddenInset" : "default",
    webPreferences: {
      preload: fileURLToPath(new URL("../preload/index.mjs", import.meta.url)),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  terminals.attach(mainWindow);
  activity.attach(mainWindow);

  if (process.env.ELECTRON_RENDERER_URL) {
    void mainWindow.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void mainWindow.loadFile(fileURLToPath(new URL("../renderer/index.html", import.meta.url)));
  }

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
  mainWindow.on("focus", () => {
    mainWindow?.webContents.send("app:focus", true);
  });
  mainWindow.on("blur", () => {
    mainWindow?.webContents.send("app:focus", false);
  });
}

function buildMenu(): void {
  const isMac = process.platform === "darwin";
  const template: Electron.MenuItemConstructorOptions[] = [
    ...(isMac
      ? [{
          label: app.name,
          submenu: [
            { role: "about" as const },
            {
              label: "Check for Updates…",
              click: () => {
                showUpdateUnavailable();
              }
            },
            { type: "separator" as const },
            { role: "services" as const },
            { type: "separator" as const },
            { role: "hide" as const },
            { role: "hideOthers" as const },
            { role: "unhide" as const },
            { type: "separator" as const },
            { role: "quit" as const }
          ]
        }]
      : []),
    {
      label: "File",
      submenu: [
        {
          label: "New Thread",
          accelerator: "CommandOrControl+N",
          click: () => mainWindow?.webContents.send("menu:new-thread")
        },
        {
          label: "Open Thread…",
          accelerator: "CommandOrControl+P",
          click: () => mainWindow?.webContents.send("menu:open-thread")
        },
        {
          label: "Rename Thread",
          accelerator: "CommandOrControl+Shift+R",
          click: () => mainWindow?.webContents.send("menu:rename-thread")
        },
        { type: "separator" },
        {
          label: "New Terminal Tab",
          accelerator: "CommandOrControl+T",
          click: () => mainWindow?.webContents.send("menu:new-tab")
        },
        ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map((number) => ({
          label: `Select Terminal Tab ${number}`,
          accelerator: `CommandOrControl+${number}`,
          click: () => mainWindow?.webContents.send("menu:select-tab", number - 1)
        })),
        { type: "separator" },
        ...(!isMac
          ? [
              {
                label: "Check for Updates…",
                click: () => {
                  showUpdateUnavailable();
                }
              } satisfies Electron.MenuItemConstructorOptions,
              { type: "separator" as const }
            ]
          : []),
        isMac ? { role: "close" as const } : { role: "quit" as const }
      ]
    },
    { role: "editMenu" },
    {
      label: "Find",
      submenu: [
        {
          label: "Find…",
          accelerator: "CommandOrControl+F",
          click: () => mainWindow?.webContents.send("menu:search", "open")
        },
        {
          label: "Find Next",
          accelerator: "CommandOrControl+G",
          click: () => mainWindow?.webContents.send("menu:search", "next")
        },
        {
          label: "Find Previous",
          accelerator: "CommandOrControl+Shift+G",
          click: () => mainWindow?.webContents.send("menu:search", "previous")
        },
        {
          label: "Hide Find Bar",
          accelerator: "CommandOrControl+Shift+F",
          click: () => mainWindow?.webContents.send("menu:search", "close")
        },
        {
          label: "Use Selection for Find",
          accelerator: "CommandOrControl+E",
          click: () => mainWindow?.webContents.send("menu:search", "useSelection")
        }
      ]
    },
    {
      label: "View",
      submenu: [
        {
          label: "Toggle Sidebar",
          accelerator: "CommandOrControl+B",
          click: () => mainWindow?.webContents.send("menu:toggle-sidebar")
        },
        {
          label: "Toggle Sidebar (Command-S)",
          accelerator: "CommandOrControl+S",
          click: () => mainWindow?.webContents.send("menu:toggle-sidebar")
        },
        { type: "separator" },
        { role: "reload" },
        { role: "toggleDevTools" },
        { type: "separator" },
        {
          label: "Settings",
          accelerator: "CommandOrControl+,",
          click: () => mainWindow?.webContents.send("menu:settings")
        }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function registerIpc(): void {
  ipcMain.handle("bootstrap", () => {
    const loaded = threads.load();
    activity.synchronizeThreads(loaded);
    return {
      threads: loaded,
      machines: remotes.list(),
      recentProjects: recents.load(),
      settings: settings.get(),
      homePath: homePath(),
      username: userInfo().username,
      terminalAppearance: loadGhosttyAppearance()
    };
  });

  ipcMain.handle("threads:create", (_event, request) => {
    const thread = threads.create(request);
    if (request.kind === "local") {
      recents.record(request.directory);
    }
    activity.synchronizeThreads(threads.list());
    return { thread, threads: threads.list(), recentProjects: recents.load(), machines: remotes.list() };
  });

  ipcMain.handle("threads:rename", (_event, threadID: string, title: string) => threads.rename(threadID, title));
  ipcMain.handle("threads:settle", (_event, threadID: string) => {
    const records = workspaces.load(threadID);
    terminals.terminate(records.map((record) => record.id));
    workspaces.remove(threadID);
    activity.forget(threadID);
    return threads.settle(threadID);
  });
  ipcMain.handle("threads:reopen", (_event, threadID: string) => threads.reopen(threadID));
  ipcMain.handle("threads:delete", (_event, ids: string[]) => {
    for (const id of ids) {
      terminals.terminate(workspaces.load(id).map((record) => record.id));
      workspaces.remove(id);
      activity.forget(id);
    }
    return threads.delete(ids);
  });
  ipcMain.handle("threads:reorder", (_event, ids: string[]) => threads.reorderActive(ids));
  ipcMain.handle("threads:git-branch", (_event, workingDirectory: string | null) =>
    currentBranch(workingDirectory)
  );

  ipcMain.handle("projects:list", (_event, query: string) => localProjects(query, recents.load(), homePath()));
  ipcMain.handle("projects:list-remote", async (_event, machineID: string, projectPath: string) => {
    const machine = remotes.machine(machineID);
    if (!machine) {
      return { listing: { kind: "failed" }, projects: [] };
    }
    const target = resolvedListingTarget(
      normalizeRemoteQuery(projectPath),
      machine.projectPath,
      () => null
    );
    const directory = target?.directory ?? "~";
    const listing = await listRemoteDirectories(
      machine,
      directory,
      process.env.FISSION_REMOTE_DIRECTORY_LISTING
    );
    return {
      listing,
      directory,
      namePrefix: target?.namePrefix ?? "",
      projects: remoteProjects(
        directory,
        target?.namePrefix ?? "",
        listing.kind === "contents" ? listing : null
      )
    };
  });

  ipcMain.handle("machines:list", () => remotes.list());
  ipcMain.handle("machines:upsert", (_event, machine) => remotes.upsert(machine));
  ipcMain.handle("machines:remove", (_event, id: string) => {
    remotes.remove(id);
    return remotes.list();
  });

  ipcMain.handle("settings:get", () => settings.get());
  ipcMain.handle("settings:update", (_event, patch) => {
    const next = settings.update(patch);
    activity.notifyWhenFinished = next.notifyWhenAgentFinishes;
    return next;
  });

  ipcMain.handle("workspace:load", (_event, threadID: string) => {
    const records = workspaces.load(threadID);
    if (records.length === 0) {
      const tab = defaultTab();
      workspaces.save(threadID, [tab]);
      return [tab];
    }
    return records;
  });
  ipcMain.handle("workspace:save", (_event, threadID: string, tabs: TerminalTabRecord[]) => {
    workspaces.save(threadID, tabs);
  });
  ipcMain.handle("workspace:next-tab-title", (_event, titles: string[]) => {
    const number = nextNumber(titles);
    return { number, title: tabTitle(number) };
  });

  ipcMain.handle("terminal:create", async (_event, spec) => {
    await terminals.create({
      ...spec,
      environment: activity.environment(spec.threadID, spec.tabID)
    });
  });
  ipcMain.on("terminal:write", (_event, tabID: string, data: string) => {
    terminals.write(tabID, data);
  });
  ipcMain.on("terminal:resize", (_event, tabID: string, cols: number, rows: number) => {
    terminals.resize(tabID, cols, rows);
  });
  ipcMain.handle("terminal:terminate", (_event, tabIDs: string[], threadID: string) => {
    terminals.terminate(tabIDs);
    for (const tabID of tabIDs) {
      activity.forget(threadID, tabID);
    }
  });

  ipcMain.handle("activity:states", (_event, threadID: string, tabIDs: string[]) =>
    activity.states(threadID, tabIDs)
  );
  ipcMain.handle("activity:attention", (_event, selectedThreadID: string | null, isAppActive: boolean) => {
    activity.updateAttention(selectedThreadID, isAppActive);
  });

  ipcMain.handle("shell:open-external", (_event, url: string) => shell.openExternal(url));
  ipcMain.handle("terminal:open-url", async (_event, rawURL: string, source: TerminalURLSource) => {
    await openTerminalURL(rawURL, source);
  });
  ipcMain.handle("terminal:stage-image", () => {
    if (clipboard.readText().length > 0) {
      return null;
    }
    const image = clipboard.readImage();
    if (image.isEmpty()) {
      return null;
    }
    const path = storePastedImage(image.toPNG(), "png");
    return pasteText([path], null);
  });
  ipcMain.handle("terminal:escape-paths", (_event, paths: string[]) => pasteText(paths, null));
  ipcMain.handle("notifications:request", async () => {
    if (!Notification.isSupported()) {
      return false;
    }
    return true;
  });
  ipcMain.handle("fs:is-directory", (_event, path: string) => {
    try {
      return statSync(path).isDirectory();
    } catch {
      return false;
    }
  });
  ipcMain.handle("fs:list", (_event, path: string) => {
    try {
      return readdirSync(path);
    } catch {
      return [];
    }
  });
}

function defaultTab(): TerminalTabRecord {
  const id = newThreadId();
  return { id, number: 1, title: "Tab 1", isSelected: true };
}

async function openTerminalURL(rawURL: string, source: TerminalURLSource): Promise<void> {
  const shown = displayString(rawURL);
  const result = decision({ rawValue: rawURL, source });
  switch (result.kind) {
    case "open":
      await openDecidedURL(result.url, result.method);
      return;
    case "confirm": {
      const { response } = await dialog.showMessageBox({
        type: "warning",
        message: "Open Link from Terminal Output?",
        detail: `This link will open in ${handlerDescription(null)}. Only continue if you recognize and trust the destination.\n\n${shown}`,
        buttons: ["Cancel", "Open Link"],
        defaultId: 0,
        cancelId: 0
      });
      if (response === 1) {
        await shell.openExternal(result.url);
      }
      return;
    }
    case "deny": {
      const { response } = await dialog.showMessageBox({
        type: "warning",
        message: "Fission Blocked This Link",
        detail: `${denialMessage[result.reason]}\n\n${shown}`,
        buttons: ["OK", "Copy Link"],
        defaultId: 0
      });
      if (response === 1) {
        clipboard.writeText(shown);
      }
    }
  }
}

async function openDecidedURL(url: string, method: "defaultApplication" | "textEditor"): Promise<void> {
  if (url.startsWith("file:")) {
    const path = fileURLToPath(url);
    if (method === "textEditor" && process.platform === "darwin") {
      spawn("open", ["-t", path], { detached: true, stdio: "ignore" }).unref();
      return;
    }
    await shell.openPath(path);
    return;
  }
  await shell.openExternal(url);
}

app.whenReady().then(async () => {
  remotes = new RemoteMachineStore(remoteMachinesPath());
  threads = await ThreadService.create(databasePath(), remotes);
  recents = new RecentProjectStore(recentProjectsPath());
  workspaces = new WorkspacePersistence(workspaceStatePath());
  settings = new SettingsStore(settingsPath());
  activity.notifyWhenFinished = settings.get().notifyWhenAgentFinishes;
  activity.tabIDsForThread = (threadID) => workspaces.tabIDs(threadID);
  registerIpc();
  buildMenu();
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("before-quit", () => {
  terminals.detach();
  activity.close();
});
