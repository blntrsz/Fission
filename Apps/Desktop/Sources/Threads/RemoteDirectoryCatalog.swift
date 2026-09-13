import FissionCore
import Foundation

protocol RemoteDirectoryCatalog: Sendable {
    func childDirectories(on machine: RemoteMachine, in directory: String) async -> [String]
}

enum RemoteDirectoryCatalogs {
    static func make() -> any RemoteDirectoryCatalog {
        if let json = ProcessInfo.processInfo.environment["FISSION_REMOTE_DIRECTORY_LISTING"],
           let directories = SSHDirectoryListing.parseFixtureJSON(json) {
            return MapRemoteDirectoryCatalog(directories: directories)
        }
        return SSHRemoteDirectoryCatalog()
    }
}

struct MapRemoteDirectoryCatalog: RemoteDirectoryCatalog {
    let directories: [String: [String]]

    func childDirectories(on machine: RemoteMachine, in directory: String) async -> [String] {
        let key = ProjectPathQuery.stripTrailingSlashes(directory)
        return directories[key] ?? directories[directory] ?? []
    }
}

struct SSHRemoteDirectoryCatalog: RemoteDirectoryCatalog {
    func childDirectories(on machine: RemoteMachine, in directory: String) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            Self.listSynchronously(machine: machine, directory: directory)
        }.value
    }

    static func listSynchronously(machine: RemoteMachine, directory: String) -> [String] {
        guard machine.isValid else { return [] }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = SSHDirectoryListing.processArguments(
            machine: machine,
            directory: directory
        )
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let group = DispatchGroup()
        process.terminationHandler = { _ in group.leave() }
        group.enter()

        do {
            try process.run()
        } catch {
            group.leave()
            return []
        }

        if group.wait(timeout: .now() + 6) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return [] }
        return SSHDirectoryListing.parseOutput(String(bytes: data, encoding: .utf8) ?? "")
    }
}
