// swiftlint:disable file_length

import FissionCore
import SwiftUI

enum NewThreadRequest: Equatable {
    case local(URL, createIsolate: Bool, branchName: String?)
    case remote(RemoteMachine, projectPath: String)
}

struct NewThreadSheet: View {
    let recentPaths: [String]
    let recentRemotePathsByMachine: [UUID: [String]]
    let machines: [RemoteMachine]
    let remoteDirectoryCatalog: any RemoteDirectoryCatalog
    let create: (NewThreadRequest) async -> Void
    let cancel: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var selectedMachineID: UUID?
    @State private var remoteProjectPath = ""
    @State private var remoteListingsByDirectory: [String: RemoteDirectoryListing] = [:]
    @State private var isolateBranchName = ""
    @State private var isCreating = false
    @State private var step = Step.project
    @AppStorage("createThreadsInNewIsolate") private var createInNewIsolate = true
    @AppStorage("newThreadLocation") private var locationRaw = NewThreadLocation.local.rawValue
    @FocusState private var focusedField: Field?

    init(
        recentPaths: [String],
        recentRemotePathsByMachine: [UUID: [String]] = [:],
        machines: [RemoteMachine],
        remoteDirectoryCatalog: any RemoteDirectoryCatalog = RemoteDirectoryCatalogs.make(),
        create: @escaping (NewThreadRequest) async -> Void,
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
        ZStack {
            VStack(spacing: 0) {
                if step == .isolateBranch {
                    branchStep
                } else {
                    header
                    if location == .local {
                        projectList
                    } else if machines.isEmpty {
                        remoteEmptyList
                    } else {
                        remoteProjectPicker
                    }
                }
                footer
            }
            .disabled(isCreating)

            if isCreating {
                creatingOverlay
            }
        }
        .frame(width: 720, height: 540)
        .background(.regularMaterial)
        .interactiveDismissDisabled(isCreating)
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
            step = .project
            focusedField = location == .local ? .project : .remotePath
            selectedIndex = projects.isEmpty ? -1 : 0
        }
        .onChange(of: createInNewIsolate) { _, isOn in
            if !isOn {
                step = .project
            }
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
            guard step == .project else { return .ignored }
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard step == .project else { return .ignored }
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(keys: ["n", "p"]) { keyPress in
            guard step == .project, keyPress.modifiers == .control else { return .ignored }
            moveSelection(by: keyPress.key == "n" ? 1 : -1)
            return .handled
        }
        .onKeyPress(.tab) {
            guard step == .project,
                  focusedField == (location == .local ? .project : .remotePath) else {
                return .ignored
            }
            completeSelectedProject()
            return .handled
        }
        .onExitCommand {
            guard !isCreating else { return }
            if step == .isolateBranch {
                returnToProjectStep()
            } else {
                cancel()
            }
        }
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

                closeButton
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

    private var branchStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Thread")
                        .font(.title2.bold())
                    Text("Name the Git branch for this isolated workspace.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                closeButton
            }

            if let project = selectedLocalProject {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Project")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(project.name)
                        .font(.title3)
                    Text(project.displayPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            field(
                title: "Branch name",
                systemImage: "arrow.triangle.branch",
                placeholder: "Leave blank to generate",
                text: $isolateBranchName,
                focus: .branch,
                accessibilityIdentifier: "isolate-branch-field",
                accessibilityLabel: "Isolate branch name"
            )
            .help("Git branch for the isolated workspace. Leave blank to generate one.")

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("new-thread-branch-step")
        .task {
            focusedField = .branch
        }
    }

    private var closeButton: some View {
        Button(action: cancel) {
            Image(systemName: "xmark")
                .font(.headline)
                .padding(8)
                .contentShape(Circle())
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
        .accessibilityLabel("Close")
        .help("Close")
    }

    private func field(
        title: String,
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        focus: Field,
        accessibilityIdentifier: String = "project-path-field",
        accessibilityLabel: String? = nil
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
                    .accessibilityLabel(accessibilityLabel ?? title)
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
            if step == .isolateBranch {
                Button("Back", systemImage: "chevron.left") {
                    returnToProjectStep()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.plain)
                .accessibilityIdentifier("new-thread-back-button")
                .help("Return to project selection.")

                Label("Create", systemImage: "return")
                Label("Back", systemImage: "escape")
            } else {
                Label("Navigate", systemImage: "arrow.up.arrow.down")
                Label("Complete", systemImage: "arrow.right.to.line")
                Label("Select", systemImage: "return")
                Label("Close", systemImage: "escape")
            }

            Spacer()

            if location == .local && step == .project {
                Toggle("New isolated workspace", isOn: $createInNewIsolate)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("isolate-toggle")
                    .help("Copy this project into an isolated folder for this Thread.")
            }

            Button("Create Thread") {
                createSelected()
            }
            .accessibilityIdentifier("create-thread-button")
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate || isCreating)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .frame(height: 64)
        .background(.bar)
    }

    private var creatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
            ProgressView("Creating Thread…")
                .controlSize(.large)
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("creating-thread-progress")
        .accessibilityLabel("Creating Thread")
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
        switch (step, location) {
        case (.isolateBranch, _):
            isolateBranchIsAllowed
        case (.project, .local):
            !projects.isEmpty
        case (.project, .remote):
            selectedMachine != nil && selectedRemoteProjectPath != nil
        }
    }

    private var selectedLocalProject: ProjectPath? {
        guard location == .local, projects.indices.contains(selectedIndex) else { return nil }
        return projects[selectedIndex]
    }

    private var isolateBranchIsAllowed: Bool {
        guard createInNewIsolate else { return true }
        guard let branch = GitWorktreeBranch.normalized(isolateBranchName) else {
            return true
        }
        return GitWorktreeBranch.isValid(branch)
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
        guard !isCreating else { return }
        let request: NewThreadRequest
        switch location {
        case .local:
            guard let project = selectedLocalProject else { return }
            if createInNewIsolate, step == .project {
                step = .isolateBranch
                focusedField = .branch
                return
            }
            request = .local(
                project.url,
                createIsolate: createInNewIsolate,
                branchName: createInNewIsolate
                    ? GitWorktreeBranch.normalized(isolateBranchName)
                    : nil
            )
        case .remote:
            guard let selectedMachine, let projectPath = selectedRemoteProjectPath else {
                return
            }
            request = .remote(selectedMachine, projectPath: projectPath)
        }
        Task {
            isCreating = true
            await Task.yield()
            await create(request)
            isCreating = false
        }
    }

    private func returnToProjectStep() {
        step = .project
        focusedField = .project
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
    case branch
}

private enum Step {
    case project
    case isolateBranch
}

private enum NewThreadLocation: String {
    case local
    case remote
}
