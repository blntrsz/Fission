import FissionCore
import Foundation

protocol RemoteDirectoryCatalog: Sendable {
    func listing(on machine: RemoteMachine, in directory: String) async -> RemoteDirectoryListing
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

    func listing(on machine: RemoteMachine, in directory: String) async -> RemoteDirectoryListing {
        let key = ProjectPathQuery.stripTrailingSlashes(directory)
        if let names = directories[key] ?? directories[directory] {
            return .contents(names)
        }
        return .missing
    }
}

struct SSHRemoteDirectoryCatalog: RemoteDirectoryCatalog {
    func listing(on machine: RemoteMachine, in directory: String) async -> RemoteDirectoryListing {
        await Task.detached(priority: .userInitiated) {
            Self.listSynchronously(machine: machine, directory: directory)
        }.value
    }

    static func listSynchronously(
        machine: RemoteMachine,
        directory: String
    ) -> RemoteDirectoryListing {
        guard machine.isValid else { return .failed }

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
            return .failed
        }

        if group.wait(timeout: .now() + 6) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            return .failed
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return SSHDirectoryListing.result(
            status: process.terminationStatus,
            output: String(bytes: data, encoding: .utf8) ?? ""
        )
    }
}
