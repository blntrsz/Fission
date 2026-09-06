import FissionCore
@testable import FissionDesktop
import Foundation
import Testing

struct ActiveThreadSearchTests {
    @Test func emptyQueryReturnsNonSettledThreadsInOriginalOrder() {
        let first = AgentThread(title: "First", status: .completed)
        let settled = AgentThread(title: "Settled", status: .settled)
        let second = AgentThread(title: "Second", status: .active)

        let results = ActiveThreadSearch.results(
            matching: "",
            in: [first, settled, second]
        )

        #expect(results.map(\.id) == [first.id, second.id])
    }

    @Test func queryMatchesTitleAndDirectoryCaseInsensitively() {
        let titleMatch = AgentThread(title: "Fix Login Flow")
        let pathMatch = AgentThread(
            title: "Documentation",
            workingDirectory: "/Users/example/Projects/Payments"
        )
        let unrelated = AgentThread(title: "Release Notes")

        #expect(
            ActiveThreadSearch.results(
                matching: "LOGIN",
                in: [titleMatch, pathMatch, unrelated]
            ).map(\.id) == [titleMatch.id]
        )
        #expect(
            ActiveThreadSearch.results(
                matching: "payments",
                in: [titleMatch, pathMatch, unrelated]
            ).map(\.id) == [pathMatch.id]
        )
    }

    @Test func everySearchTermMustMatch() {
        let matching = AgentThread(
            title: "Fix authentication",
            workingDirectory: "/Projects/WebClient"
        )
        let partial = AgentThread(title: "Fix authentication")

        let results = ActiveThreadSearch.results(
            matching: "auth web",
            in: [matching, partial]
        )

        #expect(results.map(\.id) == [matching.id])
    }
}
