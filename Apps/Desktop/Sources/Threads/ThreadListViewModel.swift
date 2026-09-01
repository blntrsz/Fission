import FissionCore
import Foundation
import Observation

@MainActor
@Observable
final class ThreadListViewModel {
    private(set) var threads: [AgentThread] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private var repository: SQLiteThreadRepository?

    func load() async {
        guard repository == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = try SQLiteThreadRepository(path: Self.databaseURL.path)
            self.repository = repository

            if try await repository.list().isEmpty {
                try await repository.create(
                    AgentThread(title: "Explore Fission")
                )
            }
            threads = try await repository.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createThread(
        title: String,
        workingDirectory: String,
        createWorktree: Bool
    ) async -> UUID? {
        guard let repository else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let threadID = UUID()
        do {
            let resolvedWorkingDirectory = if createWorktree {
                try await GitWorktreeCreator.create(
                    from: workingDirectory,
                    threadTitle: trimmedTitle,
                    threadID: threadID
                )
            } else {
                workingDirectory
            }
            let thread = AgentThread(
                id: threadID,
                title: trimmedTitle,
                workingDirectory: resolvedWorkingDirectory
            )
            try await repository.create(thread)
            threads = try await repository.list()
            return thread.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func settle(threadID: UUID) async {
        await transition(threadID: threadID, to: .settled)
    }

    func reopen(threadID: UUID) async {
        await transition(threadID: threadID, to: .active)
    }

    func deleteThreads(ids: [UUID]) async {
        guard let repository else { return }

        do {
            for id in ids {
                try await repository.delete(id: id)
            }
            threads = try await repository.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transition(threadID: UUID, to status: AgentThread.Status) async {
        guard let repository,
              var thread = threads.first(where: { $0.id == threadID }) else {
            return
        }

        thread.transition(to: status)
        do {
            try await repository.update(thread)
            threads = try await repository.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var databaseURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: "fission.sqlite")
    }
}

private enum GitWorktreeCreator {
    static func create(
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
        let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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
