import AppKit
import GhosttyTerminal
import SwiftUI

@MainActor
enum TerminalURLAlert {
    static func presentConfirmation(for url: URL, displayString: String) {
        deferPresentation {
            let workspace = NSWorkspace.shared
            let handler = handlerDescription(
                applicationURL: workspace.urlForApplication(toOpen: url)
            )
            let alert = makeAlert(
                message: "Open Link from Terminal Output?",
                information: """
                This link will open in \(handler). Only continue if you recognize \
                and trust the destination.
                """,
                displayString: displayString,
                buttons: ["Cancel", "Open Link"]
            )
            present(alert) { response in
                guard response == .alertSecondButtonReturn else { return }
                _ = workspace.open(url)
            }
        }
    }

    static func handlerDescription(applicationURL: URL?) -> String {
        applicationURL
            .map { "“\($0.deletingPathExtension().lastPathComponent)”" }
            ?? "the default application"
    }

    static func presentBlock(reason: TerminalURLDenialReason, displayString: String) {
        deferPresentation {
            let alert = makeAlert(
                message: "Fission Blocked This Link",
                information: reason.message,
                displayString: displayString,
                buttons: ["OK", "Copy Link"]
            )
            present(alert) { response in
                guard response == .alertSecondButtonReturn else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayString, forType: .string)
            }
        }
    }

    private static func deferPresentation(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        DispatchQueue.main.async(execute: action)
    }

    private static func present(
        _ alert: NSAlert,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private static func makeAlert(
        message: String,
        information: String,
        displayString: String,
        buttons: [String]
    ) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName)
        alert.messageText = message
        alert.informativeText = information
        alert.accessoryView = targetView(displayString)
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        return alert
    }

    private static func targetView(_ target: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 96))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = target
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }
}

struct TerminalURLHoverBanner: View {
    @ObservedObject var state: TerminalViewState

    var body: some View {
        if let hoveredLink = state.hoveredLink {
            let displayString = TerminalURLPolicy.displayString(for: hoveredLink)
            Text(verbatim: displayString)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: UnevenRoundedRectangle(cornerRadii: .init(topTrailing: 9)))
                .accessibilityLabel("Link destination")
                .accessibilityValue(displayString)
                .accessibilityIdentifier("terminal-link-destination")
                .allowsHitTesting(false)
        }
    }
}
