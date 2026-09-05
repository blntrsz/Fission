import Darwin
import Foundation

enum TerminalExecutionRequestKind: String, Codable, Sendable {
    case attachOrCreate
    case input
    case resize
    case terminate
}

enum TerminalExecutionResponseKind: String, Codable, Sendable {
    case attached
    case output
    case exited
    case failure
}

enum TerminalExecutionProtocol {
    // Version 2 prevents upgraded clients from reconnecting to helpers created
    // before terminal children acquired a controlling PTY and foreground group.
    static let version = 2
    static let replayByteLimit = 4 * 1_024 * 1_024

    struct Request: Codable, Sendable {
        let version: Int
        let kind: TerminalExecutionRequestKind
        let sessionID: UUID
        var threadID: UUID?
        var workingDirectory: String?
        var environment: [String: String]?
        var data: Data?
        var columns: UInt16?
        var rows: UInt16?
        var resumeOffset: UInt64?

        static func attachOrCreate(
            sessionID: UUID,
            threadID: UUID,
            workingDirectory: String?,
            environment: [String: String],
            resumeOffset: UInt64
        ) -> Self {
            Self(
                version: TerminalExecutionProtocol.version,
                kind: .attachOrCreate,
                sessionID: sessionID,
                threadID: threadID,
                workingDirectory: workingDirectory,
                environment: environment,
                resumeOffset: resumeOffset
            )
        }

        static func input(sessionID: UUID, data: Data) -> Self {
            Self(
                version: TerminalExecutionProtocol.version,
                kind: .input,
                sessionID: sessionID,
                data: data
            )
        }

        static func resize(sessionID: UUID, columns: UInt16, rows: UInt16) -> Self {
            Self(
                version: TerminalExecutionProtocol.version,
                kind: .resize,
                sessionID: sessionID,
                columns: columns,
                rows: rows
            )
        }

        static func terminate(sessionID: UUID) -> Self {
            Self(
                version: TerminalExecutionProtocol.version,
                kind: .terminate,
                sessionID: sessionID
            )
        }

        private init(
            version: Int,
            kind: TerminalExecutionRequestKind,
            sessionID: UUID,
            threadID: UUID? = nil,
            workingDirectory: String? = nil,
            environment: [String: String]? = nil,
            data: Data? = nil,
            columns: UInt16? = nil,
            rows: UInt16? = nil,
            resumeOffset: UInt64? = nil
        ) {
            self.version = version
            self.kind = kind
            self.sessionID = sessionID
            self.threadID = threadID
            self.workingDirectory = workingDirectory
            self.environment = environment
            self.data = data
            self.columns = columns
            self.rows = rows
            self.resumeOffset = resumeOffset
        }
    }

    struct Response: Codable, Sendable {
        let version: Int
        let kind: TerminalExecutionResponseKind
        let sessionID: UUID
        var data: Data?
        var exitCode: UInt32?
        var runtimeMilliseconds: UInt64?
        var message: String?
        var offset: UInt64?
    }

    static var socketPath: String {
        let applicationSupportPath = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].path
        let channel = ProcessInfo.processInfo.environment["FISSION_EXECUTION_CHANNEL"]
            ?? Bundle.main.bundleIdentifier
            ?? "com.fission.desktop"
        // sockaddr_un paths are limited to roughly 100 bytes. A stable hash keeps
        // isolated test homes and deeply nested user homes safely below that limit.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(applicationSupportPath)|\(channel)|v\(version)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "/tmp/fission-execution-\(getuid())-\(String(hash, radix: 16)).sock"
    }

    static func encode<Message: Encodable>(_ message: Message) throws -> Data {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        return data
    }

    static func withSocketAddress<Result>(
        path: String = socketPath,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
    ) rethrows -> Result {
        precondition(path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            path.utf8CString.withUnsafeBytes { pathBytes in
                bytes.copyBytes(from: pathBytes)
            }
        }
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}
