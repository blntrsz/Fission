import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    let coordinator: AgentTaskNotificationCoordinator

    @AppStorage(NotificationPreferences.agentTaskFinishedKey)
    private var notifyWhenAgentFinishes = false
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Toggle("Notify when an agent task finishes", isOn: $notifyWhenAgentFinishes)
                .onChange(of: notifyWhenAgentFinishes) { _, isEnabled in
                    guard isEnabled else { return }
                    Task {
                        let granted = await coordinator.requestAuthorization()
                        authorizationStatus = await coordinator.authorizationStatus()
                        if !granted {
                            notifyWhenAgentFinishes = false
                        }
                    }
                }

            if authorizationStatus == .denied {
                Text("Notifications are disabled for Fission in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .task {
            authorizationStatus = await coordinator.authorizationStatus()
        }
    }
}
