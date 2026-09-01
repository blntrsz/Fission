import Foundation
import Testing
@testable import FissionCore

struct AgentThreadTests {
    @Test func startsActive() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let thread = AgentThread(title: "Research Swift concurrency", createdAt: createdAt)

        #expect(thread.title == "Research Swift concurrency")
        #expect(thread.status == .active)
        #expect(thread.createdAt == createdAt)
        #expect(thread.updatedAt == createdAt)
    }

    @Test func settlesAndReopens() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let settledAt = Date(timeIntervalSince1970: 2_000)
        let reopenedAt = Date(timeIntervalSince1970: 3_000)
        var thread = AgentThread(title: "Research", createdAt: createdAt)

        thread.transition(to: .settled, at: settledAt)
        #expect(thread.status == .settled)
        #expect(thread.updatedAt == settledAt)

        thread.transition(to: .active, at: reopenedAt)
        #expect(thread.status == .active)
        #expect(thread.updatedAt == reopenedAt)
    }

    @Test func tracksChanges() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let renamedAt = Date(timeIntervalSince1970: 2_000)
        let completedAt = Date(timeIntervalSince1970: 3_000)
        var thread = AgentThread(title: "Research", createdAt: createdAt)

        thread.rename(to: "Research Swift concurrency", at: renamedAt)
        #expect(thread.title == "Research Swift concurrency")
        #expect(thread.updatedAt == renamedAt)

        thread.transition(to: .completed, at: completedAt)
        #expect(thread.status == .completed)
        #expect(thread.updatedAt == completedAt)
    }
}
