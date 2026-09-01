import SwiftUI

struct NewThreadSheet: View {
    let recentPaths: [String]
    let create: (URL, String) -> Void
    let cancel: () -> Void

    @State private var threadName = ""
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 0) {
            header
            projectList
            footer
        }
        .frame(width: 720, height: 540)
        .background(.regularMaterial)
        .task {
            focusedField = .project
        }
        .onChange(of: query) { _, _ in
            selectedIndex = projects.isEmpty ? -1 : 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.tab) {
            guard focusedField == .project else { return .ignored }
            completeSelectedProject()
            return .handled
        }
        .onExitCommand(perform: cancel)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Thread")
                        .font(.title2.bold())
                    Text("Choose the project directory where the agent should work.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close", systemImage: "xmark", action: cancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.headline)
                    .padding(8)
                    .background(.quaternary, in: Circle())
            }

            field(
                title: "Thread name",
                systemImage: "text.cursor",
                placeholder: "What should the agent work on?",
                text: $threadName,
                focus: .name
            )

            field(
                title: "Project folder",
                systemImage: "magnifyingglass",
                placeholder: "Search projects or enter ./, ~/, or /",
                text: $query,
                focus: .project
            )
        }
        .padding(24)
    }

    private func field(
        title: String,
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        focus: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: text)
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
                focusedField = .name
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

            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)

            Button("Create Thread") {
                createSelectedProject()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(projects.isEmpty || trimmedThreadName.isEmpty)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .frame(height: 64)
        .background(.bar)
    }

    private var projects: [ProjectPath] {
        ProjectPathResolver.projects(matching: query, recentPaths: recentPaths)
    }

    private func moveSelection(by offset: Int) {
        guard !projects.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), projects.count - 1)
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

    private var trimmedThreadName: String {
        threadName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createSelectedProject() {
        guard projects.indices.contains(selectedIndex), !trimmedThreadName.isEmpty else { return }
        create(projects[selectedIndex].url, trimmedThreadName)
    }
}

private enum Field: Hashable {
    case name
    case project
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
