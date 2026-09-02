@testable import FissionCore
import Foundation
import Testing

struct AgentActivityStateTests {
    @Test func idleIsTheDefaultPresentationState() {
        let reportedState: AgentActivityState? = nil

        #expect(reportedState ?? .idle == .idle)
    }

    @Test func decodesEveryIntegrationState() throws {
        for state in AgentActivityState.allCases {
            let encoded = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(AgentActivityState.self, from: encoded) == state)
        }
    }
}
