@testable import FissionDesktop
import Foundation
import Testing

@MainActor
struct DesktopNavigationModelTests {
    @Test func requestedThreadIsSelectedWhenItBecomesAvailable() {
        let requestedID = UUID()
        let fallbackID = UUID()
        let model = DesktopNavigationModel()

        model.open(threadID: requestedID)
        model.synchronize(availableThreadIDs: [])
        model.synchronize(availableThreadIDs: [fallbackID, requestedID])

        #expect(model.selectedThreadID == requestedID)
        #expect(model.requestedThreadID == nil)
    }

    @Test func openingAvailableThreadClearsPendingRequest() {
        let threadID = UUID()
        let model = DesktopNavigationModel()

        model.open(threadID: threadID)
        model.didOpen(threadID: threadID)

        #expect(model.selectedThreadID == threadID)
        #expect(model.requestedThreadID == nil)
    }

    @Test func synchronizationSelectsFirstAvailableThread() {
        let firstID = UUID()
        let model = DesktopNavigationModel()

        model.synchronize(availableThreadIDs: [firstID, UUID()])

        #expect(model.selectedThreadID == firstID)
    }
}
