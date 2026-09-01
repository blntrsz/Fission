import SwiftUI

@main
struct FissionDesktopApp: App {
    var body: some Scene {
        WindowGroup {
            ThreadListView()
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            SidebarKeyboardCommands()
        }
    }
}

private struct ToggleSidebarActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var toggleSidebarAction: (() -> Void)? {
        get { self[ToggleSidebarActionKey.self] }
        set { self[ToggleSidebarActionKey.self] = newValue }
    }
}

private struct SidebarKeyboardCommands: Commands {
    @FocusedValue(\.toggleSidebarAction) private var toggleSidebar

    var body: some Commands {
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
