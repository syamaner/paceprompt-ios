import SwiftUI

struct HistoryView: View {
    @StateObject private var model: HistoryLibraryViewModel

    @MainActor
    init() {
#if DEBUG
        if let configured = HistoryLibraryUITestConfiguration.makeViewModelIfRequested() {
            _model = StateObject(wrappedValue: configured)
            return
        }
#endif
        let history = WorkoutHistoryRepository()
        _model = StateObject(
            wrappedValue: HistoryLibraryViewModel(
                history: history,
                healthStore: HealthKitWorkoutStore()
            )
        )
    }

    var body: some View {
        Group {
            switch model.presentation.content {
            case .loading:
                ProgressView("Loading workout history")
                    .accessibilityIdentifier("history.loading")
            case .empty:
                ContentUnavailableView(
                    "No workout history",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed and interrupted workout attempts will remain on this iPhone.")
                )
                .accessibilityIdentifier("history.empty")
            case let .populated(rows):
                historyList(rows)
            case let .blocked(message):
                blockedView(message)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .task { model.reload() }
    }

    private func historyList(_ rows: [HistoryWorkoutRow]) -> some View {
        List {
            if let warning = model.presentation.warning {
                Section {
                    HistoryRepositoryMessageCard(message: warning) { model.reload() }
                        .accessibilityIdentifier("history.staging-warning")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(rows) { row in
                    NavigationLink {
                        HistoryWorkoutDetailView(summaryID: row.id, model: model)
                    } label: {
                        HistoryWorkoutRowView(row: row)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(row.accessibilityValue)
                    .accessibilityHint("Opens workout details")
                    .accessibilityIdentifier("history.record.\(row.id.uuidString)")
                }
            } header: {
                Text("Newest first")
            }
        }
        .listStyle(.plain)
    }

    private func blockedView(_ message: HistoryRepositoryMessage) -> some View {
        ScrollView {
            HistoryRepositoryMessageCard(message: message) { model.reload() }
                .padding()
        }
    }
}

private struct HistoryWorkoutRowView: View {
    let row: HistoryWorkoutRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.headline)
                Spacer()
                Text(row.duration).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("\(row.outcome) · \(row.activity)")
                .font(.subheadline)
            Text("\(row.date) · \(row.distance)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(row.health, systemImage: "heart")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct HistoryWorkoutDetailView: View {
    let summaryID: UUID
    @ObservedObject var model: HistoryLibraryViewModel
    @State private var showingHealthConfirmation = false
    @State private var showingRepeatReview = false

    var body: some View {
        Group {
            if let detail = model.detail(for: summaryID) {
                detailList(detail)
                    .navigationTitle(detail.title)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Repeat") { showingRepeatReview = true }
                                .accessibilityIdentifier("history.repeat")
                        }
                    }
                    .sheet(isPresented: $showingRepeatReview) {
                        if let plan = model.planSnapshot(for: summaryID) {
                            HistoryRepeatReviewView(plan: plan)
                        }
                    }
                    .alert(
                        detail.health.confirmationTitle ?? "Save to Apple Health?",
                        isPresented: $showingHealthConfirmation
                    ) {
                        Button("Cancel", role: .cancel) {}
                        Button("Save") { Task { await model.save(summaryID: summaryID) } }
                    } message: {
                        Text(detail.health.confirmationMessage ?? "")
                    }
            } else {
                ContentUnavailableView(
                    "Workout unavailable",
                    systemImage: "exclamationmark.circle",
                    description: Text("The workout changed or history became unavailable. Return to History and retry.")
                )
            }
        }
    }

    private func detailList(_ detail: HistoryWorkoutDetail) -> some View {
        List {
            Section {
                Label(detail.outcome, systemImage: outcomeSymbol(detail.outcome))
                    .font(.headline)
                    .accessibilityIdentifier("history.detail.outcome")
                Text(detail.activityAndDate).foregroundStyle(.secondary)
            }

            Section("Summary") {
                LabeledContent("Duration", value: detail.duration)
                LabeledContent("Distance", value: detail.distance)
                LabeledContent("Progress", value: detail.progress)
            }

            Section("Prescribed plan") {
                ForEach(detail.prescribed) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(segment.title).font(.subheadline.weight(.semibold))
                        Text("\(segment.duration) · \(segment.targets)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Executed intervals") {
                if let unavailable = detail.executionUnavailable {
                    Text(unavailable)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("history.execution-unavailable")
                } else {
                    ForEach(detail.executed) { interval in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(interval.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(interval.timing).font(.caption.monospacedDigit())
                            }
                            Text(interval.prescribed)
                            Text(interval.effective)
                            Text(interval.observed)
                            Text(interval.ended)
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("history.executed.\(interval.id)")
                    }
                }
            }

            Section("Apple Health") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: detail.health.symbol)
                        .foregroundStyle(detail.health.title == "Saved to Apple Health" ? .green : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(detail.health.title).font(.headline)
                        Text(detail.health.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("history.health.status")
                    }
                }
                if let action = detail.health.actionTitle {
                    Button(action) { showingHealthConfirmation = true }
                        .disabled(model.savingSummaryID != nil)
                        .accessibilityIdentifier("history.health.save")
                }
            }

            Section {
                Button("Export JSON") {}
                    .disabled(true)
                    .accessibilityIdentifier("history.export-json")
                Button("Delete", role: .destructive) {}
                    .disabled(true)
                    .accessibilityIdentifier("history.delete")
            } footer: {
                Text("Workout JSON export and deletion are not available in this version.")
            }
        }
    }

    private func outcomeSymbol(_ outcome: String) -> String {
        switch outcome {
        case "Completed": "checkmark.circle.fill"
        case "Ended by you": "stop.circle.fill"
        case "Interrupted": "pause.circle.fill"
        case "Failed": "xmark.circle.fill"
        case "Physically uncertain": "exclamationmark.triangle.fill"
        default: "clock.badge.exclamationmark"
        }
    }
}

private struct HistoryRepeatReviewView: View {
    let plan: WorkoutPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Activity", value: plan.activity == .indoorWalking ? "Indoor walking" : "Indoor running")
                    LabeledContent("Segments", value: "\(plan.steps.count)")
                }
                Section("Immutable plan snapshot") {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(step.label)").font(.headline)
                            Text("\(step.duration.value) s · \(NSDecimalNumber(decimal: step.targetSpeed.value).stringValue) km/h · \(NSDecimalNumber(decimal: step.targetInclination.value).stringValue)%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("Review only. This does not arm, connect to or operate a treadmill, and it does not create or save a new plan.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Repeat \(plan.suggestedName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct HistoryRepositoryMessageCard: View {
    let message: HistoryRepositoryMessage
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.symbol).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(message.title).font(.headline)
                Text(message.detail).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("history.retry")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var tint: Color {
        switch message.tone {
        case .neutral: .secondary
        case .warning: .orange
        case .failure: .red
        }
    }
}
