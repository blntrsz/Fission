import FissionCore
import Foundation

/// Creates a desktop Thread, optionally in a Git worktree.
enum DesktopThreadCreator {
    @MainActor
    static func create(
        in model: ThreadListModel,
        workingDirectory: String,
        createWorktree: Bool,
        worktreeBranch: String? = nil
    ) async -> UUID? {
        await create(
            in: model,
            workingDirectory: workingDirectory,
            createWorktree: createWorktree,
            worktreeRoot: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".fission/worktrees", directoryHint: .isDirectory),
            worktreeBranch: worktreeBranch,
            makeIdentifier: randomIdentifier
        )
    }

    @MainActor
    static func create(
        in model: ThreadListModel,
        workingDirectory: String,
        createWorktree: Bool,
        worktreeRoot: URL,
        worktreeBranch: String? = nil,
        makeIdentifier: @escaping @Sendable () -> String
    ) async -> UUID? {
        let threadID = UUID()
        let selectedDirectory = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let projectName = selectedDirectory.lastPathComponent

        do {
            let resolvedWorkingDirectory = if createWorktree {
                try await makeWorktree(
                    from: workingDirectory,
                    worktreeRoot: worktreeRoot,
                    requestedBranch: GitWorktreeBranch.normalized(worktreeBranch),
                    makeIdentifier: makeIdentifier
                )
            } else {
                workingDirectory
            }

            let title = GitBranchResolver.currentBranch(at: resolvedWorkingDirectory) ?? "local"
            return await model.createThread(
                id: threadID,
                title: title,
                workingDirectory: resolvedWorkingDirectory,
                projectName: projectName.isEmpty ? nil : projectName
            )
        } catch {
            model.errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    static func createRemote(
        in model: ThreadListModel,
        machine: RemoteMachine,
        projectPath: String
    ) async -> UUID? {
        guard machine.isValid else {
            model.errorMessage = "The remote machine needs a host."
            return nil
        }

        guard let directory = RemoteMachine.normalizedProjectPath(projectPath) else {
            model.errorMessage = "The remote Thread needs a project path."
            return nil
        }

        return await model.createThread(
            title: machine.target,
            workingDirectory: directory,
            projectName: RemoteMachine.projectName(from: directory) ?? machine.displayName,
            remoteMachineID: machine.id,
            remoteCommand: MoshCommand.loginShellCommand(
                target: machine.target,
                sshPort: machine.sshPort,
                remoteDirectory: directory
            )
        )
    }

    private static func makeWorktree(
        from workingDirectory: String,
        worktreeRoot: URL,
        requestedBranch: String?,
        makeIdentifier: @escaping @Sendable () -> String
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try createSynchronously(
                from: workingDirectory,
                worktreeRoot: worktreeRoot,
                requestedBranch: requestedBranch,
                makeIdentifier: makeIdentifier
            )
        }.value
    }

    private static func createSynchronously(
        from workingDirectory: String,
        worktreeRoot: URL,
        requestedBranch: String?,
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
        let branchAndPath = try resolveBranchAndWorktree(
            requestedBranch: requestedBranch,
            repository: repository,
            repositoryWorktrees: repositoryWorktrees,
            makeIdentifier: makeIdentifier
        )

        try FileManager.default.createDirectory(
            at: repositoryWorktrees,
            withIntermediateDirectories: true
        )
        _ = try runGit([
            "-C", repository.path,
            "worktree", "add", "-b", branchAndPath.branch, branchAndPath.worktree.path
        ])

        guard !relativePath.isEmpty else { return branchAndPath.worktree.path }
        return branchAndPath.worktree.appending(path: relativePath).path
    }

    private static func resolveBranchAndWorktree(
        requestedBranch: String?,
        repository: URL,
        repositoryWorktrees: URL,
        makeIdentifier: () -> String
    ) throws -> (branch: String, worktree: URL) {
        if let requestedBranch {
            guard GitWorktreeBranch.isValid(requestedBranch) else {
                throw GitWorktreeError.invalidBranchName
            }
            let worktree = repositoryWorktrees.appending(
                path: requestedBranch,
                directoryHint: .isDirectory
            )
            if FileManager.default.fileExists(atPath: worktree.path) {
                throw GitWorktreeError.worktreeExists(requestedBranch)
            }
            if try branchExists(requestedBranch, in: repository) {
                throw GitWorktreeError.branchAlreadyExists(requestedBranch)
            }
            return (requestedBranch, worktree)
        }

        var branch = ""
        var worktree = repositoryWorktrees
        repeat {
            branch = "fission-\(makeIdentifier())"
            worktree = repositoryWorktrees
                .appending(path: branch, directoryHint: .isDirectory)
        } while try FileManager.default.fileExists(atPath: worktree.path)
            || branchExists(branch, in: repository)
        return (branch, worktree)
    }

    private static func branchExists(_ branch: String, in repository: URL) throws -> Bool {
        !(try runGit([
            "-C", repository.path,
            "branch", "--list", "--", branch
        ])).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

enum GitWorktreeBranch {
    static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name != "@" else { return false }
        if name.hasPrefix("/") || name.hasSuffix("/") || name.hasPrefix("-") {
            return false
        }
        if name.contains("..") || name.contains("//") || name.contains("@{") {
            return false
        }
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\")
            .union(.controlCharacters)
            .union(.newlines)
        if name.unicodeScalars.contains(where: { forbidden.contains($0) }) {
            return false
        }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty
                && !component.hasPrefix(".")
                && !component.hasSuffix(".")
                && !component.hasSuffix(".lock")
        }
    }
}

private enum GitWorktreeError: LocalizedError {
    case gitUnavailable
    case notGitRepository
    case invalidBranchName
    case branchAlreadyExists(String)
    case worktreeExists(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "Git could not be started."
        case .notGitRepository:
            "The selected project folder is not inside a Git repository."
        case .invalidBranchName:
            "Enter a valid Git branch name."
        case let .branchAlreadyExists(branch):
            "A branch named \"\(branch)\" already exists."
        case let .worktreeExists(branch):
            "A worktree for \"\(branch)\" already exists."
        case let .commandFailed(message):
            message.isEmpty ? "Git could not create the worktree." : message
        }
    }
}