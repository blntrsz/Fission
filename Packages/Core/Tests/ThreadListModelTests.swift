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
            workingDirectory: "/tmp/fission-worktrees/branch",
            projectName: "Fission"
        )
        let thread = model.threads.first { $0.id == threadID }

        #expect(threadID == expectedID)
        #expect(thread?.title == "Ship Fission")
        #expect(thread?.workingDirectory == "/tmp/fission-worktrees/branch")
        #expect(thread?.projectName == "Fission")

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

    @Test func settlesReopensAndPreservesManualOrder() async throws {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let firstID = try #require(await model.createThread(title: "First"))
        try await Task.sleep(for: .milliseconds(10))
        let secondID = try #require(await model.createThread(title: "Second"))
        try await Task.sleep(for: .milliseconds(10))

        await model.settle(threadID: firstID)

        #expect(model.threads.first { $0.id == firstID }?.isSettled == true)
        #expect(model.threads.filter { !$0.isSettled }.map(\.id).first == secondID)

        await model.reopen(threadID: firstID)
        #expect(model.threads.first { $0.id == firstID }?.isSettled == false)
        #expect(model.threads.filter { !$0.isSettled }.map(\.id) == [secondID, firstID])
    }

    @Test func reordersActiveThreadsAndKeepsNewThreadsFirst() async throws {
        let model = ThreadListModel(databasePath: ":memory:")
        await model.load()
        let exploreID = try #require(model.threads.first?.id)
        let firstID = try #require(await model.createThread(title: "First"))
        let secondID = try #require(await model.createThread(title: "Second"))

        #expect(model.threads.map(\.id) == [secondID, firstID, exploreID])

        await model.reorderActiveThreads(ids: [exploreID, secondID, firstID])
        #expect(model.threads.map(\.id) == [exploreID, secondID, firstID])
        #expect(model.errorMessage == nil)

        let thirdID = try #require(await model.createThread(title: "Third"))
        #expect(model.threads.map(\.id) == [thirdID, exploreID, secondID, firstID])

        await model.rename(threadID: thirdID, to: "Third renamed")
        #expect(model.threads.map(\.id) == [thirdID, exploreID, secondID, firstID])
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
