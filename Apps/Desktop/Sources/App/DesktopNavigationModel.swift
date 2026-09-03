import Foundation
import Observation

@MainActor
@Observable
final class DesktopNavigationModel {
    var selectedThreadID: UUID?
    private(set) var requestedThreadID: UUID?

    func open(threadID: UUID) {
        requestedThreadID = threadID
        selectedThreadID = threadID
    }

    func select(threadID: UUID?) {
        requestedThreadID = nil
        selectedThreadID = threadID
    }

    func didOpen(threadID: UUID) {
        if requestedThreadID == threadID {
            requestedThreadID = nil
        }
    }

    func synchronize(availableThreadIDs: [UUID]) {
        if let requestedThreadID {
            guard availableThreadIDs.contains(requestedThreadID) else { return }
            selectedThreadID = requestedThreadID
            self.requestedThreadID = nil
            return
        }

        if let selectedThreadID, availableThreadIDs.contains(selectedThreadID) {
            return
        }
        selectedThreadID = availableThreadIDs.first
    }
}
