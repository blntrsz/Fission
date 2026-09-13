import Foundation
import Testing
@testable import FissionCore

struct RemoteMachineTests {
    @Test func buildsMoshLoginCommandForDefaultPort() {
        let machine = RemoteMachine(name: "Studio", username: "ada", host: "gpu.local")

        #expect(machine.target == "ada@gpu.local")
        #expect(machine.moshCommand == "exec mosh ada@gpu.local")
        #expect(machine.isValid)
        #expect(machine.isRemoteThreadReady)
    }

    @Test func quotesCustomSSHPortAndUnsafeHosts() {
        let command = MoshCommand.loginShellCommand(
            target: "ada@host'box",
            sshPort: 2_222
        )

        #expect(command == "exec mosh --ssh='ssh -p 2222' 'ada@host'\\''box'")
    }

    @Test func rejectsEmptyHostsAndOutOfRangePorts() {
        #expect(!RemoteMachine(name: "x", username: "ada", host: "  ").isValid)
        #expect(!RemoteMachine(name: "x", username: "ada", host: "gpu", sshPort: 0).isValid)
    }
}

private extension RemoteMachine {
    var isRemoteThreadReady: Bool { isValid && !moshCommand.isEmpty }
}

struct RemoteMachineStoreTests {
    @MainActor
    @Test func upsertsAndRemovesMachines() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = RemoteMachineStore(fileURL: fileURL)
        let machine = RemoteMachine(name: "Studio", username: "ada", host: "gpu.local")

        store.upsert(machine)
        #expect(store.machines == [machine])

        var renamed = machine
        renamed.name = "Render"
        store.upsert(renamed)
        #expect(store.machines == [renamed])
        #expect(RemoteMachineStore(fileURL: fileURL).machines == [renamed])

        store.remove(id: machine.id)
        #expect(store.machines.isEmpty)
    }
}
