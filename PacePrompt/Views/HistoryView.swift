import SwiftUI

struct HistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "No history yet",
            systemImage: "clock.arrow.circlepath",
            description: Text("PacePrompt does not store workout history in this version.")
        )
        .navigationTitle("History")
    }
}
