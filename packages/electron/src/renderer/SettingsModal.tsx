import { useState } from "react";
import { isValidMachine, machineDisplayName, machineTarget } from "@shared/remoteMachine";
import { newThreadId, type RemoteMachine } from "@shared/types";
import type { AppSettings } from "@shared/settings";

type Props = {
  settings: AppSettings;
  machines: RemoteMachine[];
  username: string;
  onSettingsChange: (patch: Partial<AppSettings>) => Promise<void>;
  onMachinesChange: (machines: RemoteMachine[]) => void;
  onClose: () => void;
};

export function SettingsModal(props: Props) {
  const [tab, setTab] = useState<"notifications" | "machines">("notifications");
  const [draft, setDraft] = useState<RemoteMachine | null>(null);

  return (
    <div className="modal-backdrop">
      <div className="modal settings" data-testid="remote-machines-settings">
        <div className="modal-header">
          <div style={{ display: "flex" }}>
            <h2 style={{ flex: 1 }}>Settings</h2>
            <button type="button" className="icon-button" aria-label="Close" onClick={props.onClose}>
              ×
            </button>
          </div>
          <div className="segmented">
            <button type="button" className={tab === "notifications" ? "selected" : ""} onClick={() => setTab("notifications")}>
              Notifications
            </button>
            <button type="button" className={tab === "machines" ? "selected" : ""} onClick={() => setTab("machines")}>
              Remote Machines
            </button>
          </div>
        </div>
        {tab === "notifications" ? (
          <div className="settings-form">
            <label>
              <input
                type="checkbox"
                checked={props.settings.notifyWhenAgentFinishes}
                onChange={(event) =>
                  void props.onSettingsChange({ notifyWhenAgentFinishes: event.target.checked })
                }
              />
              Notify when an agent task finishes
            </label>
          </div>
        ) : (
          <div className="settings-form">
            {props.machines.length === 0 && (
              <p>No remote machines yet. Add a host to open Threads over mosh.</p>
            )}
            {props.machines.map((machine) => (
              <button
                type="button"
                key={machine.id}
                className="machine-row"
                data-testid={`settings-remote-machine-${machine.id}`}
                onClick={() => setDraft(machine)}
              >
                <strong>{machineDisplayName(machine)}</strong>
                <div>{machineTarget(machine)}</div>
                {machine.projectPath && <div>{machine.projectPath}</div>}
              </button>
            ))}
            <button
              type="button"
              className="primary"
              style={{ marginLeft: 0 }}
              data-testid="add-remote-machine-button"
              onClick={() =>
                setDraft({
                  id: newThreadId(),
                  name: "",
                  username: props.username,
                  host: "",
                  sshPort: null,
                  projectPath: null
                })
              }
            >
              Add Machine
            </button>
          </div>
        )}
        {draft && (
          <MachineEditor
            machine={draft}
            onCancel={() => setDraft(null)}
            onSave={async (machine) => {
              const saved = await window.fission.machines.upsert(machine);
              if (saved) {
                props.onMachinesChange(await window.fission.machines.list());
                setDraft(null);
              }
            }}
          />
        )}
      </div>
    </div>
  );
}

function MachineEditor(props: {
  machine: RemoteMachine;
  onSave: (machine: RemoteMachine) => Promise<void>;
  onCancel: () => void;
}) {
  const [name, setName] = useState(props.machine.name);
  const [username, setUsername] = useState(props.machine.username);
  const [host, setHost] = useState(props.machine.host);
  const [port, setPort] = useState(props.machine.sshPort?.toString() ?? "");
  const [projectPath, setProjectPath] = useState(props.machine.projectPath ?? "");
  const draft: RemoteMachine = {
    id: props.machine.id,
    name: name.trim(),
    username: username.trim(),
    host: host.trim(),
    sshPort: port.trim().length === 0 ? null : Number.parseInt(port, 10),
    projectPath
  };

  return (
    <div className="settings-form">
      <h3>Remote Machine</h3>
      <label>Name<input data-testid="remote-machine-name-field" value={name} onChange={(e) => setName(e.target.value)} /></label>
      <label>Username<input data-testid="remote-machine-username-field" value={username} onChange={(e) => setUsername(e.target.value)} /></label>
      <label>Host<input data-testid="remote-machine-host-field" value={host} onChange={(e) => setHost(e.target.value)} /></label>
      <label>SSH port<input data-testid="remote-machine-port-field" placeholder="22" value={port} onChange={(e) => setPort(e.target.value)} /></label>
      <label>Project path<input data-testid="remote-machine-project-path-field" placeholder="~/src/project" value={projectPath} onChange={(e) => setProjectPath(e.target.value)} /></label>
      <div style={{ display: "flex", gap: 8 }}>
        <button type="button" onClick={props.onCancel}>Cancel</button>
        <button
          type="button"
          className="primary"
          data-testid="save-remote-machine-button"
          disabled={!isValidMachine(draft)}
          onClick={() => void props.onSave(draft)}
        >
          Save
        </button>
      </div>
    </div>
  );
}
