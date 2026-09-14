import { useEffect, useMemo, useState } from "react";
import * as gitWorktreeBranch from "@shared/gitWorktreeBranch";
import { normalizedDirectory } from "@shared/moshCommand";
import type { AgentThread, NewThreadRequest, ProjectPath, RemoteMachine } from "@shared/types";
import type { AppSettings } from "@shared/settings";

type Props = {
  recentPaths: string[];
  machines: RemoteMachine[];
  threads: AgentThread[];
  settings: AppSettings;
  homePath: string;
  onSettingsChange: (patch: Partial<AppSettings>) => Promise<void>;
  onCreate: (request: NewThreadRequest) => Promise<void>;
  onOpenSettings: () => void;
  onCancel: () => void;
};

export function NewThreadModal(props: Props) {
  const location = props.settings.newThreadLocation;
  const isolate = props.settings.createThreadsInNewIsolate;
  const [query, setQuery] = useState("");
  const [remotePath, setRemotePath] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [selectedMachineID, setSelectedMachineID] = useState(props.machines[0]?.id ?? "");
  const [projects, setProjects] = useState<ProjectPath[]>([]);
  const [listingPending, setListingPending] = useState(false);
  const [step, setStep] = useState<"project" | "isolateBranch">("project");
  const [branchName, setBranchName] = useState("");
  const [creating, setCreating] = useState(false);

  const selectedMachine = props.machines.find((machine) => machine.id === selectedMachineID) ?? props.machines[0];

  useEffect(() => {
    if (selectedMachine && remotePath.length === 0) {
      setRemotePath(selectedMachine.projectPath ?? "");
    }
  }, [selectedMachine, remotePath.length]);

  useEffect(() => {
    if (location !== "local") {
      return;
    }
    let cancelled = false;
    void window.fission.projects.list(query).then((result) => {
      if (!cancelled) {
        setProjects(result);
        setSelectedIndex(result.length === 0 ? -1 : 0);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [location, query]);

  useEffect(() => {
    if (location !== "remote" || !selectedMachine) {
      return;
    }
    let cancelled = false;
    setListingPending(true);
    void window.fission.projects.listRemote(selectedMachine.id, remotePath).then((result: { projects: ProjectPath[] }) => {
      if (!cancelled) {
        setProjects(result.projects);
        setSelectedIndex(result.projects.length === 0 ? -1 : 0);
        setListingPending(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [location, selectedMachine, remotePath]);

  const canCreate = useMemo(() => {
    if (step === "isolateBranch") {
      const branch = gitWorktreeBranch.normalized(branchName);
      return branch == null || gitWorktreeBranch.isValid(branch);
    }
    if (location === "local") {
      return projects.length > 0;
    }
    return selectedMachine != null && normalizedDirectory(projects[selectedIndex]?.path ?? "") != null;
  }, [step, branchName, location, projects, selectedIndex, selectedMachine]);

  function move(offset: number) {
    if (projects.length === 0) {
      return;
    }
    setSelectedIndex(Math.min(Math.max(selectedIndex + offset, 0), projects.length - 1));
  }

  async function createSelected() {
    if (creating || !canCreate) {
      return;
    }
    if (location === "local") {
      const project = projects[selectedIndex];
      if (!project) {
        return;
      }
      if (isolate && step === "project") {
        setStep("isolateBranch");
        return;
      }
      setCreating(true);
      await props.onCreate({
        kind: "local",
        directory: project.path,
        createIsolate: isolate,
        branchName: isolate ? gitWorktreeBranch.normalized(branchName) : null
      });
      setCreating(false);
      return;
    }
    if (!selectedMachine) {
      return;
    }
    const path = normalizedDirectory(projects[selectedIndex]?.path);
    if (!path) {
      return;
    }
    setCreating(true);
    await props.onCreate({ kind: "remote", machineID: selectedMachine.id, projectPath: path });
    setCreating(false);
  }

  return (
    <div className="modal-backdrop" onKeyDown={(event) => {
      if (creating) {
        return;
      }
      if (event.key === "Escape") {
        if (step === "isolateBranch") {
          setStep("project");
        } else {
          props.onCancel();
        }
      }
      if (step === "project" && event.key === "ArrowDown") {
        event.preventDefault();
        move(1);
      }
      if (step === "project" && event.key === "ArrowUp") {
        event.preventDefault();
        move(-1);
      }
      if (step === "project" && event.key === "Tab") {
        event.preventDefault();
        const project = projects[selectedIndex];
        if (project) {
          if (location === "local") {
            setQuery(project.path + "/");
          } else {
            setRemotePath(project.path + "/");
          }
        }
      }
      if (event.key === "Enter") {
        event.preventDefault();
        void createSelected();
      }
    }}>
      <div className="modal" role="dialog" aria-label="New Thread">
        <div className="modal-header">
          <div style={{ display: "flex" }}>
            <div style={{ flex: 1 }}>
              <h2>New Thread</h2>
              <p>
                {step === "isolateBranch"
                  ? "Name the Git branch for this isolated workspace."
                  : location === "local"
                    ? "Choose the project directory where the agent should work."
                    : "Choose a remote machine, then pick a folder. Available directories at that path are listed."}
              </p>
            </div>
            <button type="button" className="icon-button" aria-label="Close" onClick={props.onCancel}>
              ×
            </button>
          </div>
          {step === "project" && (
            <div className="segmented" data-testid="new-thread-location-picker">
              <button
                type="button"
                className={location === "local" ? "selected" : ""}
                data-testid="new-thread-location-local"
                onClick={() => void props.onSettingsChange({ newThreadLocation: "local" })}
              >
                This Mac
              </button>
              <button
                type="button"
                className={location === "remote" ? "selected" : ""}
                data-testid="new-thread-location-remote"
                onClick={() => void props.onSettingsChange({ newThreadLocation: "remote" })}
              >
                Remote
              </button>
            </div>
          )}
          {step === "project" && (
            <div className="field">
              <label>Project folder</label>
              <div className="field-control">
                <span>⌕</span>
                <input
                  data-testid={location === "local" ? "project-path-field" : "remote-project-path-field"}
                  aria-label="Project folder"
                  placeholder="Search projects or enter ./, ~/, or /"
                  value={location === "local" ? query : remotePath}
                  autoFocus
                  onChange={(event) =>
                    location === "local" ? setQuery(event.target.value) : setRemotePath(event.target.value)
                  }
                />
              </div>
            </div>
          )}
          {step === "isolateBranch" && (
            <div className="field" data-testid="new-thread-branch-step">
              <label>Branch name</label>
              <div className="field-control">
                <input
                  data-testid="isolate-branch-field"
                  aria-label="Isolate branch name"
                  placeholder="Leave blank to generate"
                  value={branchName}
                  autoFocus
                  onChange={(event) => setBranchName(event.target.value)}
                />
              </div>
            </div>
          )}
        </div>

        {step === "project" && location === "remote" && props.machines.length > 0 && (
          <div className="field" style={{ padding: "0 24px 8px" }}>
            <label>Machine</label>
            <select
              data-testid="remote-machine-picker"
              value={selectedMachine?.id ?? ""}
              onChange={(event) => setSelectedMachineID(event.target.value)}
            >
              {props.machines.map((machine) => (
                <option key={machine.id} value={machine.id}>
                  {machine.name || `${machine.username}@${machine.host}`}
                </option>
              ))}
            </select>
          </div>
        )}

        <div className="project-list" data-testid={location === "remote" && props.machines.length === 0 ? "remote-machine-list" : "new-thread-project-list"}>
          {location === "remote" && props.machines.length === 0 && (
            <div className="empty">
              <div>
                <strong>No Remote Machines</strong>
                <p>Add a host in Settings, then open it as a remote Thread.</p>
                <button
                  type="button"
                  data-testid="open-remote-machine-settings"
                  onClick={props.onOpenSettings}
                >
                  Open Settings
                </button>
              </div>
            </div>
          )}
          {listingPending && (
            <div className="empty" data-testid="remote-directory-listing">Listing directories…</div>
          )}
          {!listingPending &&
            projects.map((project, index) => (
              <button
                type="button"
                key={project.path}
                className={`project-row${index === selectedIndex ? " selected" : ""}`}
                data-testid={`new-thread-project-${project.name}`}
                onClick={() => setSelectedIndex(index)}
                onDoubleClick={() => void createSelected()}
              >
                <div>
                  <div>{project.name}</div>
                  <small>{project.displayPath}</small>
                </div>
              </button>
            ))}
        </div>

        <div className="modal-footer">
          {step === "isolateBranch" ? (
            <button
              type="button"
              data-testid="new-thread-back-button"
              onClick={() => setStep("project")}
            >
              ← Back
            </button>
          ) : (
            <span>Navigate · Complete · Select · Close</span>
          )}
          {location === "local" && step === "project" && (
            <label>
              <input
                type="checkbox"
                data-testid="isolate-toggle"
                checked={isolate}
                onChange={(event) =>
                  void props.onSettingsChange({ createThreadsInNewIsolate: event.target.checked })
                }
              />
              New isolated workspace
            </label>
          )}
          <button
            type="button"
            className="primary"
            data-testid="create-thread-button"
            disabled={!canCreate || creating}
            onClick={() => void createSelected()}
          >
            Create Thread
          </button>
        </div>
        {creating && (
          <div className="overlay" data-testid="creating-thread-progress" aria-label="Creating Thread">
            <div className="overlay-card">Creating Thread…</div>
          </div>
        )}
      </div>
    </div>
  );
}
