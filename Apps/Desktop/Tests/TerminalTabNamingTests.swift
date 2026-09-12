@testable import FissionDesktop
import Testing

struct TerminalTabNamingTests {
    @Test func firstTabUsesNumberOne() {
        #expect(TerminalTabNaming.nextNumber(existingTitles: []) == 1)
        #expect(TerminalTabNaming.title(for: 1) == "Tab 1")
    }

    @Test func reusesLowestMissingDefaultName() {
        #expect(
            TerminalTabNaming.nextNumber(existingTitles: ["Tab 2", "Tab 3"]) == 1
        )
        #expect(
            TerminalTabNaming.nextNumber(existingTitles: ["Tab 1", "Tab 3"]) == 2
        )
        #expect(
            TerminalTabNaming.nextNumber(existingTitles: ["Tab 1", "Tab 2"]) == 3
        )
    }

    @Test func customTitlesDoNotOccupyDefaultNumbers() {
        #expect(
            TerminalTabNaming.nextNumber(existingTitles: ["Logs", "Tab 2"]) == 1
        )
        #expect(
            TerminalTabNaming.nextNumber(existingTitles: ["Tab 1 extra", "Tab 01"]) == 1
        )
    }
}
