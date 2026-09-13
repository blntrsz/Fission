import Foundation
import Observation

/// JSON-backed registry of remote machines.
@MainActor
@Observable
public final class RemoteMachineStore {
    public static let overridePathKey = "FissionRemoteMachinesPath"

    public private(set) var machines: [RemoteMachine]
    private let fileURL: URL

    public static var applicationSupportFileURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: "fission-remote-machines.json")
    }

    public init(fileURL: URL? = nil) {
        let resolved = fileURL ?? Self.overrideFileURL() ?? Self.applicationSupportFileURL
        self.fileURL = resolved
        machines = Self.load(from: resolved)
    }

    public func upsert(_ machine: RemoteMachine) {
        guard machine.isValid else { return }
        var machine = machine
        machine.projectPath = RemoteMachine.normalizedProjectPath(machine.projectPath)
        if let index = machines.firstIndex(where: { $0.id == machine.id }) {
            machines[index] = machine
        } else {
            machines.append(machine)
        }
        persist()
    }

    public func remove(id: UUID) {
        machines.removeAll { $0.id == id }
        persist()
    }

    public func machine(id: UUID) -> RemoteMachine? {
        machines.first { $0.id == id }
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(machines) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func overrideFileURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: overridePathKey),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func load(from fileURL: URL) -> [RemoteMachine] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([RemoteMachine].self, from: data)) ?? []
    }
}
