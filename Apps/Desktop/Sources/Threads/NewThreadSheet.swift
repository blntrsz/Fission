// swiftlint:disable file_length

import FissionCore
import SwiftUI

enum NewThreadRequest: Equatable {
    case local(URL, createWorktree: Bool)
    case remote(RemoteMachine, projectPath: String)
}

struct NewThreadSheet: View {
    let recentPaths: [String]
    let machines: [RemoteMachine]
    let create: (NewThreadRequest) -> Void
    let cancel: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var selectedMachineID: UUID?
    @State private var remoteProjectPath = ""
    @AppStorage("createThreadsInNewWorktree") private var createInNewWorktree = false
    @AppStorage("newThreadLocation") private var locationRaw = NewThreadLocation.local.rawValue
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 0) {
            header
            if location == .local {
                projectList
            } else {
                remoteList
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
        .onChange(of: location) { _, location in
            focusedField = location == .local ? .project : .remotePath
        }
        .onChange(of: selectedMachineID) { previousID, _ in
            let previousPath = machines.first { $0.id == previousID }?.projectPath ?? ""
            let typedPath = remoteProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if typedPath.isEmpty || typedPath == previousPath {
                fillRemoteProjectPath(from: selectedMachine)
            }
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
            guard location == .local, focusedField == .project else { return .ignored }
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
                         : "Choose a remote machine and project path. Terminals open there over mosh.")
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
                    systemImage: "folder",
                    placeholder: "~/src/project or /absolute/path",
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

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(query.isEmpty ? "Recent Projects" : "Projects")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if projects.isEmpty {
                ContentUnavailableView(
                    "No Directories Found",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Enter an existing path, such as ~/Projects/.")
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
                        .id(query)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectedIndex = index
                query = inputPath(for: project.url)
                focusedField = .project
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

    private var remoteList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Machines")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            if machines.isEmpty {
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
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(machines) { machine in
                            remoteRow(machine)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("remote-machine-list")
    }

    private func remoteRow(_ machine: RemoteMachine) -> some View {
        Button {
            selectedMachineID = machine.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(machine.displayName)
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(machine.target)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let projectPath = machine.projectPath {
                        Text(projectPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 76)
            .contentShape(Rectangle())
            .background(
                selectedMachineID == machine.id ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("remote-machine-\(machine.id.uuidString)")
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectedMachineID = machine.id
                createSelected()
            }
        )
    }

    private var locationBinding: Binding<NewThreadLocation> {
        Binding(
            get: { location },
            set: { locationRaw = $0.rawValue }
        )
    }

    private var projects: [ProjectPath] {
        ProjectPathResolver.projects(matching: query, recentPaths: recentPaths)
    }

    private var canCreate: Bool {
        switch location {
        case .local:
            !projects.isEmpty
        case .remote:
            selectedMachine != nil && RemoteMachine.normalizedProjectPath(remoteProjectPath) != nil
        }
    }

    private var selectedMachine: RemoteMachine? {
        machines.first { $0.id == selectedMachineID } ?? machines.first
    }

    private func moveSelection(by offset: Int) {
        switch location {
        case .local:
            guard !projects.isEmpty else { return }
            selectedIndex = min(max(selectedIndex + offset, 0), projects.count - 1)
        case .remote:
            guard !machines.isEmpty else { return }
            let current = machines.firstIndex { $0.id == selectedMachineID } ?? 0
            let next = min(max(current + offset, 0), machines.count - 1)
            selectedMachineID = machines[next].id
        }
    }

    private func completeSelectedProject() {
        guard projects.indices.contains(selectedIndex) else { return }
        query = inputPath(for: projects[selectedIndex].url)
        focusedField = .project
    }

    private func inputPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        if query.hasPrefix("./") {
            let basePath = URL(
                fileURLWithPath: recentPaths.first ?? homePath
            ).standardizedFileURL.path
            if path == basePath {
                return "./"
            }
            if path.hasPrefix(basePath + "/") {
                return "./" + path.dropFirst(basePath.count + 1) + "/"
            }
        }

        if query.hasPrefix("~/") || (!query.hasPrefix("/") && path.hasPrefix(homePath + "/")) {
            return "~" + path.dropFirst(homePath.count) + "/"
        }

        return path.hasSuffix("/") ? path : path + "/"
    }

    private func createSelected() {
        switch location {
        case .local:
            guard projects.indices.contains(selectedIndex) else { return }
            create(.local(projects[selectedIndex].url, createWorktree: createInNewWorktree))
        case .remote:
            guard let selectedMachine,
                  let projectPath = RemoteMachine.normalizedProjectPath(remoteProjectPath) else {
                return
            }
            create(.remote(selectedMachine, projectPath: projectPath))
        }
    }

    private func fillRemoteProjectPath(from machine: RemoteMachine?) {
        remoteProjectPath = machine?.projectPath ?? ""
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

private struct ProjectPath: Identifiable {
    let url: URL

    var id: String { url.path }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard url.path.hasPrefix(home) else { return url.path }
        return "~" + url.path.dropFirst(home.count)
    }
}

private enum ProjectPathResolver {
    static func projects(matching query: String, recentPaths: [String]) -> [ProjectPath] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPathQuery(trimmedQuery) else {
            return recentProjects(recentPaths, matching: trimmedQuery)
        }

        let expandedPath = expand(trimmedQuery, recentPaths: recentPaths)
        let endsWithSlash = trimmedQuery.hasSuffix("/")
        let candidateURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        let directoryURL = endsWithSlash ? candidateURL : candidateURL.deletingLastPathComponent()
        let namePrefix = endsWithSlash ? "" : candidateURL.lastPathComponent

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                return values?.isDirectory == true
                    && values?.isHidden != true
                    && (namePrefix.isEmpty
                        || url.lastPathComponent.range(
                            of: namePrefix,
                            options: [.caseInsensitive, .anchored]
                        ) != nil)
            }
            .sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                    == .orderedAscending
            }
            .prefix(50)
            .map(ProjectPath.init)
    }

    private static func recentProjects(_ paths: [String], matching query: String) -> [ProjectPath] {
        paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { url in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                let matches = query.isEmpty
                    || url.lastPathComponent.localizedCaseInsensitiveContains(query)
                    || url.path.localizedCaseInsensitiveContains(query)
                return exists && isDirectory.boolValue && matches
            }
            .map(ProjectPath.init)
    }

    private static func isPathQuery(_ query: String) -> Bool {
        query.hasPrefix("./") || query.hasPrefix("~/") || query.hasPrefix("/")
    }

    private static func expand(_ path: String, recentPaths: [String]) -> String {
        if path.hasPrefix("./") {
            let basePath = recentPaths.first ?? FileManager.default.homeDirectoryForCurrentUser.path
            return URL(fileURLWithPath: basePath)
                .appending(path: String(path.dropFirst(2)))
                .path
        }
        return NSString(string: path).expandingTildeInPath
    }
}

enum RecentProjectPaths {
    private static let key = "recentProjectPaths"
    private static let limit = 9

    static func load() -> [String] {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        if saved.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let projects = home.appending(path: "Projects")
            return FileManager.default.fileExists(atPath: projects.path)
                ? [projects.path, home.path]
                : [home.path]
        }
        return saved
    }

    static func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = load().filter { $0 != path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
    }
}
