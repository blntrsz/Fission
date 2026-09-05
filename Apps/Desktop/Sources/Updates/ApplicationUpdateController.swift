import AppKit
import Sparkle

/// Process-wide entry point for application updates.
///
/// Sparkle owns discovery, signature verification, installation, and relaunch.
/// Fission deliberately starts with Sparkle's standard UI; a custom presentation
/// can be layered on later without changing the release protocol.
@MainActor
final class ApplicationUpdateController {
    private let updaterController: SPUStandardUpdaterController?

    var isConfigured: Bool {
        updaterController != nil
    }

    init(bundle: Bundle = .main) {
        guard Self.hasProductionConfiguration(in: bundle) else {
            updaterController = nil
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard let updaterController else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Updates are unavailable in this build"
            alert.informativeText = "Install an official Fission release to receive automatic updates."
            alert.runModal()
            return
        }

        updaterController.checkForUpdates(nil)
    }

    private static func hasProductionConfiguration(in bundle: Bundle) -> Bool {
        guard
            let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let feedURL = URL(string: feed),
            feedURL.scheme == "https",
            let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !publicKey.isEmpty
        else {
            return false
        }

        return true
    }
}
