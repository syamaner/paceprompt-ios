import SwiftUI

struct EvaluationReadinessView: View {
    private let readiness = EvaluationLaunchReadiness.current()

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    switch readiness {
                    case let .ready(provider, details):
                        Label("Ready: \(provider)", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        ForEach(details, id: \.self) { Text($0) }
                    case let .notReady(reasons):
                        Label("Not ready", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        ForEach(reasons, id: \.self) { Text($0) }
                    }
                }
                Section("Boundary") {
                    Text("This developer-only target accepts only the checked-in synthetic corpus.")
                    Text("No model, repetition count, spending limit, comparison rule, fallback, or provider decision is selected by the app.")
                    Text("A ready state does not claim that inference, quality, latency, energy, thermal behaviour, or offline operation has been validated.")
                }
            }
            .navigationTitle("Workout Import Evaluation")
        }
    }
}
