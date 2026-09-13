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

        let threadID = await DesktopThreadCreator.createRemote(
            in: model,
            machine: machine,
            projectPath: "/work/fission/"
        )
        let thread = try #require(model.threads.first { $0.id == threadID })

        #expect(thread.projectName == "fission")
        #expect(thread.title == "ada@gpu.local")
        #expect(thread.isRemote)
        #expect(thread.workingDirectory == "/work/fission")
        #expect(thread.remoteMachineID == machine.id)
        #expect(
            thread.remoteCommand
                == #"exec mosh --ssh='ssh -p 2222' ada@gpu.local -- sh -lc 'cd -- "/work/fission" && exec "${SHELL:-/bin/sh}" -l'"#
        )
    }

    @Test func rejectsRemoteThreadsWithoutAProjectPath() async {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let count = model.threads.count
        let machine = RemoteMachine(name: "Studio", username: "ada", host: "gpu.local")

        let threadID = await DesktopThreadCreator.createRemote(
            in: model,
            machine: machine,
            projectPath: "   "
        )

        #expect(threadID == nil)
        #expect(model.threads.count == count)
        #expect(model.errorMessage == "The remote Thread needs a project path.")
    }

    @Test func rejectsMachinesWithoutAHost() async {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let count = model.threads.count

        let threadID = await DesktopThreadCreator.createRemote(
            in: model,
            machine: RemoteMachine(name: "Missing", username: "ada", host: " "),
            projectPath: "/work/fission"
        )

        #expect(threadID == nil)
        #expect(model.threads.count == count)
        #expect(model.errorMessage == "The remote machine needs a host.")
    }
}
