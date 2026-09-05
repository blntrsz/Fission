@testable import FissionDesktop
import Foundation
import Testing

@MainActor
struct TerminalURLHandlerTests {
    @Test func safeWebAndMailLinksAreAllowed() throws {
        let httpsURL = try #require(URL(string: "https://example.com/issues/3"))
        let mailURL = try #require(URL(string: "mailto:hello@example.com"))

        let httpsDecision = TerminalURLPolicy.decision(
            for: .init(httpsURL.absoluteString, source: .osc8)
        )
        let mailDecision = TerminalURLPolicy.decision(
            for: .init(mailURL.absoluteString, source: .osc8)
        )
        #expect(httpsDecision == .open(httpsURL, using: .defaultApplication))
        #expect(mailDecision == .open(mailURL, using: .defaultApplication))
    }

    @Test(arguments: [
        "https:relative",
        "https:///missing-host",
        "mailto:",
        "mailto:not-an-address",
        "https://example.com/%ZZ",
        "relative/path"
    ])
    func malformedWebMailAndRelativeTargetsAreDenied(rawURL: String) {
        #expect(TerminalURLPolicy.decision(for: .init(rawURL, source: .osc8)) == .deny(.malformedURL))
    }

    @Test(arguments: [
        "https://example.com/real\nhttps://evil.example",
        "https://example.com/\u{202E}evil",
        "https://example.com/zero\u{200B}width",
        "https://example.com/function\u{2062}application",
        "https://example.com/soft\u{00AD}hyphen",
        "https://example.com/line\u{2028}break"
    ])
    func invisibleControlBidiAndLineCharactersAreDenied(rawURL: String) {
        #expect(TerminalURLPolicy.decision(for: .init(rawURL, source: .osc8)) == .deny(.unsafeCharacters))
    }

    @Test func safeLocalTextFileIsCanonicalizedAndUsesEditor() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let disguised = directory.appendingPathComponent("folder/../notes.txt").absoluteString

        let decision = TerminalURLPolicy.decision(for: .init(disguised, source: .detected(.text)))

        #expect(decision == .open(file.standardizedFileURL, using: .textEditor))
    }

    @Test func schemeLessDetectedTextPathUsesEditor() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let decision = TerminalURLPolicy.decision(
            for: .init(file.path, source: .detected(.text))
        )
        #expect(decision == .open(file.standardizedFileURL, using: .textEditor))
    }

    @Test func remoteFileHostIsDenied() {
        let decision = TerminalURLPolicy.decision(
            for: .init("file://server.example/tmp/notes.txt", source: .osc8)
        )
        #expect(decision == .deny(.remoteFile))
    }

    @Test func missingAndSpecialFilesAreDenied() {
        let missing = TerminalURLPolicy.decision(
            for: .init("file:///definitely/missing/fission-file", source: .osc8)
        )
        let special = TerminalURLPolicy.decision(
            for: .init("file:///dev/null", source: .osc8)
        )
        #expect(missing == .deny(.inaccessibleFile))
        #expect(special == .deny(.inaccessibleFile))
    }

    @Test(arguments: [
        "payload.command",
        "payload.sh",
        "Payload.app",
        "installer.pkg",
        "profile.mobileconfig"
    ])
    func dangerousFileTypesAreDenied(name: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(name)
        if name.hasSuffix(".app") {
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        } else {
            try "content".write(to: file, atomically: true, encoding: .utf8)
        }

        #expect(TerminalURLPolicy.decision(for: .init(file.absoluteString, source: .osc8)) == .deny(.unsafeFile))
    }

    @Test func executableFileAndSymlinkToExecutableAreDenied() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("payload")
        let symlink = directory.appendingPathComponent("notes.txt")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: executable)

        #expect(TerminalURLPolicy.decision(for: .init(executable.absoluteString, source: .osc8)) == .deny(.unsafeFile))
        #expect(TerminalURLPolicy.decision(for: .init(symlink.absoluteString, source: .osc8)) == .deny(.unsafeFile))
    }

    @Test func customSchemesRequireConfirmationForEverySource() throws {
        let url = try #require(URL(string: "my-tool://perform/action"))

        let osc8 = TerminalURLPolicy.decision(
            for: .init(url.absoluteString, source: .osc8)
        )
        let detected = TerminalURLPolicy.decision(
            for: .init(url.absoluteString, source: .detected(.unknown))
        )
        let owned = TerminalURLPolicy.decision(
            for: .init(url.absoluteString, source: .fissionOwned)
        )
        #expect(osc8 == .confirm(url))
        #expect(detected == .confirm(url))
        #expect(owned == .confirm(url))
    }

    @Test func handlerRoutesAllowedConfirmedAndDeniedDecisions() throws {
        let webURL = try #require(URL(string: "https://example.com"))
        let customURL = try #require(URL(string: "my-tool://perform/action"))
        var opened: [(URL, TerminalURLOpenMethod)] = []
        var confirmed: URL?
        var denied: TerminalURLDenialReason?
        let handler = TerminalURLHandler(
            open: { url, method in
                opened.append((url, method))
                return true
            },
            confirm: { url, _ in confirmed = url },
            deny: { reason, _ in denied = reason }
        )

        #expect(handler.open(webURL.absoluteString, source: .osc8))
        #expect(handler.open(customURL.absoluteString, source: .osc8))
        #expect(!handler.open("https:relative", source: .osc8))
        #expect(opened.map(\.0) == [webURL])
        #expect(confirmed == customURL)
        #expect(denied == .malformedURL)
    }

    @Test func confirmationIdentifiesRegisteredHandler() {
        let application = URL(fileURLWithPath: "/Applications/Example Browser.app")

        #expect(TerminalURLAlert.handlerDescription(applicationURL: application) == "“Example Browser”")
        #expect(TerminalURLAlert.handlerDescription(applicationURL: nil) == "the default application")
    }

    @Test func hoverDestinationEscapesUnsafeCharactersAndCanonicalizesFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("folder/../notes.txt").absoluteString

        #expect(TerminalURLPolicy.displayString(for: "https://example.com/a\nline") == "https://example.com/a%0Aline")
        #expect(TerminalURLPolicy.displayString(for: path) == directory.appendingPathComponent("notes.txt").path)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
