import Foundation
import Testing
@testable import FissionCore

struct SQLiteThreadRepositoryTests {
    @Test func performsThreadCRUD() async throws {
        let repository = try SQLiteThreadRepository(path: ":memory:")
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        var thread = AgentThread(
            title: "Initial title",
            workingDirectory: "/tmp/worktrees/project/branch",
            projectName: "project",
            remoteMachineID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            remoteCommand: "exec mosh ada@gpu.local",
            createdAt: createdAt
        )

        try await repository.create(thread)

        let fetched = try await repository.thread(id: thread.id)
        #expect(fetched == thread)
        #expect(try await repository.list() == [thread])

        thread.rename(to: "Updated title", at: updatedAt)
        try await repository.update(thread)
        #expect(try await repository.thread(id: thread.id) == thread)

        try await repository.delete(id: thread.id)
        #expect(try await repository.thread(id: thread.id) == nil)
        #expect(try await repository.list().isEmpty)
    }

    @Test func listsNewlyCreatedThreadsFirst() async throws {
        let repository = try SQLiteThreadRepository(path: ":memory:")
        let older = AgentThread(
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = AgentThread(
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        try await repository.create(older)
        try await repository.create(newer)

        #expect(try await repository.list().map(\.title) == ["Newer", "Older"])
    }

    @Test func reorderPersistsManualOrderWithoutChangingUpdatedAt() async throws {
        let repository = try SQLiteThreadRepository(path: ":memory:")
        let first = AgentThread(title: "First")
        let second = AgentThread(title: "Second")
        let third = AgentThread(title: "Third")
        try await repository.create(first)
        try await repository.create(second)
        try await repository.create(third)

        let created = try await repository.list()
        #expect(created.map(\.title) == ["Third", "Second", "First"])
        let thirdUpdatedAt = try #require(created.first?.updatedAt)

        try await repository.reorder(ids: [first.id, third.id, second.id])

        let reordered = try await repository.list()
        #expect(reordered.map(\.id) == [first.id, third.id, second.id])
        #expect(reordered.first { $0.id == third.id }?.updatedAt == thirdUpdatedAt)
    }

    @Test func renameDoesNotChangeSortOrder() async throws {
        let repository = try SQLiteThreadRepository(path: ":memory:")
        let first = AgentThread(
            title: "First",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = AgentThread(
            title: "Second",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        try await repository.create(first)
        try await repository.create(second)

        var storedFirst = try #require(try await repository.thread(id: first.id))
        storedFirst.rename(to: "Renamed", at: Date(timeIntervalSince1970: 3_000))
        try await repository.update(storedFirst)

        #expect(try await repository.list().map(\.id) == [second.id, first.id])
        #expect(try await repository.thread(id: first.id)?.title == "Renamed")
    }
}
