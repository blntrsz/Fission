import Foundation

/// Persistence required by Thread use cases.
public protocol ThreadRepository: Sendable {
    func create(_ thread: AgentThread) async throws
    func thread(id: UUID) async throws -> AgentThread?

    /// Returns all Threads ordered from most recently updated to least recently updated.
    func list() async throws -> [AgentThread]

    func update(_ thread: AgentThread) async throws
    func delete(id: UUID) async throws
}
