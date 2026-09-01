import Foundation

/// A long-lived workstream in which an agent performs related work.
public struct AgentThread: Identifiable, Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case active
        case settled
        case completed
        case failed
        case cancelled
    }

    public let id: UUID
    public private(set) var title: String
    public private(set) var status: Status
    public let workingDirectory: String?
    public let createdAt: Date
    public private(set) var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        status: Status = .active,
        workingDirectory: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public mutating func rename(to title: String, at date: Date = .now) {
        self.title = title
        updatedAt = date
    }

    public mutating func transition(to status: Status, at date: Date = .now) {
        self.status = status
        updatedAt = date
    }
}
