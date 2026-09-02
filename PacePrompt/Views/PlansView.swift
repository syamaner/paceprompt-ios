import SwiftUI

struct PlansView: View {
    var body: some View {
        ContentUnavailableView(
            "No plans yet",
            systemImage: "list.bullet.rectangle",
            description: Text("Workout plans belong to a later authorised slice.")
        )
        .navigationTitle("Plans")
    }
}
