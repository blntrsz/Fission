// swiftlint:disable file_length

import FissionCore
import SwiftUI

enum NewThreadRequest: Equatable {
    case local(URL, createWorktree: Bool)
    case remote(RemoteMachine, projectPath: String)
}

struct NewThreadSheet: View {
    let recentPaths: [String]
    let recentRemotePathsByMachine: [UUID: [String]]
    let machines: [RemoteMachine]
    let remoteDirectoryCatalog: any RemoteDirectoryCatalog
    let create: (NewThreadRequest) -> Void
    let cancel: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var selectedMachineID: UUID?
    @State private var remoteProjectPath = ""
    @State private var remoteListingsByDirectory: [String: RemoteDirectoryListing] = [:]
    @AppStorage("createThreadsInNewWorktree") private var createInNewWorktree = false
    @AppStorage("newThreadLocation") private var locationRaw = NewThreadLocation.local.rawValue
    @FocusState private var focusedField: Field?

    init(
        recentPaths: [String],
        recentRemotePathsByMachine: [UUID: [String]] = [:],
        machines: [RemoteMachine],
        remoteDirectoryCatalog: any RemoteDirectoryCatalog = RemoteDirectoryCatalogs.make(),
        create: @escaping (NewThreadRequest) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.recentPaths = recentPaths
        self.recentRemotePathsByMachine = recentRemotePathsByMachine
        self.machines = machines
        self.remoteDirectoryCatalog = remoteDirectoryCatalog
        self.create = create
        self.cancel = cancel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if location == .local {
                projectList
            } else if machines.isEmpty {
                remoteEmptyList
            } else {
                remoteProjectPicker
            }
            footer
        }
        .frame(width: 720, height: 540)
        .background(.regularMaterial)
        .task {
            if selectedMachineID == nil {
                selectedMachineID = machines.first?.id
            }
            fillRemoteProjectPath(from: selectedMachine)
            focusedField = location == .local ? .project : .remotePath
        }
        .onChange(of: query) { _, _ in
            selectedIndex = projects.isEmpty ? -1 : 0
        }
        .onChange(of: remoteProjectPath) { _, _ in
            selectedIndex = projects.isEmpty ? -1 : 0
        }
        .onChange(of: location) { _, location in
            focusedField = location == .local ? .project : .remotePath
            selectedIndex = projects.isEmpty ? -1 : 0
        }
        .onChange(of: selectedMachineID) { previousID, _ in
            let previousPath = machines.first { $0.id == previousID }?.projectPath ?? ""
            let typedPath = remoteProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if typedPath.isEmpty || typedPath == previousPath {
                fillRemoteProjectPath(from: selectedMachine)
            }
            selectedIndex = projects.isEmpty ? -1 : 0
        }
        .task(id: remoteListingID) {
            await loadRemoteListing()
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(keys: ["n", "p"]) { keyPress in
            guard keyPress.modifiers == .control else { return .ignored }
            moveSelection(by: keyPress.key == "n" ? 1 : -1)
            return .handled
        }
        .onKeyPress(.tab) {
            guard focusedField == (location == .local ? .project : .remotePath) else {
                return .ignored
            }
            completeSelectedProject()
            return .handled
        }
        .onExitCommand(perform: cancel)
    }

    private var location: NewThreadLocation {
        NewThreadLocation(rawValue: locationRaw) ?? .local
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Thread")
                        .font(.title2.bold())
                    Text(location == .local
                         ? "Choose the project directory where the agent should work."
                         : "Choose a remote machine, then pick a folder. "
                            + "Available directories at that path are listed.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(8)
                        .contentShape(Circle())
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .help("Close")
            }

            Picker("Location", selection: locationBinding) {
                Text("This Mac")
                    .tag(NewThreadLocation.local)
                    .accessibilityIdentifier("new-thread-location-local")
                Text("Remote")
                    .tag(NewThreadLocation.remote)
                    .accessibilityIdentifier("new-thread-location-remote")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("new-thread-location-picker")

            if location == .local {
                field(
                    title: "Project folder",
                    systemImage: "magnifyingglass",
                    placeholder: "Search projects or enter ./, ~/, or /",
                    text: $query,
                    focus: .project
                )
            } else {
                field(
                    title: "Project folder",
                    systemImage: "magnifyingglass",
                    placeholder: "Search projects or enter ./, ~/, or /",
                    text: $remoteProjectPath,
                    focus: .remotePath,
                    accessibilityIdentifier: "remote-project-path-field"
                )
            }
        }
        .padding(24)
    }

    private func field(
        title: String,
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        focus: Field,
        accessibilityIdentifier: String = "project-path-field"
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: text)
                    .accessibilityIdentifier(accessibilityIdentifier)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focusedField, equals: focus)

                if !text.wrappedValue.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        text.wrappedValue = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
    }

    private var remoteProjectPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            machineChooser
            projectListContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var machineChooser: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Machine")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Picker("Machine", selection: $selectedMachineID) {
                ForEach(machines) { machine in
                    Text(machine.displayName)
                        .tag(Optional(machine.id))
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("remote-machine-picker")
        }
    }

    private var projectList: some View {
        projectListContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectListContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(projectSearch.isEmpty ? "Recent Projects" : "Projects")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if isRemoteListingPending {
                ProgressView("Listing directories…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("remote-directory-listing")
            } else if projects.isEmpty {
                ContentUnavailableView(
                    "No Directories Found",
                    systemImage: "folder.badge.questionmark",
                    description: Text(
                        location == .remote
                            ? "Only existing folders on the remote machine can be picked."
                            : "Enter an existing path, such as ~/Projects/."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                                projectRow(project, at: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 14)
                        .id(projectSearch)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("new-thread-project-list")
    }

    private func projectRow(_ project: ProjectPath, at index: Int) -> some View {
        Button {
            selectedIndex = index
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "folder")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(project.displayPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .contentShape(Rectangle())
            .background(
                index == selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-thread-project-\(project.name)")
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectedIndex = index
                completeSelectedProject()
            }
        )
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Label("Navigate", systemImage: "arrow.up.arrow.down")
            Label("Complete", systemImage: "arrow.right.to.line")
            Label("Select", systemImage: "return")
            Label("Close", systemImage: "escape")

            Spacer()

            if location == .local {
                Toggle("New worktree", isOn: $createInNewWorktree)
                    .toggleStyle(.switch)
                    .help("Create an isolated Git branch and use its checkout for this Thread.")
            }

            Button("Create Thread") {
                createSelected()
            }
            .accessibilityIdentifier("create-thread-button")
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .frame(height: 64)
        .background(.bar)
    }

    private var remoteEmptyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Machines")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            ContentUnavailableView {
                Label("No Remote Machines", systemImage: "network")
            } description: {
                Text("Add a host in Settings, then open it as a remote Thread.")
            } actions: {
                SettingsLink {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("open-remote-machine-settings")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("remote-machine-list")
    }

    private var locationBinding: Binding<NewThreadLocation> {
        Binding(
            get: { location },
            set: { locationRaw = $0.rawValue }
        )
    }

    private var projectSearch: String {
        location == .local ? query : remoteProjectPath
    }

    private var recentRemotePaths: [String] {
        guard let id = selectedMachine?.id else { return [] }
        var paths = recentRemotePathsByMachine[id] ?? []
        if let projectPath = selectedMachine?.projectPath {
            paths.insert(projectPath, at: 0)
        }
        return paths
    }

    private var projects: [ProjectPath] {
        switch location {
        case .local:
            ProjectPathResolver.projects(matching: query, recentPaths: recentPaths)
        case .remote:
            RemoteProjectPathResolver.projects(
                directory: remoteListingTarget?.directory ?? "~",
                namePrefix: remoteListingTarget?.namePrefix ?? "",
                listing: cachedRemoteListing
            )
        }
    }

    private var cachedRemoteListing: RemoteDirectoryListing? {
        guard let directory = remoteListingTarget?.directory,
              let machine = selectedMachine else { return nil }
        return remoteListingsByDirectory[listingCacheKey(machineID: machine.id, directory: directory)]
    }

    private var isRemoteListingPending: Bool {
        location == .remote && selectedMachine != nil && cachedRemoteListing == nil
    }

    private var remoteListingID: String {
        guard location == .remote, let machine = selectedMachine,
              let directory = remoteListingTarget?.directory else {
            return ""
        }
        return listingCacheKey(machineID: machine.id, directory: directory)
    }

    private var remoteListingTarget: (directory: String, namePrefix: String)? {
        guard location == .remote else { return nil }
        let relativeBase = selectedMachine?.projectPath ?? recentRemotePaths.first
        return ProjectPathQuery.resolvedListingTarget(
            query: ProjectPathQuery.normalizeRemoteQuery(remoteProjectPath),
            relativeBase: relativeBase,
            exactChildNames: { directory in
                guard let machine = selectedMachine,
                      case let .contents(names) = remoteListingsByDirectory[
                          listingCacheKey(machineID: machine.id, directory: directory)
                      ] else {
                    return nil
                }
                return names
            }
        )
    }

    private func listingCacheKey(machineID: UUID, directory: String) -> String {
        "\(machineID.uuidString)\n\(directory)"
    }

    private var canCreate: Bool {
        switch location {
        case .local:
            !projects.isEmpty
        case .remote:
            selectedMachine != nil && selectedRemoteProjectPath != nil
        }
    }

    private var selectedRemoteProjectPath: String? {
        guard projects.indices.contains(selectedIndex) else { return nil }
        return RemoteMachine.normalizedProjectPath(projects[selectedIndex].path)
    }

    private var selectedMachine: RemoteMachine? {
        machines.first { $0.id == selectedMachineID } ?? machines.first
    }

    private func moveSelection(by offset: Int) {
        guard !projects.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), projects.count - 1)
    }

    private func completeSelectedProject() {
        guard projects.indices.contains(selectedIndex) else { return }
        let path = projects[selectedIndex].path
        switch location {
        case .local:
            query = ProjectPathQuery.completedInput(
                query: query,
                path: path,
                homePath: FileManager.default.homeDirectoryForCurrentUser.path,
                relativeBase: recentPaths.first
            )
            focusedField = .project
        case .remote:
            remoteProjectPath = ProjectPathQuery.completedInput(
                query: remoteProjectPath,
                path: path,
                homePath: nil,
                relativeBase: selectedMachine?.projectPath ?? recentRemotePaths.first
            )
            focusedField = .remotePath
        }
    }

    private func createSelected() {
        switch location {
        case .local:
            guard projects.indices.contains(selectedIndex) else { return }
            create(.local(projects[selectedIndex].url, createWorktree: createInNewWorktree))
        case .remote:
            guard let selectedMachine, let projectPath = selectedRemoteProjectPath else {
                return
            }
            create(.remote(selectedMachine, projectPath: projectPath))
        }
    }

    private func fillRemoteProjectPath(from machine: RemoteMachine?) {
        remoteProjectPath = machine?.projectPath ?? ""
    }

    private func loadRemoteListing() async {
        guard location == .remote,
              let machine = selectedMachine,
              let directory = remoteListingTarget?.directory else {
            return
        }
        let key = listingCacheKey(machineID: machine.id, directory: directory)
        if remoteListingsByDirectory[key] != nil { return }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let listing = await remoteDirectoryCatalog.listing(on: machine, in: directory)
        guard !Task.isCancelled else { return }
        remoteListingsByDirectory[key] = listing
        selectedIndex = 0
    }
}

private enum Field: Hashable {
    case project
    case remotePath
}

private enum NewThreadLocation: String {
    case local
    case remote
}
