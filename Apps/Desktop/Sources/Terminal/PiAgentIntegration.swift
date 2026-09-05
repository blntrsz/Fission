import Darwin
import FissionCore
import Foundation
import Observation

struct AgentFinishedNotification: Equatable, Sendable {
    let threadID: UUID
    let tabID: UUID
    let sequence: Int64
    let threadTitle: String
    let workingDirectory: String?
}

protocol AgentActivityNotificationAdapter: Sendable {
    func notifyAgentFinished(_ notification: AgentFinishedNotification) throws
}

protocol AgentActivityReportSource: AnyObject, Sendable {
    var token: String { get }
    var environment: [String: String] { get }
    func start(onReport: @escaping @Sendable (Data) -> Void)
}

private struct IgnoreAgentActivityNotifications: AgentActivityNotificationAdapter {
    func notifyAgentFinished(_ notification: AgentFinishedNotification) {}
}

@MainActor
@Observable
final class AgentActivityModel {
    private struct SessionID: Hashable {
        let threadID: UUID
        let tabID: UUID
    }

    private struct Activity {
        var state: AgentActivityState
        var reportedState: AgentActivityState
        var sequence: Int64
    }

    private struct ThreadMetadata {
        let title: String
        let workingDirectory: String?
    }

    private var activitiesByThread: [UUID: [UUID: Activity]] = [:]
    private var threadsWithAgentRun: Set<UUID> = []
    private var activeSessions: Set<SessionID> = []
    private var threadMetadata: [UUID: ThreadMetadata] = [:]
    private var selectedThreadID: UUID?
    private var isAppActive = false

    @ObservationIgnored private let reportSource: (any AgentActivityReportSource)?
    @ObservationIgnored private let notificationAdapter: any AgentActivityNotificationAdapter

    init(
        installPiIntegration: Bool = true,
        reportSource providedReportSource: (any AgentActivityReportSource)? = nil,
        notificationAdapter: any AgentActivityNotificationAdapter = IgnoreAgentActivityNotifications()
    ) {
        self.notificationAdapter = notificationAdapter

        if installPiIntegration {
            PiAgentExtensionInstaller.install()
        }

        if let providedReportSource {
            reportSource = providedReportSource
        } else {
            do {
                reportSource = try AgentActivityReceiver()
            } catch {
                reportSource = nil
                NSLog("Fission could not start the agent activity receiver: %@", String(describing: error))
            }
        }

        reportSource?.start { [weak self] data in
            Task { @MainActor in
                self?.accept(data)
            }
        }
    }

    func environment(threadID: UUID, tabID: UUID) -> [String: String] {
        activeSessions.insert(SessionID(threadID: threadID, tabID: tabID))
        guard let reportSource else { return [:] }

        return reportSource.environment.merging([
            "FISSION_THREAD_ID": threadID.uuidString,
            "FISSION_TAB_ID": tabID.uuidString
        ]) { _, sessionValue in sessionValue }
    }

    func activities(for threadID: UUID) -> [UUID: AgentActivityState] {
        guard threadsWithAgentRun.contains(threadID) else { return [:] }
        return (activitiesByThread[threadID] ?? [:]).mapValues(\.state)
    }

    func states(for threadID: UUID, orderedBy tabIDs: [UUID]) -> [AgentActivityState] {
        let activities = activities(for: threadID)
        return Array(tabIDs.compactMap { activities[$0] }.prefix(10))
    }

    func updateAttention(selectedThreadID: UUID?, isAppActive: Bool) {
        self.selectedThreadID = selectedThreadID
        self.isAppActive = isAppActive
        if let selectedThreadID {
            acknowledgeFinished(threadID: selectedThreadID)
        }
    }

    func synchronizeThreads(_ threads: [AgentThread]) {
        threadMetadata = Dictionary(uniqueKeysWithValues: threads.map {
            ($0.id, ThreadMetadata(title: $0.title, workingDirectory: $0.workingDirectory))
        })
    }

    func forget(threadID: UUID, tabID: UUID) {
        let session = SessionID(threadID: threadID, tabID: tabID)
        activeSessions.remove(session)
        activitiesByThread[threadID]?[tabID] = nil
        if activitiesByThread[threadID]?.isEmpty == true {
            activitiesByThread[threadID] = nil
            threadsWithAgentRun.remove(threadID)
        }
    }

    func forget(threadID: UUID) {
        activeSessions = Set(activeSessions.filter { $0.threadID != threadID })
        activitiesByThread[threadID] = nil
        threadsWithAgentRun.remove(threadID)
        threadMetadata[threadID] = nil
    }

    private func accept(_ data: Data) {
        guard let report = try? JSONDecoder().decode(AgentActivityReport.self, from: data),
              report.version == 1,
              report.token == reportSource?.token,
              report.agent == "pi",
              let threadID = UUID(uuidString: report.threadId),
              let tabID = UUID(uuidString: report.tabId),
              activeSessions.contains(SessionID(threadID: threadID, tabID: tabID))
        else {
            return
        }

        let previous = activitiesByThread[threadID]?[tabID]
        if let previous, report.sequence <= previous.sequence { return }

        if report.state != .idle {
            threadsWithAgentRun.insert(threadID)
        }
        activitiesByThread[threadID, default: [:]][tabID] = Activity(
            state: report.state,
            reportedState: report.state,
            sequence: report.sequence
        )

        let enteredFinishedActivity = report.state == .finished
            && previous?.reportedState != .finished
        if enteredFinishedActivity,
           !(isAppActive && selectedThreadID == threadID) {
            notifyFinished(threadID: threadID, tabID: tabID, sequence: report.sequence)
        }

        if selectedThreadID == threadID {
            acknowledgeFinished(threadID: threadID)
        }
    }

    private func acknowledgeFinished(threadID: UUID) {
        guard var threadActivities = activitiesByThread[threadID] else { return }
        for tabID in threadActivities.keys where threadActivities[tabID]?.state == .finished {
            threadActivities[tabID]?.state = .idle
        }
        activitiesByThread[threadID] = threadActivities
    }

    private func notifyFinished(threadID: UUID, tabID: UUID, sequence: Int64) {
        let metadata = threadMetadata[threadID]
        let notification = AgentFinishedNotification(
            threadID: threadID,
            tabID: tabID,
            sequence: sequence,
            threadTitle: metadata?.title ?? "Thread",
            workingDirectory: metadata?.workingDirectory
        )

        do {
            try notificationAdapter.notifyAgentFinished(notification)
        } catch {
            NSLog("Fission could not send an agent notification: %@", String(describing: error))
        }
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

private final class AgentActivityReceiver: AgentActivityReportSource, @unchecked Sendable {
    let port: UInt16
    let token = UUID().uuidString

    var environment: [String: String] {
        [
            "FISSION_AGENT_PORT": String(port),
            "FISSION_AGENT_TOKEN": token
        ]
    }

    private let descriptor: Int32
    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "com.fission.agent-activity")
    private var onReport: (@Sendable (Data) -> Void)?

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
            throw POSIXError(.EIO)
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
            throw POSIXError(.EIO)
        }

        self.descriptor = descriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
    }

    func start(onReport: @escaping @Sendable (Data) -> Void) {
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
            onReport?(Data(bytes.prefix(Int(count))))
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
