import { useEffect, useMemo, useState } from "react";
import {
  isRemoteThread,
  isSettled,
  projectDisplayName,
  type AgentThread
} from "@shared/types";

type Props = {
  threads: AgentThread[];
  selectedThreadID: string | null;
  activity: Record<string, string[]>;
  renameSignal: number;
  createdThreadID: string | null;
  onSelect: (id: string) => void;
  onCreate: () => void;
  onRename: (id: string, title: string) => Promise<void>;
  onSettle: (id: string) => Promise<void>;
  onReopen: (id: string) => Promise<void>;
  onDelete: (ids: string[]) => Promise<void>;
  onReorder: (ids: string[]) => Promise<void>;
};

type MenuState = { x: number; y: number; thread: AgentThread } | null;

export function Sidebar(props: Props) {
  const [editingID, setEditingID] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [branches, setBranches] = useState<Record<string, string | null>>({});
  const [settledOpen, setSettledOpen] = useState(true);
  const [settledLimit, setSettledLimit] = useState(20);
  const [dragID, setDragID] = useState<string | null>(null);
  const [menu, setMenu] = useState<MenuState>(null);
  const [confirmDelete, setConfirmDelete] = useState<AgentThread | null>(null);

  const active = useMemo(
    () => props.threads.filter((thread) => !isSettled(thread)),
    [props.threads]
  );
  const settled = useMemo(
    () =>
      props.threads
        .filter(isSettled)
        .sort((left, right) => right.updatedAt - left.updatedAt),
    [props.threads]
  );
  const visibleSettled = settled.slice(0, settledLimit);

  useEffect(() => {
    if (props.renameSignal === 0 || !props.selectedThreadID) {
      return;
    }
    const thread = props.threads.find((item) => item.id === props.selectedThreadID);
    if (thread) {
      setEditingID(thread.id);
      setDraft(thread.title);
    }
  }, [props.renameSignal, props.selectedThreadID, props.threads]);

  useEffect(() => {
    for (const thread of active) {
      if (isRemoteThread(thread) || branches[thread.id] !== undefined) {
        continue;
      }
      void window.fission.threads.gitBranch(thread.workingDirectory).then((branch) => {
        setBranches((current) => ({ ...current, [thread.id]: branch }));
      });
    }
  }, [active, branches]);

  useEffect(() => {
    if (!props.createdThreadID) {
      return;
    }
    document.getElementById(`thread-${props.createdThreadID}`)?.scrollIntoView({ block: "start" });
  }, [props.createdThreadID]);

  function beginRename(thread: AgentThread) {
    setEditingID(thread.id);
    setDraft(thread.title);
    setMenu(null);
  }

  async function commitRename() {
    if (!editingID) {
      return;
    }
    const title = draft;
    setEditingID(null);
    await props.onRename(editingID, title);
  }

  return (
    <aside className="sidebar">
      <div className="toolbar">
        <div className="toolbar-title">Threads</div>
        <button
          type="button"
          className="icon-button"
          data-testid="new-thread-button"
          aria-label="New Thread"
          onClick={props.onCreate}
        >
          +
        </button>
      </div>
      <div className="thread-list" data-testid="thread-sidebar-list">
        {active.map((thread) => (
          <ThreadRow
            key={thread.id}
            thread={thread}
            selected={props.selectedThreadID === thread.id}
            activity={props.activity[thread.id] ?? []}
            branch={branches[thread.id]}
            editing={editingID === thread.id}
            draft={draft}
            onDraft={setDraft}
            onSelect={() => props.onSelect(thread.id)}
            onBeginRename={() => beginRename(thread)}
            onCommitRename={() => void commitRename()}
            onCancelRename={() => setEditingID(null)}
            onSettle={() => void props.onSettle(thread.id)}
            onReopen={() => undefined}
            onContextMenu={(event) => {
              event.preventDefault();
              setMenu({ x: event.clientX, y: event.clientY, thread });
            }}
            draggable
            dragging={dragID === thread.id}
            onDragStart={() => setDragID(thread.id)}
            onDrop={() => {
              if (!dragID || dragID === thread.id) {
                return;
              }
              const ids = active.map((item) => item.id);
              const from = ids.indexOf(dragID);
              const to = ids.indexOf(thread.id);
              ids.splice(from, 1);
              ids.splice(to, 0, dragID);
              void props.onReorder(ids);
              setDragID(null);
            }}
          />
        ))}
        {settled.length > 0 && (
          <>
            <button
              type="button"
              className="settled-toggle"
              onClick={() => setSettledOpen((open) => !open)}
              aria-label={settledOpen ? "Hide settled threads" : "Show settled threads"}
            >
              <span>{settledOpen ? "▾" : "▸"}</span>
              <span>Settled</span>
              <span>{settled.length}</span>
            </button>
            {settledOpen &&
              visibleSettled.map((thread) => (
                <ThreadRow
                  key={thread.id}
                  thread={thread}
                  selected={false}
                  activity={props.activity[thread.id] ?? []}
                  branch={null}
                  editing={editingID === thread.id}
                  draft={draft}
                  onDraft={setDraft}
                  onSelect={() => undefined}
                  onBeginRename={() => beginRename(thread)}
                  onCommitRename={() => void commitRename()}
                  onCancelRename={() => setEditingID(null)}
                  onSettle={() => undefined}
                  onReopen={() => void props.onReopen(thread.id)}
                  onContextMenu={(event) => {
                    event.preventDefault();
                    setMenu({ x: event.clientX, y: event.clientY, thread });
                  }}
                />
              ))}
            {settledOpen && settled.length > visibleSettled.length && (
              <button
                type="button"
                className="load-more"
                data-testid="load-more-settled-threads"
                onClick={() => setSettledLimit((limit) => limit + 20)}
              >
                Load more ({settled.length - visibleSettled.length} remaining)
              </button>
            )}
          </>
        )}
      </div>
      {menu && (
        <div className="menu-backdrop" onClick={() => setMenu(null)}>
          <div
            className="context-menu"
            style={{ left: menu.x, top: menu.y }}
            onClick={(event) => event.stopPropagation()}
          >
            <button
              type="button"
              onClick={() => {
                beginRename(menu.thread);
              }}
            >
              Rename
            </button>
            <hr />
            {isSettled(menu.thread) ? (
              <button
                type="button"
                onClick={() => {
                  setMenu(null);
                  void props.onReopen(menu.thread.id);
                }}
              >
                Reopen
              </button>
            ) : (
              <>
                <button type="button" disabled title="Snooze — coming soon">
                  Snooze
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setMenu(null);
                    void props.onSettle(menu.thread.id);
                  }}
                >
                  Settle
                </button>
              </>
            )}
            <hr />
            <button
              type="button"
              className="danger"
              onClick={() => {
                setConfirmDelete(menu.thread);
                setMenu(null);
              }}
            >
              Delete
            </button>
          </div>
        </div>
      )}
      {confirmDelete && (
        <div className="alert">
          <div className="alert-card">
            <h3>Delete Thread?</h3>
            <p>This removes “{confirmDelete.title}” and its terminals.</p>
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
              <button type="button" onClick={() => setConfirmDelete(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="primary"
                onClick={() => {
                  const id = confirmDelete.id;
                  setConfirmDelete(null);
                  void props.onDelete([id]);
                }}
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </aside>
  );
}

function ThreadRow(props: {
  thread: AgentThread;
  selected: boolean;
  activity: string[];
  branch: string | null | undefined;
  editing: boolean;
  draft: string;
  onDraft: (value: string) => void;
  onSelect: () => void;
  onBeginRename: () => void;
  onCommitRename: () => void;
  onCancelRename: () => void;
  onSettle: () => void;
  onReopen: () => void;
  onContextMenu: (event: React.MouseEvent) => void;
  draggable?: boolean;
  dragging?: boolean;
  onDragStart?: () => void;
  onDrop?: () => void;
}) {
  const thread = props.thread;
  return (
    <div
      id={`thread-${thread.id}`}
      className={`thread-row${props.selected ? " selected" : ""}${isSettled(thread) ? " settled" : ""}${props.dragging ? " drag-over" : ""}`}
      draggable={props.draggable}
      onClick={props.onSelect}
      onContextMenu={props.onContextMenu}
      onDragStart={props.onDragStart}
      onDragOver={(event) => event.preventDefault()}
      onDrop={props.onDrop}
    >
      <div className="thread-meta">
        <span>{isRemoteThread(thread) ? "↗" : "📁"}</span>
        <span title={thread.workingDirectory ?? "No project folder"}>
          {projectDisplayName(thread)}
        </span>
        <div className="thread-actions">
          {isSettled(thread) ? (
            <button type="button" className="icon-button" aria-label="Reopen Thread" onClick={props.onReopen}>
              ↩
            </button>
          ) : (
            <>
              <button
                type="button"
                className="icon-button"
                aria-label="Snooze Thread"
                title="Snooze — coming soon"
                disabled
              >
                ⏱
              </button>
              <button type="button" className="icon-button" aria-label="Settle Thread" onClick={props.onSettle}>
                ✓
              </button>
            </>
          )}
        </div>
      </div>
      {props.editing ? (
        <input
          className="rename-field"
          value={props.draft}
          aria-label="Thread title"
          autoFocus
          onChange={(event) => props.onDraft(event.target.value)}
          onBlur={props.onCommitRename}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              props.onCommitRename();
            }
            if (event.key === "Escape") {
              props.onCancelRename();
            }
          }}
        />
      ) : (
        <div className="thread-title">{thread.title}</div>
      )}
      <div className="thread-footer">
        <span>{props.branch ?? ""}</span>
        <span className="activity" aria-label="Agent statuses">
          {props.activity.slice(0, 10).map((state, index) => (
            <span
              key={`${state}-${index}`}
              className={`dot${state === "idle" ? "" : state === "finished" ? " done" : " fill"}`}
              aria-label={state === "idle" ? "Idle agent" : state === "finished" ? "Finished agent" : "Working agent"}
            />
          ))}
        </span>
      </div>
    </div>
  );
}
