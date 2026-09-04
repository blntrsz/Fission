import FissionCore
import SwiftUI

struct ThreadListView: View {
    let model: ThreadListModel
    @State private var isCreatingThread = false
    @State private var newThreadTitle = ""
    @State private var searchText = ""
    @State private var sortOrder = ThreadSortOrder.recentlyUpdated
    @State private var isSettledExpanded = false
    @State private var settledDisplayLimit = 20

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

            Group {
                if model.isLoading {
                    ProgressView("Loading Threads…")
                } else if displayedThreads.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Threads" : "No Results",
                        systemImage: searchText.isEmpty
                            ? "bubble.left.and.text.bubble.right"
                            : "magnifyingglass",
                        description: Text(
                            searchText.isEmpty
                                ? "Create a Thread to start a new agent workstream."
                                : "Try searching for a different thread."
                        )
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(
                                Array(activeThreads.enumerated()),
                                id: \.element.id
                            ) { index, thread in
                                VStack(spacing: 0) {
                                    threadButton(thread) {
                                        ThreadRow(thread: thread)
                                    }

                                    if index < activeThreads.count - 1 {
                                        Rectangle()
                                            .fill(.white.opacity(0.09))
                                            .frame(height: 1)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .containerRelativeFrame(.horizontal)
                            }

                            settledSection
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .background(.black)
        }
        .preferredColorScheme(.dark)
        .task { await model.load() }
        .sheet(isPresented: $isCreatingThread, onDismiss: {
            newThreadTitle = ""
        }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("New Thread")
                        .font(.title2.bold())

                    Spacer()

                    Button("Close", systemImage: "xmark") {
                        isCreatingThread = false
                    }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
                }

                TextField("What should the agent work on?", text: $newThreadTitle)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                Button {
                    let title = newThreadTitle
                    newThreadTitle = ""
                    isCreatingThread = false
                    Task { await model.createThread(title: title) }
                } label: {
                    Text("Create Thread")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(
                    newThreadTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .opacity(
                    newThreadTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? 0.4
                        : 1
                )
            }
            .padding(20)
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.black)
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

    private var header: some View {
        HStack {
            Text("Fission")
                .font(.system(size: 24, weight: .bold))

            Spacer()

            Menu {
                Button("Settings", systemImage: "gearshape") {
                    // Settings will be connected when that screen is added.
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .accessibilityLabel("More")
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.top, -12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Sort Threads", selection: $sortOrder) {
                    ForEach(ThreadSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                FooterItem(systemImage: "line.3.horizontal.decrease")
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))

                TextField("Search", text: $searchText)
                    .font(.system(size: 20))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.14), lineWidth: 1)
            }

            Button {
                isCreatingThread = true
            } label: {
                FooterItem(systemImage: "square.and.pencil")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func threadButton<Label: View>(
        _ thread: AgentThread,
        @ViewBuilder label: () -> Label
    ) -> some View {
        NavigationLink {
            ThreadDetailView(thread: thread)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.deleteThreads(ids: [thread.id]) }
            }
        }
    }

    private var settledSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSettledExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(
                        isSettledExpanded
                            ? "Settled"
                            : "Settled (\(settledThreads.count))"
                    )
                    .fixedSize()

                    Rectangle()
                        .fill(.white.opacity(0.09))
                        .frame(height: 1)

                    Image(systemName: isSettledExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .buttonStyle(.plain)

            if isSettledExpanded {
                ForEach(Array(settledThreads.prefix(settledDisplayLimit))) { thread in
                    threadButton(thread) {
                        SettledThreadRow(thread: thread)
                    }
                }

                if settledThreads.count > settledDisplayLimit {
                    Button {
                        settledDisplayLimit += 20
                    } label: {
                        Text(
                            "Load more (\(settledThreads.count - settledDisplayLimit) remaining)"
                        )
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    .white.opacity(0.09),
                                    style: StrokeStyle(lineWidth: 1, dash: [5])
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var activeThreads: [AgentThread] {
        displayedThreads.filter { !$0.isSettled }
    }

    private var settledThreads: [AgentThread] {
        displayedThreads.filter(\.isSettled)
    }

    private var displayedThreads: [AgentThread] {
        let filtered = searchText.isEmpty
            ? model.threads
            : model.threads.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }

        switch sortOrder {
        case .recentlyUpdated:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .oldestUpdated:
            return filtered.sorted { $0.updatedAt < $1.updatedAt }
        case .title:
            return filtered.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}

private enum ThreadSortOrder: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case oldestUpdated
    case title

    var id: Self { self }

    var title: String {
        switch self {
        case .recentlyUpdated: "Recently Updated"
        case .oldestUpdated: "Oldest Updated"
        case .title: "Title"
        }
    }
}

private struct FooterItem: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.08), in: Circle())
            .overlay {
                Circle().stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .contentShape(Circle())
    }
}

private struct ThreadDetailView: View {
    let thread: AgentThread

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(thread.status.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(thread.title)
                    .font(.largeTitle.bold())
            }

            Divider()

            VStack(spacing: 16) {
                LabeledContent("Status", value: thread.status.rawValue.capitalized)
                LabeledContent("Created") {
                    Text(thread.createdAt, style: .date)
                }
                LabeledContent("Last updated") {
                    Text(thread.updatedAt, style: .relative)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettledThreadRow: View {
    let thread: AgentThread

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))

            Text(thread.title)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(thread.updatedAt, style: .relative)
                .fixedSize()
        }
        .font(.system(size: 19))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

private struct ThreadRow: View {
    let thread: AgentThread

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(thread.status.rawValue.capitalized)
                Spacer()
                Text(thread.updatedAt, style: .relative)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)

            Text(thread.title)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

#Preview {
    ThreadListView(model: ThreadListModel(databasePath: ":memory:"))
}
