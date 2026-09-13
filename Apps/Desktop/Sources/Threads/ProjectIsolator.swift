import Darwin
import Foundation

/// Copy-on-write project clones for isolated Threads.
enum ProjectIsolator {
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".fission/worktrees", directoryHint: .isDirectory)
    }

    static func create(
        from workingDirectory: String,
        isolateRoot: URL,
        requestedBranch: String? = nil,
        makeIdentifier: () -> String
    ) throws -> String {
        let selectedDirectory = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let sourceRoot = try resolvedSourceRoot(from: selectedDirectory)
        let relativePath = relativeSubpath(of: selectedDirectory, under: sourceRoot)
        let projectName = sourceRoot.lastPathComponent
        guard !projectName.isEmpty else {
            throw IsolateError.invalidProject
        }

        let repositoryIsolates = isolateRoot.appending(path: projectName, directoryHint: .isDirectory)
        let resolved = try resolveBranchAndIsolate(
            requestedBranch: requestedBranch,
            sourceRoot: sourceRoot,
            repositoryIsolates: repositoryIsolates,
            projectName: projectName,
            makeIdentifier: makeIdentifier
        )

        try FileManager.default.createDirectory(
            at: resolved.isolateDirectory,
            withIntermediateDirectories: true
        )
        do {
            try assertCopyOnWriteAvailable(from: sourceRoot, to: resolved.isolateDirectory)
            try cloneDirectory(from: sourceRoot, to: resolved.destination)
            try createBranchIfNeeded(at: resolved.destination, named: resolved.branch)
        } catch {
            try? FileManager.default.removeItem(at: resolved.isolateDirectory)
            throw error
        }

        guard !relativePath.isEmpty else { return resolved.destination.path }
        return resolved.destination.appending(path: relativePath).path
    }

    static func removeIsolate(workingDirectory: String?, isolateRoot: URL) throws {
        guard let isolateDirectory = isolateDirectory(
            for: workingDirectory,
            isolateRoot: isolateRoot
        ) else {
            return
        }
        try FileManager.default.removeItem(at: isolateDirectory)
    }

    static func isolateDirectory(for workingDirectory: String?, isolateRoot: URL) -> URL? {
        guard let workingDirectory else { return nil }
        let cwd = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let root = isolateRoot.standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard cwd.path.hasPrefix(prefix) else { return nil }

        let relative = String(cwd.path.dropFirst(prefix.count))
        let parts = relative.split(separator: "/").map(String.init)
        guard let project = parts.first,
              let leafIndex = parts.dropFirst().firstIndex(of: project) else {
            return nil
        }
        return parts[0..<leafIndex].reduce(root) { directory, component in
            directory.appending(path: component, directoryHint: .isDirectory)
        }
    }

    private static func resolveBranchAndIsolate(
        requestedBranch: String?,
        sourceRoot: URL,
        repositoryIsolates: URL,
        projectName: String,
        makeIdentifier: () -> String
    ) throws -> (branch: String, isolateDirectory: URL, destination: URL) {
        if let requestedBranch {
            guard GitWorktreeBranch.isValid(requestedBranch) else {
                throw IsolateError.invalidBranchName
            }
            let isolateDirectory = repositoryIsolates.appending(
                path: requestedBranch,
                directoryHint: .isDirectory
            )
            if FileManager.default.fileExists(atPath: isolateDirectory.path) {
                throw IsolateError.isolateExists(requestedBranch)
            }
            if sourceHasGitBranch(named: requestedBranch, at: sourceRoot) {
                throw IsolateError.branchAlreadyExists(requestedBranch)
            }
            return (
                requestedBranch,
                isolateDirectory,
                isolateDirectory.appending(path: projectName, directoryHint: .isDirectory)
            )
        }

        var branch = ""
        var isolateDirectory = repositoryIsolates
        repeat {
            branch = "fission-\(makeIdentifier())"
            isolateDirectory = repositoryIsolates
                .appending(path: branch, directoryHint: .isDirectory)
        } while FileManager.default.fileExists(atPath: isolateDirectory.path)
            || sourceHasGitBranch(named: branch, at: sourceRoot)
        return (
            branch,
            isolateDirectory,
            isolateDirectory.appending(path: projectName, directoryHint: .isDirectory)
        )
    }

    private static func resolvedSourceRoot(from selectedDirectory: URL) throws -> URL {
        if let repository = gitToplevel(at: selectedDirectory) {
            let git = repository.appending(path: ".git")
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory) else {
                throw IsolateError.invalidGitLayout
            }
            guard isDirectory.boolValue else {
                throw IsolateError.linkedWorktree
            }
            return repository
        }
        return selectedDirectory
    }

    private static func relativeSubpath(of selectedDirectory: URL, under sourceRoot: URL) -> String {
        selectedDirectory.path
            .dropFirst(sourceRoot.path.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func gitToplevel(at directory: URL) -> URL? {
        guard let path = try? runGit([
            "-C", directory.path,
            "rev-parse", "--show-toplevel"
        ]) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    private static func sourceHasGitBranch(named branch: String, at sourceRoot: URL) -> Bool {
        guard let listed = try? runGit([
            "-C", sourceRoot.path,
            "branch", "--list", "--", branch
        ]) else {
            return false
        }
        return !listed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func createBranchIfNeeded(at destination: URL, named branch: String) throws {
        let git = destination.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }
        guard let head = try? runGit([
            "-C", destination.path,
            "rev-parse", "--verify", "HEAD"
        ]), !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        _ = try runGit(["-C", destination.path, "switch", "-c", branch])
    }

    private static func assertCopyOnWriteAvailable(from source: URL, to destinationParent: URL) throws {
        guard isAPFS(source), isAPFS(destinationParent) else {
            throw IsolateError.copyOnWriteUnavailable
        }
        guard let sourceDevice = deviceID(of: source),
              let destinationDevice = deviceID(of: destinationParent),
              sourceDevice == destinationDevice else {
            throw IsolateError.copyOnWriteUnavailable
        }
        try probeClonefile(from: source, to: destinationParent)
    }

    private static func probeClonefile(from source: URL, to destinationParent: URL) throws {
        guard let probeSource = firstRegularFile(in: source) else { return }
        let probeDestination = destinationParent.appending(path: ".fission-cow-probe")
        try cloneFile(from: probeSource, to: probeDestination)
        try FileManager.default.removeItem(at: probeDestination)
    }

    private static func firstRegularFile(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        while let file = enumerator.nextObject() as? URL {
            let isRegular = (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isRegular { return file }
        }
        return nil
    }

    private static func cloneDirectory(from source: URL, to destination: URL) throws {
        let status = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                copyfile(
                    sourcePath,
                    destinationPath,
                    nil,
                    copyfile_flags_t(COPYFILE_CLONE | COPYFILE_RECURSIVE)
                )
            }
        }
        guard status == 0 else {
            throw IsolateError.cloneFailed(errno)
        }
    }

    private static func cloneFile(from source: URL, to destination: URL) throws {
        let status = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                clonefile(sourcePath, destinationPath, 0)
            }
        }
        guard status == 0 else {
            throw IsolateError.copyOnWriteUnavailable
        }
    }

    private static func isAPFS(_ url: URL) -> Bool {
        var filesystem = statfs()
        guard statfs(url.path, &filesystem) == 0 else { return false }
        return withUnsafeBytes(of: filesystem.f_fstypename) { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return false
            }
            return String(cString: base) == "apfs"
        }
    }

    private static func deviceID(of url: URL) -> dev_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_dev
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
            throw IsolateError.gitUnavailable
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = (String(bytes: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw IsolateError.commandFailed(message)
        }
        return message
    }
}

enum IsolateError: LocalizedError {
    case invalidProject
    case invalidGitLayout
    case linkedWorktree
    case invalidBranchName
    case branchAlreadyExists(String)
    case isolateExists(String)
    case copyOnWriteUnavailable
    case cloneFailed(Int32)
    case gitUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProject:
            "The selected project folder is invalid."
        case .invalidGitLayout:
            "The selected Git repository could not be read."
        case .linkedWorktree:
            "Linked Git worktrees cannot be isolated. Choose the main repository folder."
        case .invalidBranchName:
            "Enter a valid Git branch name."
        case let .branchAlreadyExists(branch):
            "A branch named \"\(branch)\" already exists."
        case let .isolateExists(branch):
            "An isolated workspace for \"\(branch)\" already exists."
        case .copyOnWriteUnavailable:
            "The project must be on APFS on the same volume as ~/.fission/worktrees."
        case .cloneFailed:
            "The project folder could not be copied."
        case .gitUnavailable:
            "Git could not be started."
        case let .commandFailed(message):
            message.isEmpty ? "Git could not prepare the isolated workspace." : message
        }
    }
}
