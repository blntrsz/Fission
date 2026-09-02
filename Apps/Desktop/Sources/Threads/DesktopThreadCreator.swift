import FissionCore
import Foundation

/// Creates a desktop Thread, optionally in a Git worktree.
enum DesktopThreadCreator {
    @MainActor
    static func create(
        in model: ThreadListModel,
        workingDirectory: String,
        createWorktree: Bool
    ) async -> UUID? {
        await create(
            in: model,
            workingDirectory: workingDirectory,
            createWorktree: createWorktree,
            worktreeRoot: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".fission/worktrees", directoryHint: .isDirectory),
            makeIdentifier: randomIdentifier
        )
    }

    @MainActor
    static func create(
        in model: ThreadListModel,
        workingDirectory: String,
        createWorktree: Bool,
        worktreeRoot: URL,
        makeIdentifier: @escaping @Sendable () -> String
    ) async -> UUID? {
        let threadID = UUID()

        do {
            let resolvedWorkingDirectory = if createWorktree {
                try await makeWorktree(
                    from: workingDirectory,
                    worktreeRoot: worktreeRoot,
                    makeIdentifier: makeIdentifier
                )
            } else {
                workingDirectory
            }

            let title = GitBranchResolver.currentBranch(at: resolvedWorkingDirectory) ?? "local"
            return await model.createThread(
                id: threadID,
                title: title,
                workingDirectory: resolvedWorkingDirectory
            )
        } catch {
            model.errorMessage = error.localizedDescription
            return nil
        }
    }

    private static func makeWorktree(
        from workingDirectory: String,
        worktreeRoot: URL,
        makeIdentifier: @escaping @Sendable () -> String
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try createSynchronously(
                from: workingDirectory,
                worktreeRoot: worktreeRoot,
                makeIdentifier: makeIdentifier
            )
        }.value
    }

    private static func createSynchronously(
        from workingDirectory: String,
        worktreeRoot: URL,
        makeIdentifier: () -> String
    ) throws -> String {
        let selectedDirectory = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let repositoryPath = try runGit([
            "-C", selectedDirectory.path,
            "rev-parse", "--show-toplevel"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryPath.isEmpty else {
            throw GitWorktreeError.notGitRepository
        }

        let repository = URL(fileURLWithPath: repositoryPath).standardizedFileURL
        let relativePath = selectedDirectory.path
            .dropFirst(repository.path.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let repositoryWorktrees = worktreeRoot
            .appending(path: repository.lastPathComponent, directoryHint: .isDirectory)
        var branch = ""
        var worktree = repositoryWorktrees
        repeat {
            branch = "fission-\(makeIdentifier())"
            worktree = repositoryWorktrees
                .appending(path: branch, directoryHint: .isDirectory)
        } while try FileManager.default.fileExists(atPath: worktree.path)
            || !(runGit([
                "-C", repository.path,
                "branch", "--list", branch
            ])).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        try FileManager.default.createDirectory(
            at: repositoryWorktrees,
            withIntermediateDirectories: true
        )
        _ = try runGit([
            "-C", repository.path,
            "worktree", "add", "-b", branch, worktree.path
        ])

        guard !relativePath.isEmpty else { return worktree.path }
        return worktree.appending(path: relativePath).path
    }

    private static func randomIdentifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }

    private static func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw GitWorktreeError.gitUnavailable
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = (String(bytes: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            if arguments.contains("rev-parse") {
                throw GitWorktreeError.notGitRepository
            }
            throw GitWorktreeError.commandFailed(message)
        }
        return message
    }
}

private enum GitWorktreeError: LocalizedError {
    case gitUnavailable
    case notGitRepository
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "Git could not be started."
        case .notGitRepository:
            "The selected project folder is not inside a Git repository."
        case let .commandFailed(message):
            message.isEmpty ? "Git could not create the worktree." : message
        }
    }
}
