import SwiftUI
@main struct SyntheticCompanion: App {
    init() {
        #if targetEnvironment(simulator)
        precondition(ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == "__PHONE_UDID__", "Dedicated synthetic simulator only")
        #else
        fatalError("Simulator only")
        #endif
    }
    var body: some Scene { WindowGroup { Text("Synthetic Companion — no Health writes or Bluetooth") } }
}
