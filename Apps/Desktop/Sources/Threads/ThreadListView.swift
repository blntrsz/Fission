import FissionCore
import SwiftUI

struct ThreadListView: View {
    @State private var model = ThreadListViewModel()
    @State private var workspaceStore = ThreadWorkspaceStore()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedThreadID: UUID?
    @State private var isCreatingThread = false
    @State private var areSettledThreadsExpanded = true
    @State private var recentProjectPaths = RecentProjectPaths.load()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 400)
        } detail: {
            workspaceDetail
        }
        .focusedSceneValue(\.toggleSidebarAction, toggleSidebar)
        .toolbar {
            ThreadToolbarContent(
                thread: selectedThread,
                createThread: { isCreatingThread = true }
            )
        }
        .task { await model.load() }
        .onChange(of: model.threads, initial: true) { _, threads in
            synchronizeWorkspaces(with: threads)
        }
        .onChange(of: selectedThreadID) { _, threadID in
            guard let thread = model.threads.first(where: {
                $0.id == threadID && $0.status != .settled
            }) else {
                return
            }
            workspaceStore.open(thread: thread)
        }
        .sheet(isPresented: $isCreatingThread) {
            NewThreadSheet(
                recentPaths: recentProjectPaths,
                create: createThread(in:name:),
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
                List(selection: $selectedThreadID) {
                    ForEach(activeThreads) { thread in
                        ThreadRow(
                            thread: thread,
                            isSelected: selectedThreadID == thread.id,
                            settle: { settle(thread) },
                            reopen: {}
                        )
                        .listRowInsets(
                            EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
                        )
                        .tag(thread.id)
                    }
                    .onDelete { offsets in
                        deleteThreads(at: offsets, from: activeThreads)
                    }

                    if !settledThreads.isEmpty {
                        settledThreadsAccordion

                        if areSettledThreadsExpanded {
                            ForEach(settledThreads) { thread in
                                ThreadRow(
                                    thread: thread,
                                    isSelected: false,
                                    settle: {},
                                    reopen: { reopen(thread) }
                                )
                                .listRowInsets(
                                    EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
                                )
                            }
                            .onDelete { offsets in
                                deleteThreads(at: offsets, from: settledThreads)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Threads")
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        if selectedThreadID == nil {
            ContentUnavailableView(
                "Select a Thread",
                systemImage: "terminal",
                description: Text("Choose a Thread to open its terminal workspace.")
            )
        } else {
            ZStack {
                ForEach(workspaceStore.workspaces) { workspace in
                    let visible = workspace.threadID == selectedThreadID
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

    private var selectedThread: AgentThread? {
        model.threads.first { $0.id == selectedThreadID }
    }
    private var activeThreads: [AgentThread] {
        model.threads.filter { $0.status != .settled }
    }

    private var settledThreads: [AgentThread] {
        model.threads.filter { $0.status == .settled }
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
        Task { await model.deleteThreads(ids: ids) }
    }

    private func settle(_ thread: AgentThread) {
        Task { await model.settle(threadID: thread.id) }
    }

    private func reopen(_ thread: AgentThread) {
        Task {
            await model.reopen(threadID: thread.id)
            selectedThreadID = thread.id
        }
    }

    private func createThread(in directory: URL, name: String) {
        RecentProjectPaths.record(directory)
        recentProjectPaths = RecentProjectPaths.load()
        isCreatingThread = false

        Task {
            if let threadID = await model.createThread(
                title: name,
                workingDirectory: directory.path
            ) {
                selectedThreadID = threadID
            }
        }
    }

    private func synchronizeWorkspaces(with threads: [AgentThread]) {
        workspaceStore.synchronize(threads: threads)

        let availableThreads = threads.filter { $0.status != .settled }
        if let selectedThreadID,
           availableThreads.contains(where: { $0.id == selectedThreadID }) {
            return
        }

        selectedThreadID = availableThreads.first?.id
        if let thread = availableThreads.first {
            workspaceStore.open(thread: thread)
        }
    }
}

private struct ThreadRow: View {
    let thread: AgentThread
    let isSelected: Bool
    let settle: () -> Void
    let reopen: () -> Void

    @State private var isHovering = false

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

            Text(thread.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .padding(.bottom, 6)

            GitBranchLabel(workingDirectory: thread.workingDirectory)
        }
        .padding(.bottom, 6)
        .opacity(thread.status == .settled ? 0.48 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovering && !isSelected ? Color.primary.opacity(0.06) : Color.clear)
                .padding(.horizontal, -14)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            if thread.status == .settled {
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
        if thread.status == .settled {
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

private enum GitBranchResolver {
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
    ThreadListView()
}
