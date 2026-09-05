// swiftlint:disable file_length

import FissionCore
import SwiftUI

// swiftlint:disable:next type_body_length
struct ThreadListView: View {
    let model: ThreadListModel
    let agentActivityModel: AgentActivityModel
    let navigationModel: DesktopNavigationModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var workspaceStore: ThreadWorkspaceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editingThreadID: UUID?
    @State private var renameDraft = ""
    @State private var isCreatingThread = false
    @State private var mostRecentlyCreatedThreadID: UUID?
    @State private var areSettledThreadsExpanded = true
    @State private var settledDisplayLimit = 20
    @State private var recentProjectPaths = RecentProjectPaths.load()

    init(
        model: ThreadListModel,
        agentActivityModel: AgentActivityModel,
        navigationModel: DesktopNavigationModel
    ) {
        self.model = model
        self.agentActivityModel = agentActivityModel
        self.navigationModel = navigationModel
        _workspaceStore = State(
            initialValue: ThreadWorkspaceStore(agentActivityModel: agentActivityModel)
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 400)
        } detail: {
            workspaceDetail
        }
        .focusedSceneValue(\.toggleSidebarAction, toggleSidebar)
        .focusedSceneValue(\.renameThreadAction, renameThreadAction)
        .toolbar {
            ThreadToolbarContent(
                thread: selectedThread,
                createThread: { isCreatingThread = true }
            )
        }
        .task {
            await model.load()
            synchronizeWorkspaces(with: model.threads)
            updateAgentAttention(selectedThreadID: navigationModel.selectedThreadID)
        }
        .onChange(of: model.threads) { _, threads in
            synchronizeWorkspaces(with: threads)
        }
        .onChange(of: navigationModel.selectedThreadID) { _, threadID in
            updateAgentAttention(selectedThreadID: threadID)
            guard let thread = model.threads.first(where: {
                $0.id == threadID && !$0.isSettled
            }) else {
                return
            }
            workspaceStore.open(thread: thread)
            navigationModel.didOpen(threadID: thread.id)
        }
        .onChange(of: scenePhase) { _, _ in
            updateAgentAttention(selectedThreadID: navigationModel.selectedThreadID)
        }
        .sheet(isPresented: $isCreatingThread) {
            NewThreadSheet(
                recentPaths: recentProjectPaths,
                create: createThread(in:createWorktree:),
                cancel: { isCreatingThread = false }
            )
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var sidebar: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading Threads…")
            } else if model.threads.isEmpty {
                ContentUnavailableView(
                    "No Threads",
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("Create a Thread to start a new agent workstream.")
                )
            } else {
                ScrollViewReader { proxy in
                    List(selection: selectedThreadBinding) {
                        ForEach(activeThreads) { thread in
                            let activityStates = activityStates(for: thread.id)
                            ThreadRow(
                                thread: thread,
                                activityStates: activityStates,
                                isSelected: navigationModel.selectedThreadID == thread.id,
                                isRenaming: editingThreadID == thread.id,
                                renameTitle: $renameDraft,
                                beginRenaming: { beginRenaming(thread) },
                                commitRename: commitRename,
                                cancelRename: cancelRename,
                                settle: { settle(thread) },
                                reopen: {}
                            )
                            .listRowInsets(threadRowInsets())
                            .tag(thread.id)
                            .id(thread.id)
                        }
                        .onDelete { offsets in
                            deleteThreads(at: offsets, from: activeThreads)
                        }

                        if !settledThreads.isEmpty {
                            settledThreadsAccordion

                            if areSettledThreadsExpanded {
                                ForEach(displayedSettledThreads) { thread in
                                    let activityStates = activityStates(for: thread.id)
                                    ThreadRow(
                                        thread: thread,
                                        activityStates: activityStates,
                                        isSelected: false,
                                        isRenaming: editingThreadID == thread.id,
                                        renameTitle: $renameDraft,
                                        beginRenaming: { beginRenaming(thread) },
                                        commitRename: commitRename,
                                        cancelRename: cancelRename,
                                        settle: {},
                                        reopen: { reopen(thread) }
                                    )
                                    .listRowInsets(threadRowInsets())
                                }
                                .onDelete { offsets in
                                    deleteThreads(at: offsets, from: displayedSettledThreads)
                                }

                                if remainingSettledThreadCount > 0 {
                                    Button {
                                        settledDisplayLimit += 20
                                    } label: {
                                        Text("Load more (\(remainingSettledThreadCount) remaining)")
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("load-more-settled-threads")
                                    .listRowInsets(
                                        EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: mostRecentlyCreatedThreadID) { _, threadID in
                        guard let threadID else { return }
                        proxy.scrollTo(threadID, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("Threads")
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        if navigationModel.selectedThreadID == nil {
            ContentUnavailableView(
                "Select a Thread",
                systemImage: "terminal",
                description: Text("Choose a Thread to open its terminal workspace.")
            )
        } else {
            ZStack {
                ForEach(workspaceStore.workspaces) { workspace in
                    let visible = workspace.threadID == navigationModel.selectedThreadID
                    TerminalWorkspaceView(model: workspace, isVisible: visible)
                        .opacity(visible ? 1 : 0)
                        .allowsHitTesting(visible)
                        .accessibilityHidden(!visible)
                }
            }
            .navigationTitle("")
        }
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    private var selectedThreadBinding: Binding<UUID?> {
        Binding(
            get: { navigationModel.selectedThreadID },
            set: { navigationModel.select(threadID: $0) }
        )
    }

    private var selectedThread: AgentThread? {
        model.threads.first { $0.id == navigationModel.selectedThreadID }
    }

    private var renameThreadAction: (() -> Void)? {
        guard selectedThread != nil else { return nil }
        return beginRenamingSelectedThread
    }

    private func activityStates(for threadID: UUID) -> [AgentActivityState] {
        guard let workspace = workspaceStore.workspaces.first(where: {
            $0.threadID == threadID
        }) else {
            return []
        }
        return agentActivityModel.states(
            for: threadID,
            orderedBy: workspace.tabs.map(\.id)
        )
    }

    private func updateAgentAttention(selectedThreadID: UUID?) {
        agentActivityModel.updateAttention(
            selectedThreadID: selectedThreadID,
            isAppActive: scenePhase == .active
        )
    }

    private var activeThreads: [AgentThread] {
        model.threads.filter { !$0.isSettled }
    }

    private var settledThreads: [AgentThread] {
        model.threads.filter(\.isSettled)
    }

    private var displayedSettledThreads: [AgentThread] {
        Array(settledThreads.prefix(settledDisplayLimit))
    }

    private var remainingSettledThreadCount: Int {
        settledThreads.count - displayedSettledThreads.count
    }

    private var settledThreadsAccordion: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                areSettledThreadsExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(areSettledThreadsExpanded ? 90 : 0))

                Text("Settled")
                    .font(.caption.weight(.semibold))

                Text("\(settledThreads.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 3, trailing: 8))
        .accessibilityLabel(
            areSettledThreadsExpanded ? "Hide settled threads" : "Show settled threads"
        )
    }

    private func deleteThreads(at offsets: IndexSet, from threads: [AgentThread]) {
        let ids = offsets.map { threads[$0].id }
        for id in ids { workspaceStore.terminate(threadID: id) }
        Task { await model.deleteThreads(ids: ids) }
    }

    private func settle(_ thread: AgentThread) {
        workspaceStore.terminate(threadID: thread.id)
        Task { await model.settle(threadID: thread.id) }
    }

    private func reopen(_ thread: AgentThread) {
        Task {
            await model.reopen(threadID: thread.id)
            navigationModel.select(threadID: thread.id)
        }
    }

    private func createThread(
        in directory: URL,
        createWorktree: Bool
    ) {
        RecentProjectPaths.record(directory)
        recentProjectPaths = RecentProjectPaths.load()
        isCreatingThread = false

        Task {
            if let threadID = await DesktopThreadCreator.create(
                in: model,
                workingDirectory: directory.path,
                createWorktree: createWorktree
            ) {
                mostRecentlyCreatedThreadID = threadID
                navigationModel.select(threadID: threadID)
            }
        }
    }

    private func synchronizeWorkspaces(with threads: [AgentThread]) {
        agentActivityModel.synchronizeThreads(threads)
        workspaceStore.synchronize(threads: threads)

        let availableThreads = threads.filter { !$0.isSettled }
        navigationModel.synchronize(availableThreadIDs: availableThreads.map(\.id))
        if let selectedThreadID = navigationModel.selectedThreadID,
           let thread = availableThreads.first(where: { $0.id == selectedThreadID }) {
            workspaceStore.open(thread: thread)
        }
    }
}

private func threadRowInsets() -> EdgeInsets {
    let verticalPadding: CGFloat = 18
    return EdgeInsets(
        top: verticalPadding,
        leading: 8,
        bottom: verticalPadding,
        trailing: 8
    )
}

private extension ThreadListView {
    func beginRenamingSelectedThread() {
        guard let selectedThread else { return }
        beginRenaming(selectedThread)
    }

    func beginRenaming(_ thread: AgentThread) {
        guard editingThreadID != thread.id else { return }
        editingThreadID = thread.id
        renameDraft = thread.title
    }

    func commitRename() {
        guard let threadID = editingThreadID else { return }
        let title = renameDraft
        editingThreadID = nil
        Task { await model.rename(threadID: threadID, to: title) }
    }

    func cancelRename() {
        editingThreadID = nil
    }
}

private struct ThreadRow: View {
    let thread: AgentThread
    let activityStates: [AgentActivityState]
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renameTitle: String
    let beginRenaming: () -> Void
    let commitRename: () -> Void
    let cancelRename: () -> Void
    let settle: () -> Void
    let reopen: () -> Void

    @State private var isHovering = false
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(projectName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(thread.workingDirectory ?? "No project folder")

                Spacer(minLength: 4)

                actions
            }
            .padding(.bottom, 3)

            Group {
                if isRenaming {
                    TextField("Thread title", text: $renameTitle)
                        .textFieldStyle(.plain)
                        .focused($isRenameFieldFocused)
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)
                        .onAppear {
                            isRenameFieldFocused = true
                        }
                        .onChange(of: isRenameFieldFocused) { wasFocused, isFocused in
                            if wasFocused && !isFocused {
                                commitRename()
                            }
                        }
                } else {
                    Text(thread.title)
                        .lineLimit(2)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.bottom, 6)

            HStack(spacing: 10) {
                GitBranchLabel(workingDirectory: thread.workingDirectory)
                Spacer(minLength: 0)
                if !activityStates.isEmpty {
                    AgentActivityIndicators(states: activityStates)
                }
            }
        }
        .padding(.bottom, 6)
        .opacity(thread.isSettled ? 0.48 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovering && !isSelected ? Color.primary.opacity(0.06) : Color.clear)
                .padding(.horizontal, -14)
                .padding(.vertical, -12)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename", systemImage: "pencil", action: beginRenaming)

            Divider()

            if thread.isSettled {
                Button("Reopen", systemImage: "arrow.uturn.backward", action: reopen)
            } else {
                Button("Snooze", systemImage: "clock") {}
                    .disabled(true)
                Button("Settle", systemImage: "checkmark", action: settle)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if thread.isSettled {
            Button("Reopen", systemImage: "arrow.uturn.backward", action: reopen)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .hoverFeedback()
                .help("Reopen Thread")
        } else {
            HStack(spacing: 8) {
                Button("Snooze", systemImage: "clock") {}
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .hoverFeedback()
                    .disabled(true)
                    .help("Snooze — coming soon")

                Button("Settle", systemImage: "checkmark", action: settle)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .hoverFeedback()
                    .help("Settle Thread")
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .accessibilityHidden(!isHovering)
        }
    }

    private var projectName: String {
        guard let workingDirectory = thread.workingDirectory else { return "No Project" }
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return name.isEmpty ? workingDirectory : name
    }
}

private struct AgentActivityIndicators: View {
    let states: [AgentActivityState]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(states.prefix(10).enumerated()), id: \.offset) { _, state in
                Image(systemName: symbol(for: state))
                    .foregroundStyle(color(for: state))
                    .accessibilityLabel(accessibilityTitle(for: state))
            }
        }
        .font(.caption.weight(.medium))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent statuses")
    }

    private func accessibilityTitle(for state: AgentActivityState) -> String {
        switch state {
        case .idle: "Idle agent"
        case .running, .blocked: "Working agent"
        case .finished: "Finished agent"
        }
    }

    private func symbol(for state: AgentActivityState) -> String {
        switch state {
        case .idle: "circle"
        case .running, .blocked, .finished: "circle.fill"
        }
    }

    private func color(for state: AgentActivityState) -> Color {
        switch state {
        case .idle: .secondary
        case .running, .blocked: .white
        case .finished: .blue
        }
    }
}

private struct GitBranchLabel: View {
    let workingDirectory: String?

    @State private var branchName: String?

    var body: some View {
        Group {
            if let branchName {
                Text(branchName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: workingDirectory) {
            branchName = GitBranchResolver.currentBranch(at: workingDirectory)
        }
    }
}

enum GitBranchResolver {
    static func currentBranch(at workingDirectory: String?) -> String? {
        guard let workingDirectory,
              let gitDirectory = findGitDirectory(from: URL(fileURLWithPath: workingDirectory)),
              let head = try? String(
                  contentsOf: gitDirectory.appending(path: "HEAD"),
                  encoding: .utf8
              ).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let branchPrefix = "ref: refs/heads/"
        if head.hasPrefix(branchPrefix) {
            return String(head.dropFirst(branchPrefix.count))
        }
        return head.isEmpty ? nil : String(head.prefix(7))
    }

    private static func findGitDirectory(from workingDirectory: URL) -> URL? {
        var directory = workingDirectory.standardizedFileURL

        while directory.path != "/" {
            let candidate = directory.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return candidate
                }
                return worktreeGitDirectory(from: candidate, relativeTo: directory)
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private static func worktreeGitDirectory(from file: URL, relativeTo directory: URL) -> URL? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8),
              contents.hasPrefix("gitdir: ") else {
            return nil
        }

        let path = contents.dropFirst("gitdir: ".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return directory.appending(path: path).standardizedFileURL
    }
}

#Preview {
    ThreadListView(
        model: ThreadListModel(databasePath: ":memory:"),
        agentActivityModel: AgentActivityModel(installPiIntegration: false),
        navigationModel: DesktopNavigationModel()
    )
}
