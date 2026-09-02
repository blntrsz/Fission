@testable import FissionCore
import Foundation
import Testing

@MainActor
struct ThreadListModelTests {
    @Test func bootstrapsAnEmptyDatabaseOnce() async {
        let model = ThreadListModel(databasePath: ":memory:")

        await model.load()
        let bootstrappedThreads = model.threads
        await model.load()

        #expect(model.errorMessage == nil)
        #expect(bootstrappedThreads.count == 1)
        #expect(bootstrappedThreads.first?.title == "Explore Fission")
        #expect(model.threads == bootstrappedThreads)
    }

    @Test func retriesLoadingAfterFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let database = directory.appending(path: "fission.sqlite")
        let model = ThreadListModel(databasePath: database.path)
        defer { try? FileManager.default.removeItem(at: directory) }

        await model.load()
        #expect(model.errorMessage != nil)
        #expect(model.threads.isEmpty)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        await model.load()

        #expect(model.errorMessage == nil)
        #expect(model.threads.count == 1)
    }

    @Test func createsTrimmedThreadsWithOptionalWorkingDirectories() async {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()

        let expectedID = UUID()
        let threadID = await model.createThread(
            id: expectedID,
            title: "  Ship Fission  ",
            workingDirectory: "/tmp/fission"
        )
        let thread = model.threads.first { $0.id == threadID }

        #expect(threadID == expectedID)
        #expect(thread?.title == "Ship Fission")
        #expect(thread?.workingDirectory == "/tmp/fission")

        let count = model.threads.count
        #expect(await model.createThread(title: " \n ") == nil)
        #expect(model.threads.count == count)
    }

    @Test func renamesThreadsWithTrimmedNonemptyTitles() async throws {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let threadID = try #require(await model.createThread(title: "Original"))

        await model.rename(threadID: threadID, to: "  Renamed Thread  ")
        #expect(model.threads.first { $0.id == threadID }?.title == "Renamed Thread")

        await model.rename(threadID: threadID, to: " \n ")
        #expect(model.threads.first { $0.id == threadID }?.title == "Renamed Thread")
        #expect(model.errorMessage == nil)
    }

    @Test func settlesReopensAndOrdersByLatestChange() async throws {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let firstID = try #require(await model.createThread(title: "First"))
        try await Task.sleep(for: .milliseconds(10))
        _ = await model.createThread(title: "Second")
        try await Task.sleep(for: .milliseconds(10))

        await model.settle(threadID: firstID)

        #expect(model.threads.first?.id == firstID)
        #expect(model.threads.first?.isSettled == true)

        await model.reopen(threadID: firstID)
        #expect(model.threads.first { $0.id == firstID }?.isSettled == false)
    }

    @Test func deletesThreadsAndRefreshesState() async throws {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let firstID = try #require(await model.createThread(title: "First"))
        let secondID = try #require(await model.createThread(title: "Second"))

        await model.deleteThreads(ids: [firstID, secondID])

        #expect(!model.threads.contains { $0.id == firstID })
        #expect(!model.threads.contains { $0.id == secondID })
        #expect(model.errorMessage == nil)
    }
}
