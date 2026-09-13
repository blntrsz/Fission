import Foundation

/// A registered host that Desktop can open as a remote Thread over mosh.
public struct RemoteMachine: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var username: String
    public var host: String
    public var sshPort: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        host: String,
        sshPort: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.host = host
        self.sshPort = sshPort
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? target : trimmed
    }

    public var target: String {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if user.isEmpty { return hostname }
        return "\(user)@\(hostname)"
    }

    /// Login-shell command that execs mosh so the PTY is the remote session.
    public var moshCommand: String {
        MoshCommand.loginShellCommand(target: target, sshPort: sshPort)
    }

    public var isValid: Bool {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if let sshPort {
            return (1...65_535).contains(sshPort)
        }
        return true
    }
}

public enum MoshCommand {
    public static func loginShellCommand(target: String, sshPort: Int?) -> String {
        var arguments = ["exec", "mosh"]
        if let sshPort, sshPort != 22 {
            arguments.append("--ssh=\(posixQuote("ssh -p \(sshPort)"))")
        }
        arguments.append(posixQuote(target))
        return arguments.joined(separator: " ")
    }

    public static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:@+"))
        if value.unicodeScalars.allSatisfy(allowed.contains) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
