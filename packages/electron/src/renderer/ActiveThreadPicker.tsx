import { useEffect, useMemo, useState } from "react";
import * as search from "@shared/activeThreadSearch";
import type { AgentThread } from "@shared/types";

type Props = {
  threads: AgentThread[];
  selectedThreadID: string | null;
  onSelect: (id: string) => void;
  onCancel: () => void;
};

export function ActiveThreadPicker(props: Props) {
  const [query, setQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const results = useMemo(() => search.results(query, props.threads), [query, props.threads]);

  useEffect(() => {
    const index = results.findIndex((thread) => thread.id === props.selectedThreadID);
    setSelectedIndex(index >= 0 ? index : 0);
  }, [query, results, props.selectedThreadID]);

  return (
    <div
      className="modal-backdrop"
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          props.onCancel();
        }
        if (event.key === "ArrowDown") {
          event.preventDefault();
          setSelectedIndex((index) => Math.min(index + 1, results.length - 1));
        }
        if (event.key === "ArrowUp") {
          event.preventDefault();
          setSelectedIndex((index) => Math.max(index - 1, 0));
        }
        if (event.key === "Enter" && results[selectedIndex]) {
          props.onSelect(results[selectedIndex].id);
        }
      }}
    >
      <div className="modal small">
        <div className="field-control" style={{ margin: 0, height: 58, border: 0, borderRadius: 0 }}>
          <span>⌕</span>
          <input
            data-testid="active-thread-search-field"
            placeholder="Search active Threads"
            value={query}
            autoFocus
            onChange={(event) => setQuery(event.target.value)}
          />
        </div>
        <div className="project-list">
          {results.map((thread, index) => (
            <button
              type="button"
              key={thread.id}
              className={`project-row${index === selectedIndex ? " selected" : ""}`}
              data-testid={`active-thread-result-${thread.id}`}
              onClick={() => props.onSelect(thread.id)}
            >
              <div>
                <div>{thread.title}</div>
                <small>{search.context(thread)}</small>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
