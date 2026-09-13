import FissionCore
import Foundation

/// Creates a desktop Thread, optionally in a copy-on-write isolate.
enum DesktopThreadCreator {
    @MainActor
    static func create(
        in model: ThreadListModel,
        workingDirectory: String,
        createIsolate: Bool,
        isolateBranch: String? = nil
    ) async -> UUID? {
        await create(
            in: model,
            workingDirectory: workingDirectory,
            createIsolate: createIsolate,
            isolateRoot: ProjectIsolator.defaultRoot,
            isolateBranch: isolateBranch,
            makeIdentifier: randomIdentifier
        )
    }

    @MainActor
    static func create(
        in model: ThreadListModel,
        workingDirectory: String,
        createIsolate: Bool,
        isolateRoot: URL,
        isolateBranch: String? = nil,
        makeIdentifier: @escaping @Sendable () -> String
    ) async -> UUID? {
        let threadID = UUID()
        let selectedDirectory = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let projectName = selectedDirectory.lastPathComponent

        do {
            let resolvedWorkingDirectory = if createIsolate {
                try await makeIsolate(
                    from: workingDirectory,
                    isolateRoot: isolateRoot,
                    requestedBranch: GitWorktreeBranch.normalized(isolateBranch),
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

    private static func makeIsolate(
        from workingDirectory: String,
        isolateRoot: URL,
        requestedBranch: String?,
        makeIdentifier: @escaping @Sendable () -> String
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try ProjectIsolator.create(
                from: workingDirectory,
                isolateRoot: isolateRoot,
                requestedBranch: requestedBranch,
                makeIdentifier: makeIdentifier
            )
        }.value
    }

    private static func randomIdentifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
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
