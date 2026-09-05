// The daemon deliberately concentrates process ownership, PTY lifecycle, replay,
// and IPC in one deep module.
// swiftlint:disable file_length

import Darwin
import Foundation

private final class ClientConnection {
    let descriptor: Int32
    var sessionID: UUID?
    var readBuffer = Data()
    var writeBuffer = Data()
    var readSource: DispatchSourceRead?
    var writeSource: DispatchSourceWrite?
    var isWriteSourceResumed = false

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }
}

private final class HostedTerminal {
    let id: UUID
    let threadID: UUID
    let processID: pid_t
    let ptyDescriptor: Int32
    let startedAt = ProcessInfo.processInfo.systemUptime
    var replay = Data()
    var replayStartOffset: UInt64 = 0
    var nextOutputOffset: UInt64 = 0
    var clients: Set<Int32> = []
    var readSource: DispatchSourceRead?
    var writeSource: DispatchSourceWrite?
    var isWriteSourceResumed = false
    var pendingInput = Data()
    var processSource: DispatchSourceProcess?
    var exitStatus: (code: UInt32, runtime: UInt64)?
    var removeWhenExited = false

    init(id: UUID, threadID: UUID, processID: pid_t, ptyDescriptor: Int32) {
        self.id = id
        self.threadID = threadID
        self.processID = processID
        self.ptyDescriptor = ptyDescriptor
    }
}

// The module stays deep by keeping transport and process lifecycle private.
// swiftlint:disable:next type_body_length
private final class TerminalExecutionDaemon {
    private let socketPath: String
    private let exitsWhenDetached: Bool
    private let queue = DispatchQueue(label: "com.fission.execution-daemon")
    private var listener: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var clients: [Int32: ClientConnection] = [:]
    private var terminals: [UUID: HostedTerminal] = [:]

    init(socketPath: String, exitsWhenDetached: Bool) {
        self.socketPath = socketPath
        self.exitsWhenDetached = exitsWhenDetached
    }

    func run() throws -> Never {
        signal(SIGPIPE, SIG_IGN)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: socketPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        lockDescriptor = Darwin.open("\(socketPath).lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockDescriptor >= 0 else { throw currentPOSIXError() }
        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw DaemonError.alreadyRunning
        }

        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        unlink(socketPath)

        let bindResult = TerminalExecutionProtocol.withSocketAddress(path: socketPath) {
            Darwin.bind(listener, $0, $1)
        }
        guard bindResult == 0 else { throw currentPOSIXError() }
        guard Darwin.listen(listener, 32) == 0 else { throw currentPOSIXError() }
        let listenerFlags = fcntl(listener, F_GETFL)
        _ = fcntl(listener, F_SETFL, listenerFlags | O_NONBLOCK)
        chmod(socketPath, S_IRUSR | S_IWUSR)

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnections() }
        listenerSource = source
        source.resume()
        dispatchMain()
    }

    private func acceptConnections() {
        while true {
            let descriptor = Darwin.accept(listener, nil, nil)
            guard descriptor >= 0 else { return }
            var noPipe: Int32 = 1
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )
            let flags = fcntl(descriptor, F_GETFL)
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

            let connection = ClientConnection(descriptor: descriptor)
            clients[descriptor] = connection
            let readSource = DispatchSource.makeReadSource(
                fileDescriptor: descriptor,
                queue: queue
            )
            readSource.setEventHandler { [weak self, weak connection] in
                guard let connection else { return }
                self?.read(from: connection)
            }
            readSource.setCancelHandler { Darwin.close(descriptor) }
            connection.readSource = readSource
            readSource.resume()

            let writeSource = DispatchSource.makeWriteSource(
                fileDescriptor: descriptor,
                queue: queue
            )
            writeSource.setEventHandler { [weak self, weak connection] in
                guard let connection else { return }
                self?.flushOutput(to: connection)
            }
            connection.writeSource = writeSource
        }
    }

    private func read(from connection: ClientConnection) {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(connection.descriptor, &bytes, bytes.count)
        if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
        guard count > 0 else {
            disconnect(connection)
            return
        }
        connection.readBuffer.append(contentsOf: bytes.prefix(Int(count)))

        while let newline = connection.readBuffer.firstIndex(of: 0x0A) {
            let message = connection.readBuffer[..<newline]
            connection.readBuffer.removeSubrange(...newline)
            guard let request = try? JSONDecoder().decode(
                TerminalExecutionProtocol.Request.self,
                from: message
            ) else {
                sendFailure("Malformed request", sessionID: UUID(), to: connection)
                continue
            }
            handle(request, from: connection)
        }
    }

    private func handle(
        _ request: TerminalExecutionProtocol.Request,
        from connection: ClientConnection
    ) {
        guard request.version == TerminalExecutionProtocol.version else {
            sendFailure("Unsupported protocol version", sessionID: request.sessionID, to: connection)
            return
        }

        switch request.kind {
        case .attachOrCreate:
            attachOrCreate(request, connection: connection)
        case .input:
            guard connection.sessionID == request.sessionID,
                  let data = request.data,
                  let terminal = terminals[request.sessionID],
                  terminal.exitStatus == nil else { return }
            enqueueInput(data, to: terminal)
        case .resize:
            guard connection.sessionID == request.sessionID,
                  let columns = request.columns,
                  let rows = request.rows,
                  let terminal = terminals[request.sessionID],
                  terminal.exitStatus == nil else { return }
            var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(terminal.ptyDescriptor, TIOCSWINSZ, &size)
        case .terminate:
            guard let terminal = terminals[request.sessionID] else { return }
            terminal.removeWhenExited = true
            if terminal.exitStatus != nil {
                terminals[terminal.id] = nil
            } else {
                kill(-terminal.processID, SIGHUP)
                kill(terminal.processID, SIGHUP)
            }
        }
    }

    // Creation and attachment are atomic on the daemon queue.
    // swiftlint:disable:next function_body_length
    private func attachOrCreate(
        _ request: TerminalExecutionProtocol.Request,
        connection: ClientConnection
    ) {
        if let previousID = connection.sessionID {
            terminals[previousID]?.clients.remove(connection.descriptor)
        }

        let terminal: HostedTerminal
        if let existing = terminals[request.sessionID] {
            terminal = existing
        } else {
            guard let threadID = request.threadID else {
                sendFailure("A new terminal requires a Thread ID", sessionID: request.sessionID, to: connection)
                return
            }
            do {
                terminal = try spawnTerminal(
                    id: request.sessionID,
                    threadID: threadID,
                    workingDirectory: request.workingDirectory,
                    environment: request.environment ?? [:]
                )
                terminals[terminal.id] = terminal
            } catch {
                sendFailure(String(describing: error), sessionID: request.sessionID, to: connection)
                return
            }
        }

        connection.sessionID = terminal.id
        terminal.clients.insert(connection.descriptor)
        let requestedOffset = request.resumeOffset ?? 0
        let replayOffset: UInt64
        if requestedOffset > terminal.nextOutputOffset {
            // The client outlived a previous daemon instance and must rebuild
            // its renderer from this new session's available replay.
            replayOffset = terminal.replayStartOffset
        } else {
            replayOffset = min(
                max(requestedOffset, terminal.replayStartOffset),
                terminal.nextOutputOffset
            )
        }
        let replayIndex = Int(replayOffset - terminal.replayStartOffset)
        send(
            .init(
                version: TerminalExecutionProtocol.version,
                kind: .attached,
                sessionID: terminal.id,
                data: Data(terminal.replay.dropFirst(replayIndex)),
                offset: replayOffset
            ),
            to: connection
        )
        if let exit = terminal.exitStatus {
            send(
                .init(
                    version: TerminalExecutionProtocol.version,
                    kind: .exited,
                    sessionID: terminal.id,
                    exitCode: exit.code,
                    runtimeMilliseconds: exit.runtime
                ),
                to: connection
            )
        }
    }

    // PTY setup is kept in one linear transaction so every failure closes its descriptors.
    // swiftlint:disable:next function_body_length
    private func spawnTerminal(
        id: UUID,
        threadID: UUID,
        workingDirectory: String?,
        environment additions: [String: String]
    ) throws -> HostedTerminal {
        var controllerDescriptor: Int32 = -1
        var terminalDescriptor: Int32 = -1
        var terminalName = [CChar](repeating: 0, count: Int(PATH_MAX))
        var initialSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(
            &controllerDescriptor,
            &terminalDescriptor,
            &terminalName,
            nil,
            &initialSize
        ) == 0 else {
            throw currentPOSIXError()
        }
        defer { Darwin.close(terminalDescriptor) }

        let terminalPath = String(cString: terminalName)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = ProcessInfo.processInfo.environment
        environment.merge(additions) { _, requested in requested }
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["COLORTERM"] = environment["COLORTERM"] ?? "truecolor"
        environment["TERM_PROGRAM"] = "Fission"

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            Darwin.close(controllerDescriptor)
            throw POSIXError(.EIO)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, terminalPath, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, controllerDescriptor)
        posix_spawn_file_actions_addclose(&actions, terminalDescriptor)
        if let workingDirectory, !workingDirectory.isEmpty {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory)
        }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            Darwin.close(controllerDescriptor)
            throw POSIXError(.EIO)
        }
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var processID: pid_t = 0
        // posix_spawn cannot run TIOCSCTTY between creating the new session and
        // execing the shell. Re-enter this executable for that one child-only step.
        let launcher = CommandLine.arguments[0]
        let arguments = [launcher, "--terminal-child", shell]
        let environmentEntries = environment.map { "\($0.key)=\($0.value)" }
        let spawnResult = withCStringArray(arguments) { argumentPointers in
            withCStringArray(environmentEntries) { environmentPointers in
                posix_spawn(
                    &processID,
                    launcher,
                    &actions,
                    &attributes,
                    argumentPointers,
                    environmentPointers
                )
            }
        }
        guard spawnResult == 0 else {
            Darwin.close(controllerDescriptor)
            throw POSIXError(POSIXErrorCode(rawValue: spawnResult) ?? .EIO)
        }

        let flags = fcntl(controllerDescriptor, F_GETFL)
        _ = fcntl(controllerDescriptor, F_SETFL, flags | O_NONBLOCK)

        let terminal = HostedTerminal(
            id: id,
            threadID: threadID,
            processID: processID,
            ptyDescriptor: controllerDescriptor
        )
        observeOutput(of: terminal)
        observeInput(of: terminal)
        observeExit(of: terminal)
        return terminal
    }

    private func observeOutput(of terminal: HostedTerminal) {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: terminal.ptyDescriptor,
            queue: queue
        )
        source.setEventHandler { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            var bytes = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = Darwin.read(terminal.ptyDescriptor, &bytes, bytes.count)
                guard count > 0 else { return }
                let data = Data(bytes.prefix(Int(count)))
                let outputOffset = terminal.nextOutputOffset
                terminal.nextOutputOffset += UInt64(data.count)
                terminal.replay.append(data)
                let excess = terminal.replay.count - TerminalExecutionProtocol.replayByteLimit
                if excess > 0 {
                    terminal.replay.removeFirst(excess)
                    terminal.replayStartOffset += UInt64(excess)
                }
                broadcast(
                    .init(
                        version: TerminalExecutionProtocol.version,
                        kind: .output,
                        sessionID: terminal.id,
                        data: data,
                        offset: outputOffset
                    ),
                    to: terminal
                )
            }
        }
        source.setCancelHandler { Darwin.close(terminal.ptyDescriptor) }
        terminal.readSource = source
        source.resume()
    }

    private func observeInput(of terminal: HostedTerminal) {
        let source = DispatchSource.makeWriteSource(
            fileDescriptor: terminal.ptyDescriptor,
            queue: queue
        )
        source.setEventHandler { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            flushInput(to: terminal)
        }
        terminal.writeSource = source
    }

    private func observeExit(of terminal: HostedTerminal) {
        let source = DispatchSource.makeProcessSource(
            identifier: terminal.processID,
            eventMask: .exit,
            queue: queue
        )
        source.setEventHandler { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            var status: Int32 = 0
            waitpid(terminal.processID, &status, 0)
            let code: UInt32
            if status & 0x7F == 0 {
                code = UInt32((status >> 8) & 0xFF)
            } else {
                code = UInt32(128 + (status & 0x7F))
            }
            let runtime = UInt64(
                max(0, ProcessInfo.processInfo.systemUptime - terminal.startedAt) * 1_000
            )
            terminal.exitStatus = (code, runtime)
            broadcast(
                .init(
                    version: TerminalExecutionProtocol.version,
                    kind: .exited,
                    sessionID: terminal.id,
                    exitCode: code,
                    runtimeMilliseconds: runtime
                ),
                to: terminal
            )
            terminal.readSource?.cancel()
            terminal.readSource = nil
            cancelInputSource(of: terminal)
            terminal.processSource?.cancel()
            terminal.processSource = nil
            if terminal.removeWhenExited {
                terminals[terminal.id] = nil
            }
        }
        terminal.processSource = source
        source.resume()
    }

    private func broadcast(
        _ response: TerminalExecutionProtocol.Response,
        to terminal: HostedTerminal
    ) {
        for descriptor in Array(terminal.clients) {
            if let connection = clients[descriptor] {
                send(response, to: connection)
            }
        }
    }

    private func sendFailure(_ message: String, sessionID: UUID, to connection: ClientConnection) {
        send(
            .init(
                version: TerminalExecutionProtocol.version,
                kind: .failure,
                sessionID: sessionID,
                message: message
            ),
            to: connection
        )
    }

    private func send(_ response: TerminalExecutionProtocol.Response, to connection: ClientConnection) {
        guard let data = try? TerminalExecutionProtocol.encode(response) else { return }
        connection.writeBuffer.append(data)
        guard connection.writeBuffer.count <= 8 * 1_024 * 1_024 else {
            disconnect(connection)
            return
        }
        if !connection.isWriteSourceResumed {
            connection.isWriteSourceResumed = true
            connection.writeSource?.resume()
        }
    }

    private func flushOutput(to connection: ClientConnection) {
        while !connection.writeBuffer.isEmpty {
            let count = connection.writeBuffer.withUnsafeBytes { bytes in
                Darwin.send(connection.descriptor, bytes.baseAddress, bytes.count, 0)
            }
            if count > 0 {
                connection.writeBuffer.removeFirst(count)
            } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                disconnect(connection)
                return
            }
        }
        if connection.isWriteSourceResumed {
            connection.writeSource?.suspend()
            connection.isWriteSourceResumed = false
        }
    }

    private func enqueueInput(_ data: Data, to terminal: HostedTerminal) {
        terminal.pendingInput.append(data)
        guard terminal.pendingInput.count <= 16 * 1_024 * 1_024 else {
            terminal.pendingInput.removeAll()
            for descriptor in Array(terminal.clients) {
                if let connection = clients[descriptor] { disconnect(connection) }
            }
            return
        }
        if !terminal.isWriteSourceResumed {
            terminal.isWriteSourceResumed = true
            terminal.writeSource?.resume()
        }
    }

    private func flushInput(to terminal: HostedTerminal) {
        while !terminal.pendingInput.isEmpty {
            let count = terminal.pendingInput.withUnsafeBytes { bytes in
                Darwin.write(terminal.ptyDescriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                terminal.pendingInput.removeFirst(count)
            } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                terminal.pendingInput.removeAll()
                break
            }
        }
        if terminal.isWriteSourceResumed {
            terminal.writeSource?.suspend()
            terminal.isWriteSourceResumed = false
        }
    }

    private func cancelInputSource(of terminal: HostedTerminal) {
        guard let source = terminal.writeSource else { return }
        if !terminal.isWriteSourceResumed { source.resume() }
        source.cancel()
        terminal.writeSource = nil
        terminal.isWriteSourceResumed = false
    }

    private func disconnect(_ connection: ClientConnection) {
        if let sessionID = connection.sessionID {
            terminals[sessionID]?.clients.remove(connection.descriptor)
        }
        clients[connection.descriptor] = nil
        connection.readSource?.cancel()
        connection.readSource = nil
        if let writeSource = connection.writeSource {
            if !connection.isWriteSourceResumed { writeSource.resume() }
            writeSource.cancel()
            connection.writeSource = nil
            connection.isWriteSourceResumed = false
        }

        if exitsWhenDetached, clients.isEmpty {
            for terminal in terminals.values {
                kill(-terminal.processID, SIGHUP)
                kill(terminal.processID, SIGHUP)
            }
            unlink(socketPath)
            exit(EXIT_SUCCESS)
        }
    }

}

private enum DaemonError: Error {
    case alreadyRunning
}

private func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}

private func withCStringArray<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
    var pointers = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.dropLast().forEach { free($0) } }
    return pointers.withUnsafeMutableBufferPointer { buffer in
        body(buffer.baseAddress!)
    }
}

/// Completes PTY setup after `POSIX_SPAWN_SETSID`, then becomes the user's shell.
private func runTerminalChild(shell: String) -> Never {
    guard ioctl(STDIN_FILENO, TIOCSCTTY, 0) == 0 else {
        FileHandle.standardError.write(
            Data("FissionExecution: could not set the controlling terminal: \(currentPOSIXError())\n".utf8)
        )
        exit(EXIT_FAILURE)
    }
    guard tcsetpgrp(STDIN_FILENO, getpgrp()) == 0 else {
        FileHandle.standardError.write(
            Data("FissionExecution: could not set the foreground process group: \(currentPOSIXError())\n".utf8)
        )
        exit(EXIT_FAILURE)
    }

    signal(SIGPIPE, SIG_DFL)
    let shellArguments = [shell, "-l"]
    withCStringArray(shellArguments) { pointers in
        execv(shell, pointers)
    }
    FileHandle.standardError.write(
        Data("FissionExecution: could not execute \(shell): \(currentPOSIXError())\n".utf8)
    )
    exit(EXIT_FAILURE)
}

let arguments = CommandLine.arguments
if let childIndex = arguments.firstIndex(of: "--terminal-child"),
   arguments.indices.contains(childIndex + 1) {
    runTerminalChild(shell: arguments[childIndex + 1])
}

let socketPath: String
if let socketIndex = arguments.firstIndex(of: "--socket"),
   arguments.indices.contains(socketIndex + 1) {
    socketPath = arguments[socketIndex + 1]
} else {
    socketPath = TerminalExecutionProtocol.socketPath
}

do {
    try TerminalExecutionDaemon(
        socketPath: socketPath,
        exitsWhenDetached: arguments.contains("--exit-when-detached")
    ).run()
} catch DaemonError.alreadyRunning {
    exit(EXIT_SUCCESS)
} catch {
    FileHandle.standardError.write(Data("FissionExecution: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
