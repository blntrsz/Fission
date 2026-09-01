import FissionCore
import SwiftUI

@main
struct FissionMobileApp: App {
    @State private var threadListModel = ThreadListModel(
        databasePath: ThreadListModel.applicationSupportDatabasePath
    )

    var body: some Scene {
        WindowGroup {
            ThreadListView(model: threadListModel)
        }
    }
}
