// swiftlint:disable file_length

import FissionCore
import GhosttyTerminal
import Observation
import SwiftUI

@MainActor
@Observable
final class ThreadWorkspaceStore {
    private(set) var workspaces: [TerminalTabsViewModel] = []
    private let agentActivityModel: AgentActivityModel

    init(agentActivityModel: AgentActivityModel) {
        self.agentActivityModel = agentActivityModel
    }

    func open(thread: AgentThread) {
        guard !workspaces.contains(where: { $0.threadID == thread.id }) else { return }
        workspaces.append(
            TerminalTabsViewModel(thread: thread, agentActivityModel: agentActivityModel)
        )
    }

    func terminate(threadID: UUID) {
        if let workspace = workspaces.first(where: { $0.threadID == threadID }) {
            workspace.terminateAll()
        } else {
            let sessionIDs = TerminalWorkspacePersistence.load(threadID: threadID).map(\.id)
            TerminalExecutionControl.terminate(sessionIDs: sessionIDs)
            TerminalWorkspacePersistence.remove(threadID: threadID)
        }
        agentActivityModel.forget(threadID: threadID)
    }

    func synchronize(threads: [AgentThread]) {
        let availableThreads = threads.filter { !$0.isSettled }
        let threadIDs = Set(availableThreads.map(\.id))
        let removedThreadIDs = workspaces
            .filter { !threadIDs.contains($0.threadID) }
            .map(\.threadID)
        for workspace in workspaces where !threadIDs.contains(workspace.threadID) {
            workspace.terminateAll()
        }
        workspaces.removeAll { !threadIDs.contains($0.threadID) }
        for threadID in removedThreadIDs {
            agentActivityModel.forget(threadID: threadID)
        }

        for workspace in workspaces {
            if let thread = availableThreads.first(where: { $0.id == workspace.threadID }) {
                workspace.update(thread: thread)
            }
        }
    }
}

@MainActor
@Observable
final class TerminalTabsViewModel: Identifiable {
    nonisolated let id: UUID
    nonisolated let threadID: UUID
    private(set) var threadTitle: String
    private(set) var workingDirectory: String?
    private(set) var tabs: [TerminalTab] = []
    var selectedTabID: UUID?
    private let agentActivityModel: AgentActivityModel
    private var nextTabNumber = 1

    init(thread: AgentThread, agentActivityModel: AgentActivityModel) {
        id = thread.id
        threadID = thread.id
        threadTitle = thread.title
        workingDirectory = thread.workingDirectory
        self.agentActivityModel = agentActivityModel

        let restoredTabs = TerminalWorkspacePersistence.load(threadID: thread.id)
        if restoredTabs.isEmpty {
            addTab()
        } else {
            tabs = restoredTabs.map { record in
                makeTab(id: record.id, number: record.number, title: record.title)
            }
            nextTabNumber = (restoredTabs.map(\.number).max() ?? 0) + 1
            selectedTabID = restoredTabs.first(where: \.isSelected)?.id ?? tabs.first?.id
            updateVisibility()
        }
    }

    func update(thread: AgentThread) {
        threadTitle = thread.title
        workingDirectory = thread.workingDirectory
    }

    func addTab() {
        let tab = makeTab(id: UUID(), number: nextTabNumber)
        nextTabNumber += 1
        tabs.append(tab)
        select(tabID: tab.id)
    }

    func select(tabID: UUID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        selectedTabID = tabID
        updateVisibility()
        persist()
        tabs.first(where: { $0.id == tabID })?.state.requestFocus()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tabID: tabs[index].id)
    }

    func pasteImageIntoFocusedTab() -> Bool {
        guard let tab = tabs.first(where: { $0.id == selectedTabID }),
              let view = tab.state.attachedPlatformView as? FissionTerminalView
        else {
            return false
        }
        return view.pasteImageFromMenu()
    }

    func close(tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let wasSelected = selectedTabID == tabID
        let removedTab = tabs.remove(at: index)
        removedTab.terminate()
        agentActivityModel.forget(threadID: threadID, tabID: tabID)

        if tabs.isEmpty {
            addTab()
        } else if wasSelected {
            select(tabID: tabs[min(index, tabs.count - 1)].id)
        } else {
            updateVisibility()
            persist()
        }
    }

    func terminateAll() {
        for tab in tabs { tab.terminate() }
        TerminalWorkspacePersistence.remove(threadID: threadID)
    }

    func setWorkspaceVisible(_ visible: Bool) {
        for tab in tabs {
            tab.state.isSurfaceVisible = visible && tab.id == selectedTabID
        }
    }

    private func updateVisibility() {
        for tab in tabs {
            tab.state.isSurfaceVisible = tab.id == selectedTabID
        }
    }

    private func makeTab(id: UUID, number: Int, title: String? = nil) -> TerminalTab {
        let tab = TerminalTab(
            id: id,
            number: number,
            title: title,
            threadID: threadID,
            workingDirectory: workingDirectory,
            agentActivityModel: agentActivityModel,
            didRename: { [weak self] in self?.persist() }
        )
        tab.state.onClose = { [weak self, weak tab] _ in
            guard let tab else { return }
            self?.close(tabID: tab.id)
        }
        return tab
    }

    private func persist() {
        TerminalWorkspacePersistence.save(
            tabs: tabs.enumerated().map { index, tab in
                TerminalWorkspacePersistence.TabRecord(
                    id: tab.id,
                    number: index + 1,
                    title: tab.title,
                    isSelected: tab.id == selectedTabID
                )
            },
            threadID: threadID
        )
    }
}

@MainActor
@Observable
final class TerminalTab: Identifiable {
    nonisolated let id: UUID
    private(set) var title: String
    let state: TerminalViewState

    @ObservationIgnored private let persistentSession: PersistentTerminalSession
    @ObservationIgnored private let didRename: () -> Void

    init(
        id: UUID,
        number: Int,
        title: String? = nil,
        threadID: UUID,
        workingDirectory: String?,
        agentActivityModel: AgentActivityModel,
        didRename: @escaping () -> Void
    ) {
        self.id = id
        self.title = title ?? "Tab \(number)"
        self.didRename = didRename

        let persistentSession = PersistentTerminalSession(
            id: id,
            threadID: threadID,
            workingDirectory: workingDirectory,
            environment: agentActivityModel.environment(threadID: threadID, tabID: id)
        )
        self.persistentSession = persistentSession

        state = TerminalViewState(
            configSource: GhosttyUserConfiguration.source,
            // Preserve colors from Ghostty's config instead of overlaying the
            // package's default Alabaster/Afterglow theme.
            theme: TerminalTheme()
        )
        state.makePlatformView = { FissionTerminalView(frame: .zero) }
        state.configuration = TerminalSurfaceOptions(
            backend: .inMemory(persistentSession.renderer),
            context: .window,
            resizeThrottleMilliseconds: 16
        )
    }

    func rename(to proposedTitle: String) {
        let trimmedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        title = trimmedTitle
        didRename()
    }

    func terminate() {
        persistentSession.terminate()
    }
}

private enum TerminalWorkspacePersistence {
    struct TabRecord: Codable {
        let id: UUID
        let number: Int
        let title: String
        let isSelected: Bool
    }

    static func load(threadID: UUID) -> [TabRecord] {
        guard let data = UserDefaults.standard.data(forKey: key(threadID: threadID)) else {
            return []
        }
        return (try? JSONDecoder().decode([TabRecord].self, from: data)) ?? []
    }

    static func save(tabs: [TabRecord], threadID: UUID) {
        guard let data = try? JSONEncoder().encode(tabs) else { return }
        UserDefaults.standard.set(data, forKey: key(threadID: threadID))
    }

    static func remove(threadID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(threadID: threadID))
    }

    private static func key(threadID: UUID) -> String {
        "terminal-workspace.\(threadID.uuidString)"
    }
}

private enum GhosttyUserConfiguration {
    static var source: TerminalController.ConfigSource {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser

        let xdgDirectory: URL
        if let configuredDirectory = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           configuredDirectory.hasPrefix("/") {
            xdgDirectory = URL(fileURLWithPath: configuredDirectory, isDirectory: true)
        } else {
            xdgDirectory = homeDirectory.appendingPathComponent(".config", isDirectory: true)
        }

        let xdgGhosttyDirectory = xdgDirectory.appendingPathComponent("ghostty", isDirectory: true)
        let appSupportDirectory = homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)

        // This is Ghostty's load order: legacy before current, XDG before
        // macOS Application Support. Later files override earlier files.
        let candidates = [
            xdgGhosttyDirectory.appendingPathComponent("config"),
            xdgGhosttyDirectory.appendingPathComponent("config.ghostty"),
            appSupportDirectory.appendingPathComponent("config"),
            appSupportDirectory.appendingPathComponent("config.ghostty")
        ]
        let existingPaths = candidates
            .map(\.path)
            .filter { fileManager.fileExists(atPath: $0) }

        guard !existingPaths.isEmpty else { return .none }

        let rewrittenFiles = existingPaths.compactMap { path -> String? in
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                return nil
            }
            return resolveBundledThemes(in: contents)
        }

        guard rewrittenFiles.count == existingPaths.count else {
            // Let Ghostty report the unreadable file rather than silently
            // dropping part of the user's configuration.
            return .file(existingPaths.last!)
        }

        return .generated(rewrittenFiles.joined(separator: "\n"))
    }

    private static func resolveBundledThemes(in config: String) -> String {
        config
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let line = String(line)
                guard let equalsIndex = line.firstIndex(of: "="),
                      line[..<equalsIndex].trimmingCharacters(in: .whitespaces) == "theme"
                else {
                    return line
                }

                let valueStart = line.index(after: equalsIndex)
                let value = line[valueStart...].trimmingCharacters(in: .whitespaces)
                guard let resolvedValue = resolveThemeValue(value) else { return line }
                return "theme = \(resolvedValue)"
            }
            .joined(separator: "\n")
    }

    private static func resolveThemeValue(_ value: String) -> String? {
        if value.contains(",") || value.hasPrefix("light:") || value.hasPrefix("dark:") {
            let entries = value.split(separator: ",", omittingEmptySubsequences: false)
            let resolvedEntries = entries.compactMap { entry -> String? in
                guard let colonIndex = entry.firstIndex(of: ":") else { return nil }
                let mode = entry[..<colonIndex].trimmingCharacters(in: .whitespaces)
                let nameStart = entry.index(after: colonIndex)
                let name = entry[nameStart...].trimmingCharacters(in: .whitespaces)
                guard mode == "light" || mode == "dark",
                      let path = installedThemePath(named: name)
                else {
                    return nil
                }
                return "\(mode):\(path)"
            }
            guard resolvedEntries.count == entries.count else { return nil }
            return resolvedEntries.joined(separator: ",")
        }

        return installedThemePath(named: value)
    }

    private static func installedThemePath(named name: String) -> String? {
        let unquotedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard !unquotedName.hasPrefix("/") else { return unquotedName }
        guard let ghosttyURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.mitchellh.ghostty"
        ) else {
            return nil
        }

        let themesDirectory = ghosttyURL
            .appendingPathComponent("Contents/Resources/ghostty/themes", isDirectory: true)
        guard let themeNames = try? FileManager.default.contentsOfDirectory(
            atPath: themesDirectory.path
        ),
            let matchingName = themeNames.first(where: {
                $0.compare(unquotedName, options: [.caseInsensitive]) == .orderedSame
            })
        else {
            return nil
        }

        return themesDirectory.appendingPathComponent(matchingName).path
    }
}

struct TerminalWorkspaceView: View {
    @Bindable var model: TerminalTabsViewModel
    let isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            terminalStack
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("terminal-workspace")
        .focusedSceneValue(
            \.terminalTabsActions,
            isVisible
                ? TerminalTabsActions(
                    tabCount: model.tabs.count,
                    addTab: { model.addTab() },
                    selectTab: { model.selectTab(at: $0) },
                    pasteImage: { model.pasteImageIntoFocusedTab() }
                )
                : nil
        )
        .onAppear { model.setWorkspaceVisible(isVisible) }
        .onChange(of: isVisible) { _, visible in
            model.setWorkspaceVisible(visible)
            if visible, let selectedTabID = model.selectedTabID {
                model.select(tabID: selectedTabID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalTabsShortcut)) { notification in
            guard isVisible,
                  let request = notification.object as? TerminalTabsShortcutRequest
            else {
                return
            }

            switch request.action {
            case .addTab:
                request.isHandled = true
                model.addTab()
            case let .selectTab(index) where model.tabs.indices.contains(index):
                request.isHandled = true
                model.selectTab(at: index)
            case .selectTab:
                break
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.tabs) { tab in
                        TerminalTabButton(
                            tab: tab,
                            isSelected: model.selectedTabID == tab.id,
                            select: { model.select(tabID: tab.id) },
                            close: { model.close(tabID: tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Button("New Terminal", systemImage: "plus") {
                model.addTab()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .hoverFeedback()
            .help("New Terminal")
            .padding(.trailing, 10)
        }
        .frame(height: 38)
        .background(.bar)
    }

    private var terminalStack: some View {
        ZStack {
            ForEach(model.tabs) { tab in
                ZStack(alignment: .bottomLeading) {
                    TerminalSurfaceView(context: tab.state)
                    TerminalURLHoverBanner(state: tab.state)
                }
                .opacity(model.selectedTabID == tab.id ? 1 : 0)
                .allowsHitTesting(model.selectedTabID == tab.id)
                .accessibilityHidden(model.selectedTabID != tab.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct TerminalTabButton: View {
    @Bindable var tab: TerminalTab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isRenaming = false
    @State private var proposedTitle = ""
    @State private var isHovering = false

    init(
        tab: TerminalTab,
        isSelected: Bool,
        select: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.select = select
        self.close = close
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: select) {
                HStack(spacing: 7) {
                    Text(tab.title)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)

                    // Reserve the close button's space while keeping the entire
                    // visible tab as the selection button's hit target.
                    Color.clear
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            Button("Close Terminal", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .hoverFeedback()
                .padding(.trailing, 6)
        }
        .background(
            Color.primary.opacity(isSelected ? 0.12 : (isHovering ? 0.07 : 0)),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename…", systemImage: "pencil") {
                beginRenaming()
            }
            Button("Close", systemImage: "xmark", action: close)
        }
        .alert("Rename Tab", isPresented: $isRenaming) {
            TextField("Tab name", text: $proposedTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                tab.rename(to: proposedTitle)
            }
        } message: {
            Text("Choose a name for this terminal tab.")
        }
    }

    private func beginRenaming() {
        proposedTitle = tab.title
        isRenaming = true
    }
}
