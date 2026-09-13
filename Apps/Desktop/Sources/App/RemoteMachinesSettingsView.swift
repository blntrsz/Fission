import FissionCore
import SwiftUI

struct RemoteMachinesSettingsView: View {
    let store: RemoteMachineStore
    @State private var draft: RemoteMachine?
    @State private var isEditorPresented = false

    var body: some View {
        Form {
            Section {
                if store.machines.isEmpty {
                    Text("No remote machines yet. Add a host to open Threads over mosh.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.machines) { machine in
                        Button {
                            draft = machine
                            isEditorPresented = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(machine.displayName)
                                    Text(machine.target)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let projectPath = machine.projectPath {
                                        Text(projectPath)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-remote-machine-\(machine.id.uuidString)")
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.machines[$0].id }
                        for id in ids { store.remove(id: id) }
                    }
                }
            } header: {
                Text("Machines")
            } footer: {
                Text("Remote Threads open a login shell that execs mosh, then cd into the machine's project path.")
            }

            Button("Add Machine") {
                draft = RemoteMachine(name: "", username: NSUserName(), host: "")
                isEditorPresented = true
            }
            .accessibilityIdentifier("add-remote-machine-button")
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 320)
        .accessibilityIdentifier("remote-machines-settings")
        .sheet(isPresented: $isEditorPresented) {
            RemoteMachineEditor(
                machine: draft ?? RemoteMachine(name: "", username: "", host: ""),
                save: { machine in
                    store.upsert(machine)
                    isEditorPresented = false
                },
                cancel: { isEditorPresented = false }
            )
        }
    }
}

private struct RemoteMachineEditor: View {
    @State private var name: String
    @State private var username: String
    @State private var host: String
    @State private var portText: String
    @State private var projectPath: String
    private let machineID: UUID
    let save: (RemoteMachine) -> Void
    let cancel: () -> Void

    init(
        machine: RemoteMachine,
        save: @escaping (RemoteMachine) -> Void,
        cancel: @escaping () -> Void
    ) {
        machineID = machine.id
        _name = State(initialValue: machine.name)
        _username = State(initialValue: machine.username)
        _host = State(initialValue: machine.host)
        _portText = State(
            initialValue: machine.sshPort.map(String.init) ?? ""
        )
        _projectPath = State(initialValue: machine.projectPath ?? "")
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remote Machine")
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("remote-machine-name-field")
                TextField("Username", text: $username)
                    .accessibilityIdentifier("remote-machine-username-field")
                TextField("Host", text: $host)
                    .accessibilityIdentifier("remote-machine-host-field")
                TextField("SSH port", text: $portText, prompt: Text("22"))
                    .accessibilityIdentifier("remote-machine-port-field")
                TextField("Project path", text: $projectPath, prompt: Text("~/src/project"))
                    .accessibilityIdentifier("remote-machine-project-path-field")
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(draftMachine)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draftMachine.isValid)
                .accessibilityIdentifier("save-remote-machine-button")
            }
        }
        .padding(24)
        .frame(width: 420)
        .onExitCommand(perform: cancel)
    }

    private var draftMachine: RemoteMachine {
        let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(trimmedPort)
        return RemoteMachine(
            id: machineID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            sshPort: trimmedPort.isEmpty ? nil : port,
            projectPath: projectPath
        )
    }
}
