import AppKit
import Foundation
import GhosttyTerminal
import SwiftUI
import UniformTypeIdentifiers

enum TerminalDetectedURLKind: Equatable {
    case unknown
    case text
    case html
}

enum TerminalURLSource: Equatable {
    case osc8
    case detected(TerminalDetectedURLKind)
    case fissionOwned
}

struct TerminalURLTarget: Equatable {
    let rawValue: String
    let source: TerminalURLSource

    init(_ rawValue: String, source: TerminalURLSource) {
        self.rawValue = rawValue
        self.source = source
    }
}

enum TerminalURLOpenMethod: Equatable {
    case defaultApplication
    case textEditor
}

enum TerminalURLDenialReason: Equatable {
    case malformedURL
    case unsafeCharacters
    case remoteFile
    case inaccessibleFile
    case unsafeFile

    var message: String {
        switch self {
        case .malformedURL:
            "The target is not a valid absolute web, mail, or file URL."
        case .unsafeCharacters:
            "The target contains invisible, control, bidirectional, or line-breaking characters."
        case .remoteFile:
            "Terminal links cannot open files on a remote host."
        case .inaccessibleFile:
            "The local target does not exist or is not a regular file or directory."
        case .unsafeFile:
            "Opening this local target could execute code."
        }
    }
}

enum TerminalURLDecision: Equatable {
    case open(URL, using: TerminalURLOpenMethod)
    case confirm(URL)
    case deny(TerminalURLDenialReason)
}

enum TerminalURLPolicy {
    static func decision(for target: TerminalURLTarget) -> TerminalURLDecision {
        let rawValue = target.rawValue
        guard !rawValue.isEmpty else { return .deny(.malformedURL) }
        guard !rawValue.unicodeScalars.contains(where: isUnsafeCharacter) else {
            return .deny(.unsafeCharacters)
        }
        guard hasValidPercentEscapes(rawValue) else {
            return .deny(.malformedURL)
        }

        guard let url = resolvedURL(for: target),
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty
        else {
            return .deny(.malformedURL)
        }

        switch scheme {
        case "http", "https":
            guard let host = url.host, !host.isEmpty else {
                return .deny(.malformedURL)
            }
            return .open(url, using: .defaultApplication)

        case "mailto":
            guard isValidMailURL(url) else { return .deny(.malformedURL) }
            return .open(url, using: .defaultApplication)

        case "file":
            return fileDecision(for: url, source: target.source)

        default:
            return .confirm(url)
        }
    }

    private static func isValidMailURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let recipients = components.path.removingPercentEncoding,
              !recipients.isEmpty
        else {
            return false
        }
        return recipients.split(separator: ",", omittingEmptySubsequences: false).allSatisfy { recipient in
            let parts = recipient.split(separator: "@", omittingEmptySubsequences: false)
            return parts.count == 2
                && !parts[0].isEmpty
                && !parts[1].isEmpty
                && !recipient.contains(where: \.isWhitespace)
        }
    }

    private static func resolvedURL(for target: TerminalURLTarget) -> URL? {
        if let candidate = URL(string: target.rawValue), candidate.scheme != nil {
            return candidate
        }
        guard case .detected = target.source else { return nil }
        let path = NSString(string: target.rawValue).expandingTildeInPath
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func displayString(for rawValue: String) -> String {
        let normalized: String
        if let url = URL(string: rawValue), url.scheme != nil {
            normalized = url.isFileURL
                ? url.standardizedFileURL.resolvingSymlinksInPath().path
                : url.absoluteString
        } else {
            normalized = URL(fileURLWithPath: rawValue).standardizedFileURL.path
        }

        var result = String()
        result.reserveCapacity(normalized.count)
        for scalar in normalized.unicodeScalars {
            if isUnsafeCharacter(scalar) {
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func fileDecision(
        for url: URL,
        source: TerminalURLSource
    ) -> TerminalURLDecision {
        guard url.isFileURL, url.query == nil, url.fragment == nil else {
            return .deny(.malformedURL)
        }
        if let host = url.host,
           !host.isEmpty,
           host.caseInsensitiveCompare("localhost") != .orderedSame {
            return .deny(.remoteFile)
        }

        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let values: URLResourceValues
        do {
            values = try canonicalURL.resourceValues(forKeys: [
                .contentTypeKey,
                .isDirectoryKey,
                .isExecutableKey,
                .isRegularFileKey
            ])
        } catch {
            return .deny(.inaccessibleFile)
        }

        guard values.isDirectory == true || values.isRegularFile == true else {
            return .deny(.inaccessibleFile)
        }
        guard !isUnsafeFile(canonicalURL, values: values) else {
            return .deny(.unsafeFile)
        }

        let method: TerminalURLOpenMethod
        if source == .detected(.text), values.isDirectory != true {
            method = .textEditor
        } else {
            method = .defaultApplication
        }
        return .open(canonicalURL, using: method)
    }

    private static func isUnsafeFile(_ url: URL, values: URLResourceValues) -> Bool {
        if unsafePathExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        if let contentType = values.contentType,
           unsafeContentTypes.contains(where: { contentType.conforms(to: $0) }) {
            return true
        }
        return values.isDirectory != true && values.isExecutable == true
    }

    private static func isUnsafeCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator:
            true
        default:
            false
        }
    }

    private static func hasValidPercentEscapes(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        for index in scalars.indices where scalars[index] == "%" {
            guard scalars.indices.contains(index + 2),
                  isASCIIHexDigit(scalars[index + 1]),
                  isASCIIHexDigit(scalars[index + 2])
            else {
                return false
            }
        }
        return true
    }

    private static func isASCIIHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x46, 0x61...0x66:
            true
        default:
            false
        }
    }

    private static let unsafePathExtensions: Set<String> = [
        "action", "app", "applescript", "class", "command", "desktop",
        "inetloc", "jar", "mobileconfig", "mpkg", "pkg", "scpt",
        "terminal", "tool", "url", "webloc", "workflow"
    ]

    private static let unsafeContentTypes: [UTType] = [
        .application,
        .executable,
        .script
    ]
}

@MainActor
struct TerminalURLHandler {
    private let openTarget: (URL, TerminalURLOpenMethod) -> Bool
    private let confirmTarget: (URL, String) -> Void
    private let denyTarget: (TerminalURLDenialReason, String) -> Void

    init(
        open: @escaping (URL, TerminalURLOpenMethod) -> Bool,
        confirm: @escaping (URL, String) -> Void,
        deny: @escaping (TerminalURLDenialReason, String) -> Void
    ) {
        openTarget = open
        confirmTarget = confirm
        denyTarget = deny
    }

    @discardableResult
    func open(_ rawURL: String, source: TerminalURLSource) -> Bool {
        let target = TerminalURLTarget(rawURL, source: source)
        let displayString = TerminalURLPolicy.displayString(for: rawURL)
        switch TerminalURLPolicy.decision(for: target) {
        case let .open(url, method):
            return openTarget(url, method)
        case let .confirm(url):
            confirmTarget(url, displayString)
            return true
        case let .deny(reason):
            denyTarget(reason, displayString)
            return false
        }
    }

    static let system = TerminalURLHandler(
        open: { url, method in
            let workspace = NSWorkspace.shared
            switch method {
            case .defaultApplication:
                return workspace.open(url)
            case .textEditor:
                let editor = workspace.urlForApplication(toOpen: url)
                    ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
                guard let editor else { return false }
                workspace.open(
                    [url],
                    withApplicationAt: editor,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return true
            }
        },
        confirm: { url, displayString in
            TerminalURLAlert.presentConfirmation(for: url, displayString: displayString)
        },
        deny: { reason, displayString in
            TerminalURLAlert.presentBlock(reason: reason, displayString: displayString)
        }
    )
}

extension TerminalViewState: @retroactive TerminalSurfaceOpenURLDelegate {
    public func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        let source: TerminalURLSource
        switch kind {
        case .osc8:
            source = .osc8
        case .unknown:
            source = .detected(.unknown)
        case .text:
            source = .detected(.text)
        case .html:
            source = .detected(.html)
        }
        TerminalURLHandler.system.open(url, source: source)
    }
}
