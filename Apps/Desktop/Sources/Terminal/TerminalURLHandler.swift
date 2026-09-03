import AppKit
import Foundation
import GhosttyTerminal

@MainActor
struct TerminalURLHandler {
    private let openURL: (URL) -> Bool

    init(_ openURL: @escaping (URL) -> Bool) {
        self.openURL = openURL
    }

    @discardableResult
    func open(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL), url.scheme != nil else { return false }
        return openURL(url)
    }

    static let system = TerminalURLHandler { NSWorkspace.shared.open($0) }
}

extension TerminalViewState: @retroactive TerminalSurfaceOpenURLDelegate {
    public func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
        TerminalURLHandler.system.open(url)
    }
}
