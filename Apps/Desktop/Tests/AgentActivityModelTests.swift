@testable import FissionDesktop
import Foundation
import Testing

@MainActor
struct AgentActivityModelTests {
    @Test func finishedTransitionEmitsOneEvent() {
        let threadID = UUID()
        let tabID = UUID()
        var events: [AgentFinishedEvent] = []
        let model = AgentActivityModel(installPiIntegration: false) { events.append($0) }

        model.record(state: .running, threadID: threadID, tabID: tabID, sequence: 1)
        model.record(state: .finished, threadID: threadID, tabID: tabID, sequence: 2)
        model.record(state: .finished, threadID: threadID, tabID: tabID, sequence: 3)

        #expect(events == [AgentFinishedEvent(threadID: threadID, tabID: tabID, sequence: 2)])
    }

    @Test func olderReportsDoNotEmitFinishedEvents() {
        let threadID = UUID()
        let tabID = UUID()
        var events: [AgentFinishedEvent] = []
        let model = AgentActivityModel(installPiIntegration: false) { events.append($0) }

        model.record(state: .running, threadID: threadID, tabID: tabID, sequence: 2)
        model.record(state: .finished, threadID: threadID, tabID: tabID, sequence: 1)

        #expect(events.isEmpty)
        #expect(model.state(for: threadID) == .running)
    }

    @Test func finishedTabEmitsWhileAnotherTabIsRunning() {
        let threadID = UUID()
        let runningTabID = UUID()
        let finishedTabID = UUID()
        var events: [AgentFinishedEvent] = []
        let model = AgentActivityModel(installPiIntegration: false) { events.append($0) }

        model.record(state: .running, threadID: threadID, tabID: runningTabID, sequence: 1)
        model.record(state: .running, threadID: threadID, tabID: finishedTabID, sequence: 1)
        model.record(state: .finished, threadID: threadID, tabID: finishedTabID, sequence: 2)

        #expect(events.count == 1)
        #expect(model.state(for: threadID) == .running)
        #expect(model.states(for: threadID).count == 2)
        #expect(model.states(for: threadID).contains(.running))
        #expect(model.states(for: threadID).contains(.finished))
    }

    @Test func exposesAtMostTenAgentStates() {
        let threadID = UUID()
        let model = AgentActivityModel(installPiIntegration: false)

        for sequence in 1 ... 12 {
            model.record(
                state: .running,
                threadID: threadID,
                tabID: UUID(),
                sequence: Int64(sequence)
            )
        }

        #expect(model.states(for: threadID).count == 10)
    }
}
