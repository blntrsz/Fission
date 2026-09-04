import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

@MainActor
// swiftlint:disable:next type_body_length
struct AgentActivityModelTests {
    @Test func rejectsMalformedUnauthorizedAndUnregisteredReports() async {
        let source = StubAgentActivityReportSource()
        let notifications = RecordingAgentActivityNotificationAdapter()
        let model = makeModel(source: source, notifications: notifications)
        let registeredThreadID = UUID()
        let registeredTabID = UUID()
        _ = model.environment(threadID: registeredThreadID, tabID: registeredTabID)

        source.send(Data("not json".utf8))
        source.send(reportData(
            token: "wrong-token",
            threadID: registeredThreadID,
            tabID: registeredTabID,
            state: .running,
            sequence: 1
        ))
        source.send(reportData(
            token: source.token,
            threadID: UUID(),
            tabID: UUID(),
            state: .running,
            sequence: 1
        ))
        await Task.yield()

        #expect(model.activities(for: registeredThreadID).isEmpty)
        #expect(notifications.notifications.isEmpty)
    }

    @Test func ignoresOlderReports() async {
        let source = StubAgentActivityReportSource()
        let model = makeModel(source: source)
        let threadID = UUID()
        let tabID = UUID()
        _ = model.environment(threadID: threadID, tabID: tabID)

        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .running,
            sequence: 2
        ))
        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .finished,
            sequence: 1
        ))
        await Task.yield()

        #expect(model.activities(for: threadID) == [tabID: .running])
    }

    @Test func preservesFinishedActivityBesideRunningActivity() async {
        let source = StubAgentActivityReportSource()
        let notifications = RecordingAgentActivityNotificationAdapter()
        let model = makeModel(source: source, notifications: notifications)
        let threadID = UUID()
        let runningTabID = UUID()
        let finishedTabID = UUID()
        _ = model.environment(threadID: threadID, tabID: runningTabID)
        _ = model.environment(threadID: threadID, tabID: finishedTabID)

        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: runningTabID,
            state: .running,
            sequence: 1
        ))
        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: finishedTabID,
            state: .finished,
            sequence: 1
        ))
        await Task.yield()

        #expect(model.activities(for: threadID) == [
            runningTabID: .running,
            finishedTabID: .finished
        ])
        #expect(notifications.notifications.count == 1)
    }

    @Test func selectedThreadImmediatelyAcknowledgesEveryFinishedTab() async {
        let source = StubAgentActivityReportSource()
        let model = makeModel(source: source)
        let threadID = UUID()
        let runningTabID = UUID()
        let finishedTabID = UUID()
        _ = model.environment(threadID: threadID, tabID: runningTabID)
        _ = model.environment(threadID: threadID, tabID: finishedTabID)

        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: runningTabID,
            state: .running,
            sequence: 1
        ))
        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: finishedTabID,
            state: .finished,
            sequence: 1
        ))
        await Task.yield()
        model.updateAttention(selectedThreadID: threadID, isAppActive: true)

        #expect(model.activities(for: threadID) == [
            runningTabID: .running,
            finishedTabID: .idle
        ])
    }

    @Test func suppressesNotificationOnlyForActiveSelectedThread() async {
        let source = StubAgentActivityReportSource()
        let notifications = RecordingAgentActivityNotificationAdapter()
        let model = makeModel(source: source, notifications: notifications)
        let selectedThreadID = UUID()
        let selectedTabID = UUID()
        let otherThreadID = UUID()
        let otherTabID = UUID()
        _ = model.environment(threadID: selectedThreadID, tabID: selectedTabID)
        _ = model.environment(threadID: otherThreadID, tabID: otherTabID)
        model.updateAttention(selectedThreadID: selectedThreadID, isAppActive: true)

        source.send(reportData(
            token: source.token,
            threadID: selectedThreadID,
            tabID: selectedTabID,
            state: .finished,
            sequence: 1
        ))
        source.send(reportData(
            token: source.token,
            threadID: otherThreadID,
            tabID: otherTabID,
            state: .finished,
            sequence: 1
        ))
        await Task.yield()

        #expect(model.activities(for: selectedThreadID) == [selectedTabID: .idle])
        #expect(notifications.notifications.map(\.threadID) == [otherThreadID])
    }

    @Test func inactiveSelectedThreadNotifiesAndAcknowledges() async {
        let source = StubAgentActivityReportSource()
        let notifications = RecordingAgentActivityNotificationAdapter()
        let model = makeModel(source: source, notifications: notifications)
        let threadID = UUID()
        let tabID = UUID()
        _ = model.environment(threadID: threadID, tabID: tabID)
        model.updateAttention(selectedThreadID: threadID, isAppActive: false)

        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .finished,
            sequence: 1
        ))
        await Task.yield()

        #expect(model.activities(for: threadID) == [tabID: .idle])
        #expect(notifications.notifications.count == 1)
    }

    @Test func repeatedFinishedStateNotifiesOnceUntilActivityRunsAgain() async {
        let source = StubAgentActivityReportSource()
        let notifications = RecordingAgentActivityNotificationAdapter()
        let model = makeModel(source: source, notifications: notifications)
        let threadID = UUID()
        let tabID = UUID()
        _ = model.environment(threadID: threadID, tabID: tabID)
        model.updateAttention(selectedThreadID: threadID, isAppActive: false)

        for (state, sequence) in [
            (AgentActivityState.finished, Int64(1)),
            (.finished, 2),
            (.running, 3),
            (.finished, 4)
        ] {
            source.send(reportData(
                token: source.token,
                threadID: threadID,
                tabID: tabID,
                state: state,
                sequence: sequence
            ))
        }
        await Task.yield()

        #expect(notifications.notifications.map(\.sequence) == [1, 4])
    }

    @Test func forgettingTabRejectsLateReports() async {
        let source = StubAgentActivityReportSource()
        let model = makeModel(source: source)
        let threadID = UUID()
        let tabID = UUID()
        _ = model.environment(threadID: threadID, tabID: tabID)

        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .running,
            sequence: 1
        ))
        await Task.yield()
        model.forget(threadID: threadID, tabID: tabID)
        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .finished,
            sequence: 2
        ))
        await Task.yield()

        #expect(model.activities(for: threadID).isEmpty)
    }

    @Test func forgettingThreadRejectsLateReportsAndReopeningStartsIdle() async {
        let source = StubAgentActivityReportSource()
        let model = makeModel(source: source)
        let threadID = UUID()
        let tabID = UUID()
        _ = model.environment(threadID: threadID, tabID: tabID)
        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .running,
            sequence: 1
        ))
        await Task.yield()

        model.forget(threadID: threadID)
        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .finished,
            sequence: 2
        ))
        await Task.yield()

        #expect(model.activities(for: threadID).isEmpty)
        let newTabID = UUID()
        _ = model.environment(threadID: threadID, tabID: newTabID)
        #expect(model.activities(for: threadID).isEmpty)
    }

    @Test func usesThreadMetadataAndFallsBackWhenMissing() async {
        let source = StubAgentActivityReportSource()
        let notifications = RecordingAgentActivityNotificationAdapter()
        let model = makeModel(source: source, notifications: notifications)
        let knownThread = AgentThread(title: "Architecture review", workingDirectory: "/tmp/Fission")
        let knownTabID = UUID()
        let unknownThreadID = UUID()
        let unknownTabID = UUID()
        model.synchronizeThreads([knownThread])
        _ = model.environment(threadID: knownThread.id, tabID: knownTabID)
        _ = model.environment(threadID: unknownThreadID, tabID: unknownTabID)

        source.send(reportData(
            token: source.token,
            threadID: knownThread.id,
            tabID: knownTabID,
            state: .finished,
            sequence: 1
        ))
        source.send(reportData(
            token: source.token,
            threadID: unknownThreadID,
            tabID: unknownTabID,
            state: .finished,
            sequence: 1
        ))
        await Task.yield()

        #expect(notifications.notifications.map(\.threadTitle) == ["Architecture review", "Thread"])
        #expect(notifications.notifications.first?.workingDirectory == "/tmp/Fission")
    }

    @Test func notificationFailureDoesNotChangeActivity() async {
        let source = StubAgentActivityReportSource()
        let notifications = RecordingAgentActivityNotificationAdapter(shouldThrow: true)
        let model = makeModel(source: source, notifications: notifications)
        let threadID = UUID()
        let tabID = UUID()
        _ = model.environment(threadID: threadID, tabID: tabID)

        source.send(reportData(
            token: source.token,
            threadID: threadID,
            tabID: tabID,
            state: .finished,
            sequence: 1
        ))
        await Task.yield()

        #expect(model.activities(for: threadID) == [tabID: .finished])
    }

    private func makeModel(
        source: StubAgentActivityReportSource,
        notifications: RecordingAgentActivityNotificationAdapter = .init()
    ) -> AgentActivityModel {
        AgentActivityModel(
            installPiIntegration: false,
            reportSource: source,
            notificationAdapter: notifications
        )
    }

    private func reportData(
        token: String,
        threadID: UUID,
        tabID: UUID,
        state: AgentActivityState,
        sequence: Int64
    ) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: [
            "version": 1,
            "token": token,
            "threadId": threadID.uuidString,
            "tabId": tabID.uuidString,
            "agent": "pi",
            "state": state.rawValue,
            "sequence": sequence
        ])
    }
}

private final class StubAgentActivityReportSource: AgentActivityReportSource, @unchecked Sendable {
    let token = "test-token"
    let environment = [
        "FISSION_AGENT_PORT": "1234",
        "FISSION_AGENT_TOKEN": "test-token"
    ]

    private var onReport: (@Sendable (Data) -> Void)?

    func start(onReport: @escaping @Sendable (Data) -> Void) {
        self.onReport = onReport
    }

    func send(_ data: Data) {
        onReport?(data)
    }
}

// swiftlint:disable:next type_name
private final class RecordingAgentActivityNotificationAdapter: AgentActivityNotificationAdapter,
    @unchecked Sendable {
    enum Failure: Error {
        case deliveryFailed
    }

    private(set) var notifications: [AgentFinishedNotification] = []
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func notifyAgentFinished(_ notification: AgentFinishedNotification) throws {
        if shouldThrow { throw Failure.deliveryFailed }
        notifications.append(notification)
    }
}
