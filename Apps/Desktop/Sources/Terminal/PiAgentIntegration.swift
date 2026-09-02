import Darwin
import FissionCore
import Foundation
import Observation

@MainActor
@Observable
final class AgentActivityModel {
    private struct Activity {
        var state: AgentActivityState
        var sequence: Int64
    }

    private var activities: [UUID: [UUID: Activity]] = [:]
    private var threadsWithAgentRun: Set<UUID> = []
    @ObservationIgnored private var receiver: AgentActivityReceiver?

    init(installPiIntegration: Bool = true) {
        if installPiIntegration {
            PiAgentExtensionInstaller.install()
        }

        do {
            let receiver = try AgentActivityReceiver()
            self.receiver = receiver
            receiver.start { [weak self] report in
                Task { @MainActor in
                    self?.accept(report)
                }
            }
        } catch {
            NSLog("Fission could not start the agent activity receiver: %@", String(describing: error))
        }
    }

    func environment(threadID: UUID, tabID: UUID) -> [String: String] {
        guard let receiver else { return [:] }
        return [
            "FISSION_AGENT_PORT": String(receiver.port),
            "FISSION_AGENT_TOKEN": receiver.token,
            "FISSION_THREAD_ID": threadID.uuidString,
            "FISSION_TAB_ID": tabID.uuidString
        ]
    }

    func state(for threadID: UUID) -> AgentActivityState? {
        guard threadsWithAgentRun.contains(threadID) else { return nil }
        let states = activities[threadID]?.values.map(\.state) ?? []
        if states.contains(.blocked) { return .blocked }
        if states.contains(.running) { return .running }
        if states.contains(.finished) { return .finished }
        return .idle
    }

    func acknowledgeFinished(threadID: UUID) {
        guard var threadActivities = activities[threadID] else { return }
        for tabID in threadActivities.keys where threadActivities[tabID]?.state == .finished {
            threadActivities[tabID]?.state = .idle
        }
        activities[threadID] = threadActivities
    }

    func forget(threadID: UUID, tabID: UUID) {
        activities[threadID]?[tabID] = nil
        if activities[threadID]?.isEmpty == true {
            activities[threadID] = nil
        }
    }

    func forget(threadID: UUID) {
        activities[threadID] = nil
        threadsWithAgentRun.remove(threadID)
    }

    private func accept(_ report: AgentActivityReport) {
        guard report.version == 1,
              report.token == receiver?.token,
              report.agent == "pi",
              let threadID = UUID(uuidString: report.threadId),
              let tabID = UUID(uuidString: report.tabId)
        else {
            return
        }

        if let previous = activities[threadID]?[tabID], report.sequence <= previous.sequence {
            return
        }
        if report.state != .idle {
            threadsWithAgentRun.insert(threadID)
        }
        activities[threadID, default: [:]][tabID] = Activity(
            state: report.state,
            sequence: report.sequence
        )
    }
}

private struct AgentActivityReport: Decodable, Sendable {
    let version: Int
    let token: String
    let threadId: String
    let tabId: String
    let agent: String
    let state: AgentActivityState
    let sequence: Int64
}

private final class AgentActivityReceiver: @unchecked Sendable {
    let port: UInt16
    let token = UUID().uuidString

    private let descriptor: Int32
    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "com.fission.agent-activity")
    private var onReport: (@Sendable (AgentActivityReport) -> Void)?

    init() throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &boundAddressLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        self.descriptor = descriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
    }

    func start(onReport: @escaping @Sendable (AgentActivityReport) -> Void) {
        self.onReport = onReport
        source.setEventHandler { [weak self] in
            self?.receiveAvailableReports()
        }
        source.resume()
    }

    private func receiveAvailableReports() {
        while true {
            var bytes = [UInt8](repeating: 0, count: 8_192)
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.recv(descriptor, buffer.baseAddress, buffer.count, MSG_DONTWAIT)
            }
            guard count > 0 else { return }

            let data = Data(bytes.prefix(Int(count)))
            guard let report = try? JSONDecoder().decode(AgentActivityReport.self, from: data) else {
                continue
            }
            onReport?(report)
        }
    }

    deinit {
        source.cancel()
    }
}

private enum PiAgentExtensionInstaller {
    static func install() {
        guard let source = Bundle.main.url(
            forResource: "fission-pi-agent-state",
            withExtension: "ts"
        ) else {
            NSLog("Fission's bundled Pi agent integration is missing")
            return
        }

        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let agentDirectory: URL
        if let configuredPath = environment["PI_CODING_AGENT_DIR"],
           configuredPath.hasPrefix("/") {
            agentDirectory = URL(fileURLWithPath: configuredPath, isDirectory: true)
        } else {
            agentDirectory = fileManager.homeDirectoryForCurrentUser
                .appending(path: ".pi/agent", directoryHint: .isDirectory)
        }

        let extensionsDirectory = agentDirectory.appending(
            path: "extensions",
            directoryHint: .isDirectory
        )
        let destination = extensionsDirectory.appending(path: "fission-agent-state.ts")

        do {
            let bundledData = try Data(contentsOf: source)
            if let installedData = try? Data(contentsOf: destination), installedData == bundledData {
                return
            }
            try fileManager.createDirectory(
                at: extensionsDirectory,
                withIntermediateDirectories: true
            )
            try bundledData.write(to: destination, options: .atomic)
        } catch {
            NSLog("Fission could not install the Pi agent integration: %@", String(describing: error))
        }
    }
}
