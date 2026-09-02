import SwiftUI

@main
struct PacePromptApp: App {
    @StateObject private var treadmill = TreadmillSetupViewModel()

    var body: some Scene {
        WindowGroup {
            RootTabView(treadmill: treadmill)
        }
    }
}
