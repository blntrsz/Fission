import { useEffect, useRef, useState } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { SearchAddon } from "@xterm/addon-search";
import { WebLinksAddon } from "@xterm/addon-web-links";
import "@xterm/xterm/css/xterm.css";
import { isRemoteThread, newThreadId, type AgentThread, type TerminalTabRecord } from "@shared/types";

type Command =
  | { kind: "add" }
  | { kind: "select"; index: number }
  | { kind: "search"; command: string }
  | null;

type Props = {
  thread: AgentThread;
  command: Command;
  onCommandHandled: () => void;
};

type LiveTab = TerminalTabRecord & {
  terminal: Terminal;
  fit: FitAddon;
  search: SearchAddon;
};

export function TerminalWorkspace(props: Props) {
  const [tabs, setTabs] = useState<TerminalTabRecord[]>([]);
  const [selectedID, setSelectedID] = useState<string | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState("");
    const [count] = useState("");
  const live = useRef(new Map<string, LiveTab>());
  const hosts = useRef(new Map<string, HTMLDivElement>());
  const threadID = props.thread.id;

  useEffect(() => {
    let cancelled = false;
    void window.fission.workspace.load(threadID).then(async (records) => {
      if (cancelled) {
        return;
      }
      setTabs(records);
      setSelectedID(records.find((tab) => tab.isSelected)?.id ?? records[0]?.id ?? null);
      for (const record of records) {
        await ensureTab(record);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [threadID]);

  useEffect(() => {
    return window.fission.terminal.onData((tabID, data) => {
      live.current.get(tabID)?.terminal.write(data);
    });
  }, []);

  useEffect(() => {
    if (!props.command) {
      return;
    }
    if (props.command.kind === "add") {
      void addTab();
    } else if (props.command.kind === "select") {
      const tab = tabs[props.command.index];
      if (tab) {
        void selectTab(tab.id);
      }
    } else if (props.command.kind === "search") {
      performSearch(props.command.command);
    }
    props.onCommandHandled();
  }, [props.command]);

  async function persist(next: TerminalTabRecord[], selected: string | null) {
    setTabs(next);
    setSelectedID(selected);
    await window.fission.workspace.save(
      threadID,
      next.map((tab) => ({ ...tab, isSelected: tab.id === selected }))
    );
  }

  async function ensureTab(record: TerminalTabRecord) {
    if (live.current.has(record.id)) {
      return;
    }
    const terminal = new Terminal({
      cursorBlink: true,
      fontFamily: "Menlo, Monaco, ui-monospace, monospace",
      fontSize: 13,
      theme: { background: "#111111", foreground: "#f5f5f7" }
    });
    const fit = new FitAddon();
    const searchAddon = new SearchAddon();
    terminal.loadAddon(fit);
    terminal.loadAddon(searchAddon);
    terminal.loadAddon(
      new WebLinksAddon((_event, uri) => {
        void window.fission.shell.openExternal(uri);
      })
    );
    terminal.onData((data) => window.fission.terminal.write(record.id, data));
    live.current.set(record.id, { ...record, terminal, fit, search: searchAddon });
    await window.fission.terminal.create({
      tabID: record.id,
      threadID,
      cwd: isRemoteThread(props.thread) ? null : props.thread.workingDirectory,
      startupCommand: props.thread.remoteCommand
    });
    attach(record.id);
  }

  function attach(tabID: string) {
    const host = hosts.current.get(tabID);
    const tab = live.current.get(tabID);
    if (!host || !tab) {
      return;
    }
    if (!tab.terminal.element) {
      tab.terminal.open(host);
    }
    requestAnimationFrame(() => {
      tab.fit.fit();
      const dims = tab.fit.proposeDimensions();
      if (dims) {
        window.fission.terminal.resize(tabID, dims.cols, dims.rows);
      }
      tab.terminal.focus();
    });
  }

  async function addTab() {
    const nextTitle = await window.fission.workspace.nextTabTitle(tabs.map((tab) => tab.title));
    const record: TerminalTabRecord = {
      id: newThreadId(),
      number: nextTitle.number,
      title: nextTitle.title,
      isSelected: true
    };
    await persist([...tabs, record], record.id);
    await ensureTab(record);
  }

  async function selectTab(tabID: string) {
    await persist(tabs, tabID);
    attach(tabID);
  }

  async function closeTab(tabID: string) {
    await window.fission.terminal.terminate([tabID], threadID);
    live.current.get(tabID)?.terminal.dispose();
    live.current.delete(tabID);
    const remaining = tabs.filter((tab) => tab.id !== tabID);
    if (remaining.length === 0) {
      const nextTitle = await window.fission.workspace.nextTabTitle([]);
      const record: TerminalTabRecord = {
        id: newThreadId(),
        number: nextTitle.number,
        title: nextTitle.title,
        isSelected: true
      };
      await persist([record], record.id);
      await ensureTab(record);
      return;
    }
    const nextSelected = selectedID === tabID ? remaining[Math.max(0, tabs.findIndex((tab) => tab.id === tabID) - 1)]?.id ?? remaining[0].id : selectedID;
    await persist(remaining, nextSelected);
  }

  function performSearch(command: string) {
    const tab = selectedID ? live.current.get(selectedID) : null;
    if (!tab) {
      return;
    }
    if (command === "open") {
      setSearchOpen(true);
    } else if (command === "close") {
      setSearchOpen(false);
      tab.search.clearDecorations();
    } else if (command === "next") {
      tab.search.findNext(query);
    } else if (command === "previous") {
      tab.search.findPrevious(query);
    } else if (command === "useSelection") {
      const selection = tab.terminal.getSelection();
      setQuery(selection);
      setSearchOpen(true);
    }
  }

  return (
    <>
      <div className="tab-bar">
        <div className="tab-scroller" data-testid="terminal-workspace">
          {tabs.map((tab, index) => (
            <button
              type="button"
              key={tab.id}
              className={`tab${tab.id === selectedID ? " selected" : ""}`}
              onClick={() => void selectTab(tab.id)}
              draggable
              onDragStart={(event) => event.dataTransfer.setData("text/plain", tab.id)}
              onDrop={(event) => {
                const fromID = event.dataTransfer.getData("text/plain");
                const from = tabs.findIndex((item) => item.id === fromID);
                if (from < 0 || from === index) {
                  return;
                }
                const next = [...tabs];
                const [moved] = next.splice(from, 1);
                next.splice(index, 0, moved);
                void persist(next, selectedID);
              }}
              onDragOver={(event) => event.preventDefault()}
            >
              {tab.title}
              <span
                className="close"
                role="button"
                aria-label="Close tab"
                onClick={(event) => {
                  event.stopPropagation();
                  void closeTab(tab.id);
                }}
              >
                ×
              </span>
            </button>
          ))}
        </div>
        <button type="button" className="icon-button" aria-label="New Terminal" onClick={() => void addTab()}>
          +
        </button>
      </div>
      <div className="terminal-stack">
        {tabs.map((tab) => (
          <div key={tab.id} className={`terminal-pane${tab.id === selectedID ? "" : " hidden"}`}>
            <div
              className="xterm-host"
              ref={(node) => {
                if (node) {
                  hosts.current.set(tab.id, node);
                  attach(tab.id);
                }
              }}
            />
            {searchOpen && tab.id === selectedID && (
              <div className="search-bar">
                <input
                  data-testid="terminal-search-field"
                  value={query}
                  autoFocus
                  onChange={(event) => {
                    setQuery(event.target.value);
                    live.current.get(tab.id)?.search.findNext(event.target.value);
                  }}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      live.current.get(tab.id)?.search.findNext(query);
                    }
                    if (event.key === "Escape") {
                      setSearchOpen(false);
                    }
                  }}
                />
                <span data-testid="terminal-search-count">{count}</span>
                <button type="button" data-testid="terminal-search-next" onClick={() => live.current.get(tab.id)?.search.findNext(query)}>
                  ↓
                </button>
                <button type="button" data-testid="terminal-search-previous" onClick={() => live.current.get(tab.id)?.search.findPrevious(query)}>
                  ↑
                </button>
                <button type="button" data-testid="terminal-search-close" onClick={() => setSearchOpen(false)}>
                  ×
                </button>
              </div>
            )}
          </div>
        ))}
      </div>
    </>
  );
}
