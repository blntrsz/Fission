import FissionCore
import SwiftUI

struct ThreadToolbarContent: ToolbarContent {
    let thread: AgentThread?
    let createThread: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("New Thread", systemImage: "plus", action: createThread)
                .keyboardShortcut("n")
        }

        // Xcode 26 couples Swift 6.2+ with the macOS 26 SDK; older SDKs
        // cannot parse sharedBackgroundVisibility, even behind #available.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            titleItem
                .sharedBackgroundVisibility(.hidden)
        } else {
            titleItem
        }
        #else
        titleItem
        #endif
    }

    @ToolbarContentBuilder
    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            title
        }
    }

    @ViewBuilder
    private var title: some View {
        if let thread {
            ThreadHeaderTitle(thread: thread)
        }
    }
}

struct ThreadHeaderTitle: View {
    let thread: AgentThread

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            Text(projectName)
                .foregroundStyle(.secondary)

            Text("/")
                .foregroundStyle(.secondary)

            Text(thread.title)
                .fontWeight(.medium)
        }
        .font(.system(size: 15))
        .padding(.leading, 8)
        .lineLimit(1)
        .help(thread.workingDirectory ?? thread.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(projectName), \(thread.title)")
    }

    private var projectName: String {
        guard let workingDirectory = thread.workingDirectory else { return "No Project" }
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return name.isEmpty ? workingDirectory : name
    }
}
