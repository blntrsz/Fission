import FissionCore
import Foundation

/// Creates a desktop Thread, optionally in a Git worktree.
enum DesktopThreadCreator {
    @MainActor
    static func create(
        in model: ThreadListModel,
        title: String,
        workingDirectory: String,
        createWorktree: Bool
    ) async -> UUID? {
        let threadID = UUID()

        do {
            let resolvedWorkingDirectory = if createWorktree {
                try await makeWorktree(
                    from: workingDirectory,
                    threadTitle: title,
                    threadID: threadID
                )
            } else {
                workingDirectory
            }

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
        threadTitle: String,
        threadID: UUID
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try createSynchronously(
                from: workingDirectory,
                threadTitle: threadTitle,
                threadID: threadID
            )
        }.value
    }

    private static func createSynchronously(
        from workingDirectory: String,
        threadTitle: String,
        threadID: UUID
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
        let identifier = String(threadID.uuidString.lowercased().prefix(8))
        let slug = slug(for: threadTitle)
        let worktreeName = "\(repository.lastPathComponent)-\(slug)-\(identifier)"
        let worktree = repository.deletingLastPathComponent().appending(path: worktreeName)
        let branch = "fission/\(slug)-\(identifier)"

        _ = try runGit([
            "-C", repository.path,
            "worktree", "add", "-b", branch, worktree.path
        ])

        guard !relativePath.isEmpty else { return worktree.path }
        return worktree.appending(path: relativePath).path
    }

    private static func slug(for title: String) -> String {
        let normalized = title.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let slug = words.filter { !$0.isEmpty }.joined(separator: "-")
        return String((slug.isEmpty ? "thread" : slug).prefix(32))
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
