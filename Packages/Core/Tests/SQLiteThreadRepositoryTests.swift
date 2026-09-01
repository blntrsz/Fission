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
            workingDirectory: "/tmp/project",
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

    @Test func listsMostRecentlyUpdatedFirst() async throws {
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

        #expect(try await repository.list() == [newer, older])
    }
}
