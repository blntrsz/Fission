import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

@MainActor
struct DesktopRemoteThreadTests {
    @Test func createRemotePersistsMoshCommandWithoutWorktree() async throws {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let machine = RemoteMachine(
            name: "Studio",
            username: "ada",
            host: "gpu.local",
            sshPort: 2_222
        )

        let threadID = await DesktopThreadCreator.createRemote(in: model, machine: machine)
        let thread = try #require(model.threads.first { $0.id == threadID })

        #expect(thread.projectName == "Studio")
        #expect(thread.title == "ada@gpu.local")
        #expect(thread.isRemote)
        #expect(thread.workingDirectory == nil)
        #expect(thread.remoteMachineID == machine.id)
        #expect(thread.remoteCommand == #"exec mosh --ssh='ssh -p 2222' ada@gpu.local"#)
    }

    @Test func rejectsMachinesWithoutAHost() async {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let count = model.threads.count

        let threadID = await DesktopThreadCreator.createRemote(
            in: model,
            machine: RemoteMachine(name: "Missing", username: "ada", host: " ")
        )

        #expect(threadID == nil)
        #expect(model.threads.count == count)
        #expect(model.errorMessage == "The remote machine needs a host.")
    }
}
