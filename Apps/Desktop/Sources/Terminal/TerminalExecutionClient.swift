import Darwin
import Foundation
import GhosttyTerminal

/// A renderer-side attachment to a terminal whose process is owned by
/// FissionExecution. Destroying this object only detaches the renderer.
final class PersistentTerminalSession: @unchecked Sendable {
    let renderer: InMemoryTerminalSession

    private let connection: TerminalDaemonConnection

    init(
        id: UUID,
        threadID: UUID,
        workingDirectory: String?,
        environment: [String: String]
    ) {
        connection = TerminalDaemonConnection(
            sessionID: id,
            threadID: threadID,
            workingDirectory: workingDirectory,
            environment: environment
        )

        renderer = InMemoryTerminalSession(
            write: { [weak connection] data in
                connection?.send(.input(sessionID: id, data: data))
            },
            resize: { [weak connection] viewport in
                connection?.send(.resize(
                    sessionID: id,
                    columns: viewport.columns,
                    rows: viewport.rows
                ))
            },
            suppressesPixelOnlyResizes: true
        )

        connection.onResponse = { [weak renderer, weak connection] response in
            guard response.version == TerminalExecutionProtocol.version else { return }
            switch response.kind {
            case .attached, .output:
                if let data = connection?.unseenData(from: response), !data.isEmpty {
                    renderer?.receive(data)
                }
            case .exited:
                renderer?.finish(
                    exitCode: response.exitCode ?? 0,
                    runtimeMilliseconds: response.runtimeMilliseconds ?? 0
                )
            case .failure:
                if let message = response.message {
                    renderer?.receive("\r\n[Fission execution error: \(message)]\r\n")
                }
            }
        }
        connection.start()
    }

    func terminate() {
        connection.send(.terminate(sessionID: connection.sessionID))
        connection.disconnect()
    }
}

enum TerminalExecutionControl {
    static func terminate(sessionIDs: [UUID]) {
        guard !sessionIDs.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return }
            defer { Darwin.close(descriptor) }
            var noPipe: Int32 = 1
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )
            let connected = TerminalExecutionProtocol.withSocketAddress {
                Darwin.connect(descriptor, $0, $1)
            } == 0
            guard connected else { return }

            for sessionID in sessionIDs {
                guard let data = try? TerminalExecutionProtocol.encode(
                    TerminalExecutionProtocol.Request.terminate(sessionID: sessionID)
                ) else {
                    continue
                }
                data.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    _ = Darwin.send(descriptor, base, bytes.count, 0)
                }
            }
        }
    }
}

private final class TerminalDaemonConnection: @unchecked Sendable {
    let sessionID: UUID
    var onResponse: (@Sendable (TerminalExecutionProtocol.Response) -> Void)?

    private let threadID: UUID
    private let workingDirectory: String?
    private let environment: [String: String]
    private let queue = DispatchQueue(label: "com.fission.terminal-connection")
    private var descriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var readBuffer = Data()
    private var isStopped = false
    private var didRequestLaunch = false
    private var pendingRequests: [TerminalExecutionProtocol.Request] = []
    private var nextOutputOffset: UInt64 = 0

    init(
        sessionID: UUID,
        threadID: UUID,
        workingDirectory: String?,
        environment: [String: String]
    ) {
        self.sessionID = sessionID
        self.threadID = threadID
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    deinit {
        readSource?.cancel()
        if readSource == nil, descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }

    func start() {
        queue.async { [weak self] in self?.connect() }
    }

    func send(_ request: TerminalExecutionProtocol.Request) {
        queue.async { [weak self] in
            guard let self else { return }
            enqueue(request)
            flushPendingRequests()
        }
    }

    func unseenData(from response: TerminalExecutionProtocol.Response) -> Data? {
        // Responses and this method are delivered on `queue`.
        let responseOffset = response.offset ?? nextOutputOffset
        if response.kind == .attached, responseOffset < nextOutputOffset {
            nextOutputOffset = responseOffset
        }
        guard let data = response.data, !data.isEmpty else { return nil }
        if responseOffset > nextOutputOffset {
            nextOutputOffset = responseOffset
        }
        let overlap = nextOutputOffset > responseOffset
            ? min(Int(nextOutputOffset - responseOffset), data.count)
            : 0
        let unseen = data.dropFirst(overlap)
        nextOutputOffset += UInt64(unseen.count)
        return Data(unseen)
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            isStopped = true
            handleDisconnect(retry: false)
        }
    }

    private func connect() {
        guard !isStopped, descriptor < 0 else { return }

        let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            scheduleReconnect()
            return
        }
        var noPipe: Int32 = 1
        setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )

        let result = TerminalExecutionProtocol.withSocketAddress { address, length in
            Darwin.connect(socketDescriptor, address, length)
        }
        guard result == 0 else {
            Darwin.close(socketDescriptor)
            if !didRequestLaunch {
                didRequestLaunch = true
                TerminalDaemonLauncher.launch()
            }
            scheduleReconnect()
            return
        }

        descriptor = socketDescriptor
        didRequestLaunch = false
        let source = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailableData() }
        source.setCancelHandler { Darwin.close(socketDescriptor) }
        readSource = source
        source.resume()

        do {
            let request = TerminalExecutionProtocol.Request.attachOrCreate(
                sessionID: sessionID,
                threadID: threadID,
                workingDirectory: workingDirectory,
                environment: environment,
                resumeOffset: nextOutputOffset
            )
            try sendAll(TerminalExecutionProtocol.encode(request))
            flushPendingRequests()
        } catch {
            handleDisconnect(retry: true)
        }
    }

    private func readAvailableData() {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        guard count > 0 else {
            handleDisconnect(retry: true)
            return
        }
        readBuffer.append(contentsOf: bytes.prefix(Int(count)))

        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let message = readBuffer[..<newline]
            readBuffer.removeSubrange(...newline)
            guard let response = try? JSONDecoder().decode(
                TerminalExecutionProtocol.Response.self,
                from: message
            ) else {
                continue
            }
            onResponse?(response)
        }
    }

    private func enqueue(_ request: TerminalExecutionProtocol.Request) {
        if request.kind == .resize {
            pendingRequests.removeAll { $0.kind == .resize }
        }
        pendingRequests.append(request)

        let queuedInputBytes = pendingRequests.reduce(into: 0) { count, request in
            count += request.data?.count ?? 0
        }
        if queuedInputBytes > 16 * 1_024 * 1_024,
           let inputIndex = pendingRequests.firstIndex(where: { $0.kind == .input }) {
            pendingRequests.remove(at: inputIndex)
            onResponse?(.init(
                version: TerminalExecutionProtocol.version,
                kind: .failure,
                sessionID: sessionID,
                message: "Terminal input queue exceeded 16 MiB"
            ))
        }
    }

    private func flushPendingRequests() {
        guard descriptor >= 0 else { return }
        while let request = pendingRequests.first {
            do {
                try sendAll(TerminalExecutionProtocol.encode(request))
                pendingRequests.removeFirst()
            } catch {
                handleDisconnect(retry: true)
                return
            }
        }
    }

    private func sendAll(_ data: Data) throws {
        var sent = 0
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            while sent < bytes.count {
                let count = Darwin.send(descriptor, base.advanced(by: sent), bytes.count - sent, 0)
                guard count > 0 else { throw POSIXError(.EPIPE) }
                sent += count
            }
        }
    }

    private func handleDisconnect(retry: Bool) {
        guard descriptor >= 0 || readSource != nil else {
            if retry { scheduleReconnect() }
            return
        }
        descriptor = -1
        readBuffer.removeAll(keepingCapacity: true)
        readSource?.cancel()
        readSource = nil
        if retry { scheduleReconnect() }
    }

    private func scheduleReconnect() {
        guard !isStopped else { return }
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.connect()
        }
    }
}

private enum TerminalDaemonLauncher {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var lastLaunchUptime: TimeInterval = 0

    static func launch() {
        lock.lock()
        defer { lock.unlock() }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLaunchUptime > 2 else { return }
        lastLaunchUptime = now

        let executable = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/FissionExecution")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            NSLog("Fission execution helper is missing at %@", executable.path)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: TerminalExecutionProtocol.socketPath)
                    .deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--socket", TerminalExecutionProtocol.socketPath]
            let environment = ProcessInfo.processInfo.environment
            let isRunningTests = NSClassFromString("XCTestCase") != nil
                || environment["XCTestConfigurationFilePath"] != nil
            if environment["FISSION_EXECUTION_EPHEMERAL"] == "1" || isRunningTests {
                process.arguments?.append("--exit-when-detached")
            }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            NSLog("Fission could not launch its execution helper: %@", String(describing: error))
        }
    }
}
