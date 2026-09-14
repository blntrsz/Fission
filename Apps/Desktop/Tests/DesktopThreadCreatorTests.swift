import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

@MainActor
struct DesktopThreadCreatorTests {
    @Test func createsCopyOnWriteIsolateNamedAfterTheRepository() async throws {
        let fixture = try IsolateFixture.makeGitRepository(withNestedSelection: true)
        defer { fixture.tearDown() }

        try Data("dirty".utf8).write(to: fixture.repository.appending(path: "dirty.txt"))
        try Data("untracked".utf8).write(to: fixture.repository.appending(path: "untracked.txt"))
        try FileManager.default.createDirectory(
            at: fixture.repository.appending(path: "node_modules"),
            withIntermediateDirectories: true
        )
        try Data("dep".utf8).write(to: fixture.repository.appending(path: "node_modules/pkg.js"))

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: fixture.selectedDirectory.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            makeIdentifier: { "1de6e4" }
        )

        let thread = try #require(model.threads.first { $0.id == threadID })
        let expectedRoot = fixture.isolateRoot
            .appending(path: "ExampleRepo")
            .appending(path: "fission-1de6e4")
            .appending(path: "ExampleRepo")
        let expectedWorkingDirectory = expectedRoot.appending(path: "Sources/Feature")

        #expect(thread.title == "fission-1de6e4")
        #expect(thread.workingDirectory == expectedWorkingDirectory.path)
        #expect(thread.projectName == "Feature")
        #expect(try String(contentsOf: expectedRoot.appending(path: "dirty.txt"), encoding: .utf8) == "dirty")
        #expect(try String(contentsOf: expectedRoot.appending(path: "untracked.txt"), encoding: .utf8) == "untracked")
        #expect(try String(contentsOf: expectedRoot.appending(path: "node_modules/pkg.js"), encoding: .utf8) == "dep")
        #expect(try gitOutput(["-C", expectedRoot.path, "branch", "--show-current"]) == "fission-1de6e4")
        #expect(try gitOutput(["-C", fixture.repository.path, "branch", "--show-current"]) != "fission-1de6e4")
        var gitIsDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(
                atPath: expectedRoot.appending(path: ".git").path,
                isDirectory: &gitIsDirectory
            )
        )
        #expect(gitIsDirectory.boolValue)
        #expect(
            !(try gitOutput(["-C", fixture.repository.path, "worktree", "list"])
                .contains(expectedRoot.path))
        )
    }

    @Test func retriesWhenGeneratedBranchAlreadyExists() async throws {
        let fixture = try IsolateFixture.makeGitRepository(withNestedSelection: false)
        defer { fixture.tearDown() }
        try runGit(["-C", fixture.repository.path, "branch", "fission-taken1"])
        let identifiers = IdentifierSequence(["taken1", "second"])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: fixture.repository.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            makeIdentifier: identifiers.next
        )

        let thread = try #require(model.threads.first { $0.id == threadID })
        let expectedRoot = fixture.isolateRoot
            .appending(path: "ExampleRepo")
            .appending(path: "fission-second")
            .appending(path: "ExampleRepo")
        #expect(thread.title == "fission-second")
        #expect(thread.workingDirectory == expectedRoot.path)
        #expect(try gitOutput(["-C", expectedRoot.path, "branch", "--show-current"]) == "fission-second")
    }

    @Test func isolatesANonGitFolder() async throws {
        let fixture = try IsolateFixture.makePlainFolder()
        defer { fixture.tearDown() }

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: fixture.repository.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            makeIdentifier: { "plain1" }
        )

        let thread = try #require(model.threads.first { $0.id == threadID })
        let expectedRoot = fixture.isolateRoot
            .appending(path: "ExampleRepo")
            .appending(path: "fission-plain1")
            .appending(path: "ExampleRepo")
        #expect(thread.title == "local")
        #expect(thread.workingDirectory == expectedRoot.path)
        #expect(try String(contentsOf: expectedRoot.appending(path: "notes.txt"), encoding: .utf8) == "hello")
    }

    @Test func createsIsolateUsingRequestedBranchName() async throws {
        let fixture = try IsolateFixture.makeGitRepository(withNestedSelection: false)
        defer { fixture.tearDown() }

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: fixture.repository.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            isolateBranch: " my-feature ",
            makeIdentifier: { "unused" }
        )

        let thread = try #require(model.threads.first { $0.id == threadID })
        let expectedRoot = fixture.isolateRoot
            .appending(path: "ExampleRepo")
            .appending(path: "my-feature")
            .appending(path: "ExampleRepo")
        #expect(thread.title == "my-feature")
        #expect(thread.workingDirectory == expectedRoot.path)
        #expect(try gitOutput(["-C", expectedRoot.path, "branch", "--show-current"]) == "my-feature")
    }

    @Test func reportsWhenRequestedIsolateBranchAlreadyExists() async throws {
        let fixture = try IsolateFixture.makeGitRepository(withNestedSelection: false)
        defer { fixture.tearDown() }
        try runGit(["-C", fixture.repository.path, "branch", "taken-branch"])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: fixture.repository.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            isolateBranch: "taken-branch",
            makeIdentifier: { "unused" }
        )

        #expect(threadID == nil)
        #expect(model.errorMessage == "A branch named \"taken-branch\" already exists.")
    }

    @Test func reportsWhenRequestedIsolateBranchIsInvalid() async throws {
        let fixture = try IsolateFixture.makeGitRepository(withNestedSelection: false)
        defer { fixture.tearDown() }

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: fixture.repository.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            isolateBranch: "bad name",
            makeIdentifier: { "unused" }
        )

        #expect(threadID == nil)
        #expect(model.errorMessage == "Enter a valid Git branch name.")
    }

    @Test func refusesALinkedGitWorktree() async throws {
        let fixture = try IsolateFixture.makeGitRepository(withNestedSelection: false)
        defer { fixture.tearDown() }
        let worktree = fixture.temporaryDirectory.appending(path: "linked", directoryHint: .isDirectory)
        try runGit(["-C", fixture.repository.path, "worktree", "add", "--detach", worktree.path])

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: worktree.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            makeIdentifier: { "nope" }
        )

        #expect(threadID == nil)
        #expect(model.errorMessage == IsolateError.linkedWorktree.errorDescription)
    }

    @Test func removeIsolateDeletesTheFissionDirectory() async throws {
        let fixture = try IsolateFixture.makeGitRepository(withNestedSelection: false)
        defer { fixture.tearDown() }

        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = await DesktopThreadCreator.create(
            in: model,
            workingDirectory: fixture.repository.path,
            createIsolate: true,
            isolateRoot: fixture.isolateRoot,
            makeIdentifier: { "gone1" }
        )
        let thread = try #require(model.threads.first { $0.id == threadID })
        let isolateDirectory = fixture.isolateRoot
            .appending(path: "ExampleRepo")
            .appending(path: "fission-gone1")
        #expect(FileManager.default.fileExists(atPath: isolateDirectory.path))

        try ProjectIsolator.removeIsolate(
            workingDirectory: thread.workingDirectory,
            isolateRoot: fixture.isolateRoot
        )
        #expect(!FileManager.default.fileExists(atPath: isolateDirectory.path))
        #expect(FileManager.default.fileExists(atPath: fixture.repository.path))
    }
}

private struct IsolateFixture {
    let temporaryDirectory: URL
    let repository: URL
    let isolateRoot: URL
    let selectedDirectory: URL

    static func makeGitRepository(withNestedSelection: Bool) throws -> IsolateFixture {
        let fixture = try makeDirectories(withNestedSelection: withNestedSelection)
        try FileManager.default.createDirectory(at: fixture.selectedDirectory, withIntermediateDirectories: true)
        try runGit(["init", fixture.repository.path])
        try runGit(["-C", fixture.repository.path, "config", "user.name", "Fission Tests"])
        try runGit(["-C", fixture.repository.path, "config", "user.email", "tests@fission.local"])
        try Data("initial".utf8).write(to: fixture.selectedDirectory.appending(path: "README.md"))
        try runGit(["-C", fixture.repository.path, "add", "."])
        try runGit(["-C", fixture.repository.path, "commit", "-m", "Initial commit"])
        return fixture
    }

    static func makePlainFolder() throws -> IsolateFixture {
        let fixture = try makeDirectories(withNestedSelection: false)
        try FileManager.default.createDirectory(at: fixture.repository, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: fixture.repository.appending(path: "notes.txt"))
        return fixture
    }

    private static func makeDirectories(withNestedSelection: Bool) throws -> IsolateFixture {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = temporaryDirectory.appending(path: "ExampleRepo", directoryHint: .isDirectory)
        let isolateRoot = temporaryDirectory.appending(path: "worktrees", directoryHint: .isDirectory)
        let selectedDirectory = if withNestedSelection {
            repository
                .appending(path: "Sources", directoryHint: .isDirectory)
                .appending(path: "Feature", directoryHint: .isDirectory)
        } else {
            repository
        }
        return IsolateFixture(
            temporaryDirectory: temporaryDirectory,
            repository: repository,
            isolateRoot: isolateRoot,
            selectedDirectory: selectedDirectory
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
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
