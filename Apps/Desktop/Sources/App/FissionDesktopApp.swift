import AppKit
import FissionCore
import SwiftUI

extension Notification.Name {
    static let terminalTabsShortcut = Notification.Name("terminalTabsShortcut")
}

final class TerminalTabsShortcutRequest {
    enum Action {
        case addTab
        case selectTab(Int)
    }

    let action: Action
    var isHandled = false

    init(action: Action) {
        self.action = action
    }
}

@main
struct FissionDesktopApp: App {
    @State private var threadListModel = ThreadListModel(
        databasePath: ThreadListModel.applicationSupportDatabasePath
    )

    private static let terminalTabsShortcutMonitor = NSEvent.addLocalMonitorForEvents(
        matching: .keyDown
    ) { event in
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let action: TerminalTabsShortcutRequest.Action?

        if modifiers == .command, let index = terminalTabIndex(for: event.keyCode) {
            action = .selectTab(index)
        } else if modifiers == [.command, .shift], event.keyCode == 45 {
            action = .addTab
        } else {
            action = nil
        }

        guard let action else { return event }
        let request = TerminalTabsShortcutRequest(action: action)
        NotificationCenter.default.post(name: .terminalTabsShortcut, object: request)
        return request.isHandled ? nil : event
    }

    init() {
        _ = Self.terminalTabsShortcutMonitor
    }

    private static func terminalTabIndex(for keyCode: UInt16) -> Int? {
        // Physical number-row key codes make the shortcuts independent of keyboard layout.
        switch keyCode {
        case 18: 0
        case 19: 1
        case 20: 2
        case 21: 3
        case 23: 4
        case 22: 5
        case 26: 6
        case 28: 7
        case 25: 8
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ThreadListView(model: threadListModel)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            AppKeyboardCommands()
        }
    }
}

private struct ToggleSidebarActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct TerminalTabsActions {
    let tabCount: Int
    let addTab: () -> Void
    let selectTab: (Int) -> Void
}

private struct TerminalTabsActionsKey: FocusedValueKey {
    typealias Value = TerminalTabsActions
}

extension FocusedValues {
    var toggleSidebarAction: (() -> Void)? {
        get { self[ToggleSidebarActionKey.self] }
        set { self[ToggleSidebarActionKey.self] = newValue }
    }

    var terminalTabsActions: TerminalTabsActions? {
        get { self[TerminalTabsActionsKey.self] }
        set { self[TerminalTabsActionsKey.self] = newValue }
    }
}

private struct AppKeyboardCommands: Commands {
    @FocusedValue(\.toggleSidebarAction) private var toggleSidebar
    @FocusedValue(\.terminalTabsActions) private var terminalTabs

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Terminal Tab") {
                terminalTabs?.addTab()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(terminalTabs == nil)

            ForEach(1...9, id: \.self) { tabNumber in
                Button("Select Terminal Tab \(tabNumber)") {
                    terminalTabs?.selectTab(tabNumber - 1)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character(String(tabNumber))),
                    modifiers: .command
                )
                .disabled(tabNumber > (terminalTabs?.tabCount ?? 0))
            }
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                toggleSidebar?()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(toggleSidebar == nil)

            Button("Toggle Sidebar (Command-S)") {
                toggleSidebar?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(toggleSidebar == nil)
        }
    }
}
