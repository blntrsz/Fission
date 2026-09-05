import GhosttyTerminal
import Observation
import SwiftUI

enum TerminalSearchCommand {
    case open
    case useSelection
    case next
    case previous
    case close
}

enum GhosttySearchAction {
    case start
    case useSelection
    case query(String)
    case next
    case previous
    case end

    var binding: String {
        switch self {
        case .start: "start_search"
        case .useSelection: "search_selection"
        case let .query(query): "search:\(query)"
        case .next: "navigate_search:next"
        case .previous: "navigate_search:previous"
        case .end: "end_search"
        }
    }
}

@MainActor
@Observable
final class TerminalSearchState {
    private(set) var isPresented = false
    var query = ""
    private(set) var focusRequest = 0

    @ObservationIgnored private let performAction: (GhosttySearchAction) -> Bool
    @ObservationIgnored private let restoreTerminalFocus: () -> Void

    init(
        performAction: @escaping (GhosttySearchAction) -> Bool,
        restoreTerminalFocus: @escaping () -> Void
    ) {
        self.performAction = performAction
        self.restoreTerminalFocus = restoreTerminalFocus
    }

    func perform(_ command: TerminalSearchCommand) {
        switch command {
        case .open:
            present(query: nil)
            _ = performAction(.start)
        case .useSelection:
            _ = performAction(.useSelection)
        case .next:
            navigate(to: .next)
        case .previous:
            navigate(to: .previous)
        case .close:
            close()
        }
    }

    func present(query proposedQuery: String?) {
        if let proposedQuery {
            query = proposedQuery
        }
        isPresented = true
        requestFocus()
    }

    func requestFocus() {
        focusRequest += 1
    }

    func submitQuery() {
        _ = performAction(.query(query))
    }

    func nextMatch() {
        navigate(to: .next)
    }

    func previousMatch() {
        navigate(to: .previous)
    }

    func close() {
        isPresented = false
        _ = performAction(.end)
        restoreTerminalFocus()
    }

    private func navigate(to action: GhosttySearchAction) {
        if !isPresented {
            present(query: nil)
            submitQuery()
        }
        _ = performAction(action)
    }

    func dismissFromRenderer() {
        guard isPresented else { return }
        isPresented = false
        restoreTerminalFocus()
    }
}

struct TerminalSearchOverlay: View {
    @Bindable var search: TerminalSearchState
    @ObservedObject var terminalState: TerminalViewState
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Find", text: $search.query)
                .textFieldStyle(.plain)
                .frame(width: 190)
                .focused($isSearchFieldFocused)
                .accessibilityIdentifier("terminal-search-field")
                .onSubmit { search.nextMatch() }
                .onExitCommand { search.close() }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    search.previousMatch()
                    return .handled
                }

            matchCount
                .frame(minWidth: 42, alignment: .trailing)

            Button("Next Match", systemImage: "chevron.up") {
                search.nextMatch()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("terminal-search-next")

            Button("Previous Match", systemImage: "chevron.down") {
                search.previousMatch()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("terminal-search-previous")

            Button("Close Find", systemImage: "xmark") {
                search.close()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("terminal-search-close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.12))
        }
        .shadow(radius: 5, y: 2)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onAppear { focusSearchField() }
        .onChange(of: search.focusRequest) { _, _ in focusSearchField() }
        .task(id: search.query) {
            if !search.query.isEmpty, search.query.count < 3 {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            search.submitQuery()
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    private var matchCount: some View {
        Group {
            if let selected = terminalState.selectedSearchMatchIndex {
                Text("\(selected + 1)/\(terminalState.searchMatchCount.map(String.init) ?? "?")")
            } else if let total = terminalState.searchMatchCount {
                Text("-/\(total)")
            } else {
                Text("-/-")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityIdentifier("terminal-search-count")
    }
}
