import SwiftUI

struct HistoryView: View {
    @StateObject private var model: HistoryHealthExportViewModel
    @State private var showingConfirmation = false

    @MainActor
    init() {
#if DEBUG
        if let configured = HistoryHealthExportUITestConfiguration.makeViewModelIfRequested() {
            _model = StateObject(wrappedValue: configured)
            return
        }
#endif
        let history = WorkoutHistoryRepository()
        _model = StateObject(
            wrappedValue: HistoryHealthExportViewModel(
                history: history,
                healthStore: HealthKitWorkoutStore()
            )
        )
    }

    var body: some View {
        Group {
            if let presentation = model.presentation {
                List {
                    Section("Latest eligible workout") {
                        LabeledContent("Workout", value: presentation.title)
                        LabeledContent("Outcome", value: presentation.outcome)
                        LabeledContent("Activity", value: presentation.activity)
                        LabeledContent("When", value: presentation.timing)
                        LabeledContent("Active duration", value: presentation.duration)
                        LabeledContent("Distance", value: presentation.distance)
                        LabeledContent("Intervals", value: presentation.intervalCount)
                    }
                    Section("Apple Health") {
                        Text(presentation.status)
                            .accessibilityIdentifier("history.health.status")
                        if let action = presentation.actionTitle {
                            Button(action) { showingConfirmation = true }
                                .accessibilityIdentifier("history.health.save")
                        }
                    }
                }
                .alert(presentation.confirmationTitle, isPresented: $showingConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { Task { await model.save() } }
                } message: {
                    Text(presentation.confirmationMessage)
                }
            } else {
                ContentUnavailableView(
                    "No workout ready to save",
                    systemImage: "heart.text.square",
                    description: Text("Complete an eligible workout to save it deliberately to Apple Health.")
                )
            }
        }
        .navigationTitle("History")
    }
}
