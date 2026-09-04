import AppKit
import Foundation
import UserNotifications

struct NotificationPreferences {
    static let agentTaskFinishedKey = "notifications.agentTaskFinished"
}

final class AgentTaskNotificationCoordinator: NSObject, AgentActivityNotificationAdapter,
    UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let threadIDKey = "threadID"

    private let center: UNUserNotificationCenter
    private let openThread: @MainActor @Sendable (UUID) -> Void

    init(
        center: UNUserNotificationCenter = .current(),
        openThread: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        self.center = center
        self.openThread = openThread
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("Fission could not request notification authorization: %@", String(describing: error))
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func notifyAgentFinished(_ notification: AgentFinishedNotification) {
        guard UserDefaults.standard.bool(forKey: NotificationPreferences.agentTaskFinishedKey) else {
            return
        }

        Task {
            let status = await authorizationStatus()
            guard status == .authorized || status == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "\"\(notification.threadTitle)\" finished"
            if let projectName = Self.projectName(for: notification.workingDirectory) {
                content.body = projectName
            }
            content.sound = .default
            content.userInfo = [Self.threadIDKey: notification.threadID.uuidString]

            let identifier = [
                "agent-finished",
                notification.threadID.uuidString,
                notification.tabID.uuidString,
                String(notification.sequence)
            ].joined(separator: ".")

            do {
                try await center.add(UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: nil
                ))
            } catch {
                NSLog("Fission could not send an agent notification: %@", String(describing: error))
            }
        }
    }

    private static func projectName(for workingDirectory: String?) -> String? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return name.isEmpty ? workingDirectory : name
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let rawThreadID = response.notification.request.content.userInfo[Self.threadIDKey]
                as? String,
              let threadID = UUID(uuidString: rawThreadID) else {
            return
        }

        Task { @MainActor [openThread] in
            openThread(threadID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
