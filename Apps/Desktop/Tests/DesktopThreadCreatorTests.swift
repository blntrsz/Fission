import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

@MainActor
struct DesktopThreadCreatorTests {
    @Test func createsWorktreeUnderFissionHomeUsingGeneratedBranchName() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = temporaryDirectory.appending(path: "ExampleRepo", directoryHint: .isDirectory)
        let worktreeRoot = temporaryDirectory.appending(path: "worktrees", directoryHint: .isDirectory)
        let selectedDirectory = repository
            .appending(path: "Sources", directoryHint: .isDirectory)
            .appending(path: "Feature", directoryHint: .isDirectory)
        let expectedWorktree = worktreeRoot
            .appending(path: "ExampleRepo", directoryHint: .isDirectory)
            .appending(path: "fission-1de6e4", directoryHint: .isDirectory)
        let expectedWorkingDirectory = expectedWorktree
            .appending(path: "Sources/Feature", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
        try runGit(["init", repository.path])
        try runGit(["-C", repository.path, "config", "user.name", "Fission Tests"])
        try runGit(["-C", repository.path, "config", "user.email", "tests@fission.local"])
        try Data().write(to: selectedDirectory.appending(path: "README.md"))
        try runGit(["-C", repository.path, "add", "."])
        try runGit(["-C", repository.path, "commit", "-m", "Initial commit"])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: selectedDirectory.path,
            createWorktree: true,
            worktreeRoot: worktreeRoot,
            makeIdentifier: { "1de6e4" }
        )

        let thread = try #require(model.threads.first { $0.id == threadID })
        #expect(thread.title == "fission-1de6e4")
        #expect(thread.workingDirectory == expectedWorkingDirectory.path)
        #expect(thread.projectName == "Feature")
        #expect(FileManager.default.fileExists(atPath: expectedWorkingDirectory.path))
        #expect(try gitOutput(["-C", expectedWorktree.path, "branch", "--show-current"]) == "fission-1de6e4")
    }

    @Test func retriesWhenGeneratedBranchAlreadyExists() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = temporaryDirectory.appending(path: "ExampleRepo", directoryHint: .isDirectory)
        let worktreeRoot = temporaryDirectory.appending(path: "worktrees", directoryHint: .isDirectory)
        let expectedWorktree = worktreeRoot
            .appending(path: "ExampleRepo", directoryHint: .isDirectory)
            .appending(path: "fission-second", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", repository.path])
        try runGit(["-C", repository.path, "config", "user.name", "Fission Tests"])
        try runGit(["-C", repository.path, "config", "user.email", "tests@fission.local"])
        try Data().write(to: repository.appending(path: "README.md"))
        try runGit(["-C", repository.path, "add", "README.md"])
        try runGit(["-C", repository.path, "commit", "-m", "Initial commit"])
        try runGit(["-C", repository.path, "branch", "fission-taken1"])
        let identifiers = IdentifierSequence(["taken1", "second"])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: repository.path,
            createWorktree: true,
            worktreeRoot: worktreeRoot,
            makeIdentifier: identifiers.next
        )

        let thread = try #require(model.threads.first { $0.id == threadID })
        #expect(thread.title == "fission-second")
        #expect(thread.workingDirectory == expectedWorktree.path)
        #expect(thread.projectName == "ExampleRepo")
        #expect(try gitOutput(["-C", expectedWorktree.path, "branch", "--show-current"]) == "fission-second")
    }

    @Test func createsWorktreeUsingRequestedBranchName() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = temporaryDirectory.appending(path: "ExampleRepo", directoryHint: .isDirectory)
        let worktreeRoot = temporaryDirectory.appending(path: "worktrees", directoryHint: .isDirectory)
        let expectedWorktree = worktreeRoot
            .appending(path: "ExampleRepo", directoryHint: .isDirectory)
            .appending(path: "my-feature", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", repository.path])
        try runGit(["-C", repository.path, "config", "user.name", "Fission Tests"])
        try runGit(["-C", repository.path, "config", "user.email", "tests@fission.local"])
        try Data().write(to: repository.appending(path: "README.md"))
        try runGit(["-C", repository.path, "add", "README.md"])
        try runGit(["-C", repository.path, "commit", "-m", "Initial commit"])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: repository.path,
            createWorktree: true,
            worktreeRoot: worktreeRoot,
            worktreeBranch: " my-feature ",
            makeIdentifier: { "unused" }
        )

        let thread = try #require(model.threads.first { $0.id == threadID })
        #expect(thread.title == "my-feature")
        #expect(thread.workingDirectory == expectedWorktree.path)
        #expect(try gitOutput(["-C", expectedWorktree.path, "branch", "--show-current"]) == "my-feature")
    }

    @Test func reportsWhenRequestedWorktreeBranchAlreadyExists() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = temporaryDirectory.appending(path: "ExampleRepo", directoryHint: .isDirectory)
        let worktreeRoot = temporaryDirectory.appending(path: "worktrees", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", repository.path])
        try runGit(["-C", repository.path, "config", "user.name", "Fission Tests"])
        try runGit(["-C", repository.path, "config", "user.email", "tests@fission.local"])
        try Data().write(to: repository.appending(path: "README.md"))
        try runGit(["-C", repository.path, "add", "README.md"])
        try runGit(["-C", repository.path, "commit", "-m", "Initial commit"])
        try runGit(["-C", repository.path, "branch", "taken-branch"])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: repository.path,
            createWorktree: true,
            worktreeRoot: worktreeRoot,
            worktreeBranch: "taken-branch",
            makeIdentifier: { "unused" }
        )

        #expect(threadID == nil)
        #expect(model.threads.isEmpty)
        #expect(model.errorMessage == "A branch named \"taken-branch\" already exists.")
    }

    @Test func reportsWhenRequestedWorktreeBranchIsInvalid() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = temporaryDirectory.appending(path: "ExampleRepo", directoryHint: .isDirectory)
        let worktreeRoot = temporaryDirectory.appending(path: "worktrees", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", repository.path])
        try runGit(["-C", repository.path, "config", "user.name", "Fission Tests"])
        try runGit(["-C", repository.path, "config", "user.email", "tests@fission.local"])
        try Data().write(to: repository.appending(path: "README.md"))
        try runGit(["-C", repository.path, "add", "README.md"])
        try runGit(["-C", repository.path, "commit", "-m", "Initial commit"])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: repository.path,
            createWorktree: true,
            worktreeRoot: worktreeRoot,
            worktreeBranch: "bad name",
            makeIdentifier: { "unused" }
        )

        #expect(threadID == nil)
        #expect(model.errorMessage == "Enter a valid Git branch name.")
    }

    private func runGit(_ arguments: [String]) throws {
        _ = try gitOutput(arguments)
    }

    private func gitOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw TestGitError.commandFailed(message)
        }
        return message
    }
}

private final class IdentifierSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String]

    init(_ identifiers: [String]) {
        self.identifiers = identifiers
    }

    func next() -> String {
        lock.withLock { identifiers.removeFirst() }
    }
}

private enum TestGitError: Error {
    case commandFailed(String)
}

struct GitWorktreeBranchTests {
    @Test func trimsAndTreatsBlankNamesAsGenerated() {
        #expect(GitWorktreeBranch.normalized(nil) == nil)
        #expect(GitWorktreeBranch.normalized("  ") == nil)
        #expect(GitWorktreeBranch.normalized(" feat/login ") == "feat/login")
    }

    @Test func acceptsTypicalBranchNamesAndRejectsInvalidOnes() {
        #expect(GitWorktreeBranch.isValid("my-feature"))
        #expect(GitWorktreeBranch.isValid("feat/login"))
        #expect(!GitWorktreeBranch.isValid(""))
        #expect(!GitWorktreeBranch.isValid("bad name"))
        #expect(!GitWorktreeBranch.isValid("-leading-dash"))
        #expect(!GitWorktreeBranch.isValid(".hidden"))
        #expect(!GitWorktreeBranch.isValid("ends."))
        #expect(!GitWorktreeBranch.isValid("foo..bar"))
        #expect(!GitWorktreeBranch.isValid("@"))
    }
}
