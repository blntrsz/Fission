import Foundation

/// A registered host that Desktop can open as a remote Thread over mosh.
public struct RemoteMachine: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var username: String
    public var host: String
    public var sshPort: Int?
    /// Remote directory new Threads on this machine open in.
    public var projectPath: String?

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        host: String,
        sshPort: Int? = nil,
        projectPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.host = host
        self.sshPort = sshPort
        self.projectPath = Self.normalizedProjectPath(projectPath)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, username, host, sshPort, projectPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        host = try container.decode(String.self, forKey: .host)
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort)
        projectPath = Self.normalizedProjectPath(
            try container.decodeIfPresent(String.self, forKey: .projectPath)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(username, forKey: .username)
        try container.encode(host, forKey: .host)
        try container.encodeIfPresent(sshPort, forKey: .sshPort)
        try container.encodeIfPresent(projectPath, forKey: .projectPath)
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
        MoshCommand.loginShellCommand(
            target: target,
            sshPort: sshPort,
            remoteDirectory: projectPath
        )
    }

    public static func normalizedProjectPath(_ path: String?) -> String? {
        MoshCommand.normalizedDirectory(path)
    }

    public static func projectName(from path: String) -> String? {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.isEmpty || trimmed == "~" || trimmed == "/" {
            return nil
        }
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return name.isEmpty ? nil : name
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
    public static func loginShellCommand(
        target: String,
        sshPort: Int?,
        remoteDirectory: String? = nil
    ) -> String {
        var arguments = ["exec", "mosh"]
        if let sshPort, sshPort != 22 {
            arguments.append("--ssh=\(posixQuote("ssh -p \(sshPort)"))")
        }
        arguments.append(posixQuote(target))
        if let remoteDirectory = normalizedDirectory(remoteDirectory) {
            arguments.append("--")
            arguments.append("sh")
            arguments.append("-lc")
            arguments.append(posixQuote(
                "cd -- \(remoteDirectoryExpression(remoteDirectory)) && exec \"${SHELL:-/bin/sh}\" -l"
            ))
        }
        return arguments.joined(separator: " ")
    }

    public static func normalizedDirectory(_ path: String?) -> String? {
        guard var trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    public static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:@+"))
        if value.unicodeScalars.allSatisfy(allowed.contains) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func remoteDirectoryExpression(_ path: String) -> String {
        if path == "~" {
            return "\"$HOME\""
        }
        if path.hasPrefix("~/") {
            return "\"$HOME/" + escapeDoubleQuoted(String(path.dropFirst(2))) + "\""
        }
        return "\"" + escapeDoubleQuoted(path) + "\""
    }

    private static func escapeDoubleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }
}
