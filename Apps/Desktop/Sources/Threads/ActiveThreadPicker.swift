import FissionCore
import SwiftUI

struct ActiveThreadPicker: View {
    let threads: [AgentThread]
    let selectedThreadID: UUID?
    let select: (UUID) -> Void
    let cancel: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: 600, height: 420)
        .background(.regularMaterial)
        .task {
            selectCurrentThread()
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedIndex = results.isEmpty ? -1 : 0
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
        .onExitCommand(perform: cancel)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search active Threads", text: $query)
                .accessibilityIdentifier("active-thread-search-field")
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)

            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    query = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)

        // A hidden default button lets Return select without taking focus from the search field.
        .background {
            Button("Open Thread", action: openSelectedThread)
                .keyboardShortcut(.defaultAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, thread in
                            resultRow(thread, at: index)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: selectedIndex) { _, index in
                    guard index >= 0 else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func resultRow(_ thread: AgentThread, at index: Int) -> some View {
        Button {
            select(thread.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: thread.id == selectedThreadID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(thread.id == selectedThreadID ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let context = ActiveThreadSearch.context(for: thread) {
                        Text(context)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .contentShape(Rectangle())
            .background(
                index == selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("active-thread-result-\(thread.id.uuidString)")
        .onHover { isHovering in
            if isHovering {
                selectedIndex = index
            }
        }
    }

    private var results: [AgentThread] {
        ActiveThreadSearch.results(matching: query, in: threads)
    }

    private func selectCurrentThread() {
        selectedIndex = results.firstIndex { $0.id == selectedThreadID } ?? 0
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    private func openSelectedThread() {
        guard results.indices.contains(selectedIndex) else { return }
        select(results[selectedIndex].id)
    }
}

enum ActiveThreadSearch {
    static func results(matching query: String, in threads: [AgentThread]) -> [AgentThread] {
        let activeThreads = threads.filter { !$0.isSettled }
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !terms.isEmpty else { return activeThreads }

        return activeThreads.filter { thread in
            let searchableText = [
                thread.title,
                thread.projectName,
                thread.workingDirectory,
                thread.remoteCommand
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            return terms.allSatisfy {
                searchableText.localizedCaseInsensitiveContains($0)
            }
        }
    }

    static func context(for thread: AgentThread) -> String? {
        if let projectName = thread.projectName, !projectName.isEmpty {
            return projectName
        }
        guard let workingDirectory = thread.workingDirectory else { return nil }
        let directoryName = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return directoryName.isEmpty ? workingDirectory : directoryName
    }
}
