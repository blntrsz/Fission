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
    public let projectName: String?
    public let remoteMachineID: UUID?
    public let remoteCommand: String?
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var sortIndex: Int

    public var isSettled: Bool { status == .settled }
    public var isRemote: Bool { remoteCommand != nil || remoteMachineID != nil }

    public init(
        id: UUID = UUID(),
        title: String,
        status: Status = .active,
        workingDirectory: String? = nil,
        projectName: String? = nil,
        remoteMachineID: UUID? = nil,
        remoteCommand: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.workingDirectory = workingDirectory
        self.projectName = projectName
        self.remoteMachineID = remoteMachineID
        self.remoteCommand = remoteCommand
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.sortIndex = sortIndex
    }

    public mutating func rename(to title: String, at date: Date = .now) {
        self.title = title
        updatedAt = date
    }

    public mutating func transition(to status: Status, at date: Date = .now) {
        self.status = status
        updatedAt = date
    }

    public mutating func place(at sortIndex: Int) {
        self.sortIndex = sortIndex
    }
}
