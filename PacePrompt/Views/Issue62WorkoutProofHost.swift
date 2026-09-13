#if PACEPROMPT_ISSUE62_PROOF
  import SwiftUI
  import UIKit

  @MainActor
  final class Issue62WorkoutProofSessionAuthority: WorkoutProofSessionAuthorizing {
    private let nextSessionID: () -> UUID
    private(set) var activeAuthorization: WorkoutProofSessionAuthorization?

    init(nextSessionID: @escaping () -> UUID = UUID.init) {
      self.nextSessionID = nextSessionID
    }

    var canAuthorize: Bool {
      activeAuthorization == nil
    }

    @discardableResult
    func authorize(_ candidate: WorkoutProofConnectionCandidate) -> Bool {
      guard canAuthorize else { return false }
      let equipment = candidate.equipmentIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !equipment.isEmpty else { return false }
      activeAuthorization = .init(
        sessionID: nextSessionID(),
        peripheralIdentifier: candidate.peripheralIdentifier,
        equipmentIdentity: equipment
      )
      return true
    }

    func invalidateAuthorization() {
      activeAuthorization = nil
    }
  }

  @MainActor
  final class Issue62WorkoutProofCoordinator: ObservableObject {
    struct EvidenceEntry: Identifiable, Equatable {
      let id: Int
      let elapsed: TimeInterval
      let detail: String
    }

    let binding: ProductionWorkoutExecutionBinding
    let authority: Issue62WorkoutProofSessionAuthority
    let plan: WorkoutPlanValidator.ValidatedPlan
    let ceilings = WorkoutSessionCeilings(
      maximumSpeed: .init(value: Decimal(7) / 10, unit: .kilometresPerHour),
      maximumInclination: .init(value: 1, unit: .percent),
      maximumStepSpeedChange: .init(value: Decimal(1) / 10, unit: .kilometresPerHour)
    )

    @Published private(set) var revision = 0
    @Published private(set) var evidence: [EvidenceEntry] = []
    @Published private(set) var notice: String?
    @Published private(set) var explicitDisconnectRecorded = false
    @Published var readiness = WorkoutOperatorReadiness(
      deckClear: false,
      consoleImmediatelyReachable: false,
      safetyKeyImmediatelyReachable: false,
      physicallyStationary: false
    )
    @Published var activityConfirmed = false

    private let treadmill: TreadmillSetupViewModel
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var lastPhase = ""
    private var lastTelemetry: WorkoutTarget?
    private var recordedProcedureCount = 0
    private var lastEpoch: ConnectionEpoch?
    private var sequenceNumber = 0
    private var didBeginCurrentSequence = false
    private var didBeginAnySequence = false
    private var explicitDisconnectCount = 0
    private var lastAuthorizedEpoch: ConnectionEpoch?

    init(
      treadmill: TreadmillSetupViewModel,
      binding: ProductionWorkoutExecutionBinding,
      authority: Issue62WorkoutProofSessionAuthority
    ) {
      self.treadmill = treadmill
      self.binding = binding
      self.authority = authority
      let rawPlan = WorkoutPlan(
        schemaVersion: WorkoutPlanSchema.currentVersion,
        suggestedName: "Issue 62 conservative walking proof",
        activity: .indoorWalking,
        steps: [
          Self.step(.warmUp, "Warm up", seconds: 60, speed: Decimal(5) / 10),
          Self.step(.interval, "Proof interval", seconds: 180, speed: Decimal(6) / 10),
          Self.step(.coolDown, "Cool down", seconds: 60, speed: Decimal(5) / 10),
        ]
      )
      guard
        case .success(let validated) = WorkoutPlanValidator.validate(
          rawPlan,
          against: Self.acceptedCapabilities
        )
      else {
        preconditionFailure("The fixed issue #62 plan must validate against the accepted profile")
      }
      plan = validated
      record("Proof build opened; no treadmill procedure has been authorised in the app")
    }

    var canAuthorizeCurrentConnection: Bool {
      authority.canAuthorize
        && binding.proofConnectionCandidate != nil
        && binding.epoch != lastAuthorizedEpoch
    }

    var canArm: Bool {
      authority.activeAuthorization != nil
        && binding.canExposeArming
        && binding.orchestrator.state.armedWorkout == nil
    }

    var hasArmedWorkout: Bool {
      binding.orchestrator.state.armedWorkout != nil
    }

    var shouldShowExercise: Bool {
      switch binding.orchestrator.state.execution {
      case .waitingForPhysicalStart, .applyingTargets, .runningSegment, .checkingTreadmill,
        .paused, .restoringTargets, .awaitingPhysicalStopForCompletion, .readyToEnd,
        .ending, .finished:
        true
      case .interrupted, .failed:
        didBeginCurrentSequence
      case .idle, .preflight, .acquiringControl:
        false
      }
    }

    var isTerminal: Bool {
      switch binding.orchestrator.state.execution {
      case .finished, .interrupted, .failed: true
      default: false
      }
    }

    var preflightPresentation: WorkoutPreflightPresentation? {
      guard let profile = binding.executionProfile else { return nil }
      return .init(
        context: .init(
          validatedPlan: plan,
          ceilings: ceilings,
          profile: profile,
          executionState: binding.orchestrator.state,
          operatorReadiness: readiness,
          activityConfirmed: activityConfirmed
        ),
        at: SystemWorkoutOrchestrationClock().read().monotonic,
        locale: Locale(identifier: "en_GB")
      )
    }

    var exercisePresentation: WorkoutExercisePresentation {
      .init(
        context: .init(orchestrator: binding.orchestrator),
        at: SystemWorkoutOrchestrationClock().read().monotonic,
        locale: Locale(identifier: "en_GB")
      )
    }

    var markerInstruction: String? {
      switch binding.orchestrator.state.execution {
      case .waitingForPhysicalStart:
        "Tap the marker, then press physical Start. The marker does not control the belt."
      case .runningSegment:
        "Use the marker immediately before the predetermined physical Stop."
      case .paused:
        "Paused is accepted. Tap the resume marker, then press physical Start."
      case .awaitingPhysicalStopForCompletion:
        "The plan is complete. Tap the marker, then press physical Stop."
      default:
        nil
      }
    }

    var markerTitle: String? {
      switch binding.orchestrator.state.execution {
      case .waitingForPhysicalStart: "Record initial Start press"
      case .runningSegment: "Record physical Stop press"
      case .paused: "Record resume Start press"
      case .awaitingPhysicalStopForCompletion: "Record final Stop press"
      default: nil
      }
    }

    func refresh() {
      resetForNewConnectionIfNeeded()
      recordStateChanges()
      revision &+= 1
    }

    func recordLifecycle(_ activity: FTMSApplicationActivity) {
      record("Application lifecycle: \(activity.title)")
    }

    func authorizeCurrentConnection() {
      guard let candidate = binding.proofConnectionCandidate else {
        notice = "The current connection does not yet match the complete accepted passive profile."
        return
      }
      guard authority.authorize(candidate) else {
        notice = "This connection already has an active supervised-session authority."
        return
      }
      lastAuthorizedEpoch = binding.epoch
      notice = nil
      record("Supervised-session authority created for the selected, exact-profile connection")
      binding.tick()
      refresh()
    }

    func armReviewedPlan() {
      guard canArm,
        let result = binding.arm(plan: plan, ceilings: ceilings, sourcePlanID: nil),
        result.reducerDisposition == .accepted
      else {
        notice = "The fixed plan could not be armed; no procedure was sent."
        return
      }
      notice = nil
      record("Fixed plan and ceilings armed after current profile and telemetry checks")
      refresh()
    }

    func handlePreflight(_ intent: WorkoutPreflightIntent) {
      switch intent {
      case .setConfirmation(let kind, let confirmed):
        setConfirmation(kind, confirmed: confirmed)
      case .beginWorkout:
        guard let presentation = preflightPresentation, presentation.canBeginWorkout else {
          notice = "Begin workout remains blocked by current Preflight evidence."
          return
        }
        guard let result = binding.beginWorkout(readiness: readiness),
          result.reducerDisposition == .accepted
        else {
          notice = "Begin workout was rejected before transmission."
          return
        }
        didBeginCurrentSequence = true
        didBeginAnySequence = true
        record(
          "Begin workout accepted; Request Control may be submitted, but belt Start remains physical"
        )
        notice = nil
        refresh()
      }
    }

    func handleExercise(_ intent: WorkoutExerciseIntent) {
      guard let epoch = binding.epoch else {
        notice = "The connection epoch is unavailable; no action was sent."
        return
      }
      switch intent {
      case .setSpeed(let speed):
        let result = binding.handle(.setSpeedOverride(epoch: epoch, speed))
        guard result.reducerDisposition == .accepted else {
          notice =
            "That speed adjustment is unavailable in the current state or outside the session limits."
          return
        }
        record("Manual speed adjustment accepted: \(Self.decimal(speed.value)) km/h")
      case .setInclination(let inclination):
        let result = binding.handle(.setInclinationOverride(epoch: epoch, inclination))
        guard result.reducerDisposition == .accepted else {
          notice =
            "That inclination adjustment is unavailable in the current state or outside the session limits."
          return
        }
        record("Manual inclination adjustment accepted: \(Self.decimal(inclination.value))%")
      case .returnToPlan:
        let result = binding.handle(.returnToPlan(epoch: epoch))
        guard result.reducerDisposition == .accepted else {
          notice = "Return to plan is unavailable in the current state."
          return
        }
        record("Return to the current segment's planned targets accepted")
      case .confirmOperatorStationary:
        record("Operator separately confirmed the treadmill stationary")
        _ = binding.handle(
          .humanConfirmsStationary(
            epoch: epoch,
            note: "Issue #62 operator stationary confirmation"
          )
        )
      case .endWorkout:
        let result = binding.handle(.userEndsWorkout(epoch: epoch))
        guard result.reducerDisposition == .accepted else {
          notice = "End workout requires accepted stationary evidence."
          return
        }
        record("End workout tapped; local finalisation requested with no FTMS Stop procedure")
      }
      notice = nil
      refresh()
    }

    func recordPhysicalConsoleMarker() {
      switch binding.orchestrator.state.execution {
      case .waitingForPhysicalStart:
        record("Operator marker: about to press initial physical Start")
      case .runningSegment:
        record("Operator marker: about to press physical Stop")
      case .paused:
        record("Operator marker: about to press physical Start for resume")
      case .awaitingPhysicalStopForCompletion:
        record("Operator marker: about to press final physical Stop")
      default:
        notice = "No predetermined physical-console marker is available in this state."
        return
      }
      notice = nil
    }

    func disconnect() {
      record("Explicit disconnect requested for the current supervised sequence")
      if !explicitDisconnectRecorded { explicitDisconnectCount += 1 }
      explicitDisconnectRecorded = true
      treadmill.disconnect()
      refresh()
    }

    var sanitizedReport: String {
      var lines = [
        "PacePrompt issue #62 supervised physical-console workout sessions",
        "Evidence boundary: operator-confirmed FR30z sessions; no peripheral identifier or raw packet data included",
        "Plan: 60 s at 0.50 km/h / 0%; 180 s at 0.60 km/h / 0%; 60 s at 0.50 km/h / 0%",
        "Ceilings: 0.70 km/h; 1%; 0.10 km/h planned-step change",
        "Allowed procedures: Request Control, Set Target Speed, Set Target Inclination only",
        "Sequences opened: \(sequenceNumber)",
        "Any executable control phase entered: \(didBeginAnySequence ? "yes" : "no")",
        "Explicit disconnects recorded: \(explicitDisconnectCount)",
        "",
        "Sanitised evidence timeline",
      ]
      lines.append(
        contentsOf: evidence.map { entry in
          String(format: "+%.3f s · %@", entry.elapsed, entry.detail)
        })
      lines.append("")
      if !didBeginAnySequence {
        lines.append("No executable treadmill procedure was initiated in these sessions.")
      }
      lines.append(
        "Human markers are operator statements, not protocol or treadmill telemetry evidence.")
      return lines.joined(separator: "\n")
    }

    private func setConfirmation(
      _ kind: WorkoutPreflightConfirmationKind,
      confirmed: Bool
    ) {
      switch kind {
      case .activity:
        activityConfirmed = confirmed
      case .deckClear:
        readiness = .init(
          deckClear: confirmed,
          consoleImmediatelyReachable: readiness.consoleImmediatelyReachable,
          safetyKeyImmediatelyReachable: readiness.safetyKeyImmediatelyReachable,
          physicallyStationary: readiness.physicallyStationary
        )
      case .consoleReachable:
        readiness = .init(
          deckClear: readiness.deckClear,
          consoleImmediatelyReachable: confirmed,
          safetyKeyImmediatelyReachable: readiness.safetyKeyImmediatelyReachable,
          physicallyStationary: readiness.physicallyStationary
        )
      case .safetyKeyReachable:
        readiness = .init(
          deckClear: readiness.deckClear,
          consoleImmediatelyReachable: readiness.consoleImmediatelyReachable,
          safetyKeyImmediatelyReachable: confirmed,
          physicallyStationary: readiness.physicallyStationary
        )
      case .physicallyStationary:
        readiness = .init(
          deckClear: readiness.deckClear,
          consoleImmediatelyReachable: readiness.consoleImmediatelyReachable,
          safetyKeyImmediatelyReachable: readiness.safetyKeyImmediatelyReachable,
          physicallyStationary: confirmed
        )
      }
      record("Preflight confirmation \(kind.rawValue): \(confirmed ? "yes" : "no")")
    }

    private func recordStateChanges() {
      let state = binding.orchestrator.state
      let phase = Self.phaseDescription(state.execution)
      if phase != lastPhase {
        lastPhase = phase
        record("Execution state: \(phase)")
      }

      while recordedProcedureCount < state.procedureHistory.count {
        let outcome = state.procedureHistory[recordedProcedureCount]
        recordedProcedureCount += 1
        record(Self.procedureDescription(outcome))
      }

      if case .fresh(let sample) = state.telemetry {
        let target = WorkoutTarget(speed: sample.speed, inclination: sample.inclination)
        if target != lastTelemetry {
          lastTelemetry = target
          record(
            "Later treadmill report: \(Self.decimal(sample.speed.value)) km/h, "
              + "\(Self.decimal(sample.inclination.value))%"
          )
        }
      }
    }

    private func resetForNewConnectionIfNeeded() {
      guard let epoch = binding.epoch, epoch != lastEpoch else { return }
      lastEpoch = epoch
      sequenceNumber += 1
      lastPhase = ""
      lastTelemetry = nil
      recordedProcedureCount = 0
      didBeginCurrentSequence = false
      explicitDisconnectRecorded = false
      readiness = .init(
        deckClear: false,
        consoleImmediatelyReachable: false,
        safetyKeyImmediatelyReachable: false,
        physicallyStationary: false
      )
      activityConfirmed = false
      record("Supervised sequence \(sequenceNumber) opened by an explicit connection")
    }

    private func record(_ detail: String) {
      evidence.append(
        .init(
          id: evidence.count + 1,
          elapsed: max(0, ProcessInfo.processInfo.systemUptime - startedAt),
          detail: detail
        )
      )
    }

    private static func step(
      _ kind: WorkoutStepKind,
      _ label: String,
      seconds: Int,
      speed: Decimal
    ) -> WorkoutStep {
      .init(
        kind: kind,
        label: label,
        duration: .init(value: seconds, unit: .seconds),
        targetSpeed: .init(value: speed, unit: .kilometresPerHour),
        targetInclination: .init(value: 0, unit: .percent)
      )
    }

    private static let acceptedCapabilities = WorkoutPlanCapabilities(
      speed: .supported(
        .init(
          minimum: .init(value: Decimal(5) / 10, unit: .kilometresPerHour),
          maximum: .init(value: 20, unit: .kilometresPerHour),
          increment: .init(value: Decimal(1) / 10, unit: .kilometresPerHour)
        )
      ),
      inclination: .supported(
        .init(
          minimum: .init(value: 0, unit: .percent),
          maximum: .init(value: 15, unit: .percent),
          increment: .init(value: 1, unit: .percent)
        )
      )
    )

    private static func phaseDescription(_ phase: WorkoutExecutionPhase) -> String {
      switch phase {
      case .idle: "idle"
      case .preflight: "preflight"
      case .acquiringControl: "acquiring control"
      case .waitingForPhysicalStart: "waiting for physical Start"
      case .applyingTargets: "applying targets"
      case .runningSegment: "running segment"
      case .checkingTreadmill: "checking treadmill"
      case .paused: "paused"
      case .restoringTargets: "restoring targets"
      case .awaitingPhysicalStopForCompletion: "awaiting final physical Stop"
      case .readyToEnd: "ready to End workout"
      case .ending: "ending locally"
      case .finished: "finished"
      case .interrupted: "interrupted"
      case .failed: "failed"
      }
    }

    private static func procedureDescription(_ outcome: WorkoutProcedureOutcome) -> String {
      switch outcome {
      case .acknowledged(let record, let attAt, let ftmsAt):
        let submitted =
          record.submittedAt.map { String(format: "%.3f", $0.seconds) } ?? "unavailable"
        return
          "Procedure \(record.id.sequence) \(intentDescription(record.intent)): submitted at \(submitted), ATT accepted at \(String(format: "%.3f", attAt.seconds)), FTMS acknowledged at \(String(format: "%.3f", ftmsAt.seconds))"
      case .failed(let record, let failure):
        return
          "Procedure \(record.id.sequence) \(intentDescription(record.intent)) failed: \(String(describing: failure))"
      case .timedOutUnknown(let record):
        return
          "Procedure \(record.id.sequence) \(intentDescription(record.intent)) timed out with outcome unknown"
      }
    }

    private static func intentDescription(_ intent: WorkoutControlPointIntent) -> String {
      switch intent {
      case .requestControl: "Request Control"
      case .setTargetSpeed(let speed): "Set Target Speed \(decimal(speed.value)) km/h"
      case .setTargetInclination(let inclination):
        "Set Target Inclination \(decimal(inclination.value))%"
      }
    }

    private static func decimal(_ value: Decimal) -> String {
      NSDecimalNumber(decimal: value).stringValue
    }
  }

  struct Issue62WorkoutProofHost: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel
    @ObservedObject var coordinator: Issue62WorkoutProofCoordinator
    @Environment(\.scenePhase) private var scenePhase

    private let refreshTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
      Group {
        if coordinator.shouldShowExercise {
          exercise
        } else if coordinator.hasArmedWorkout, let presentation = coordinator.preflightPresentation
        {
          WorkoutPreflightView(presentation: presentation, send: coordinator.handlePreflight)
        } else {
          preparation
        }
      }
      .safeAreaInset(edge: .bottom) {
        proofControls
      }
      .onReceive(refreshTimer) { _ in coordinator.refresh() }
      .onAppear { updateLifecycle(scenePhase) }
      .onChange(of: scenePhase) { _, phase in updateLifecycle(phase) }
    }

    private var preparation: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Label("Reusable supervised sessions", systemImage: "exclamationmark.shield.fill")
              .font(.title2.bold())
              .foregroundStyle(.orange)
            Text(
              "The physical console and safety key remain authoritative. Each explicit connection may create one supervised authority for Request Control plus repeated in-range speed and inclination actions."
            )
            .font(.callout)

            GroupBox("Fixed plan and ceilings") {
              VStack(alignment: .leading, spacing: 6) {
                Text("1:00 · 0.50 km/h · 0%")
                Text("3:00 · 0.60 km/h · 0%")
                Text("1:00 · 0.50 km/h · 0%")
                Divider()
                Text("Maximum 0.70 km/h · 1% · 0.10 km/h planned-step change")
                  .font(.footnote)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }

            NavigationLink {
              TreadmillSetupView(treadmill: treadmill)
            } label: {
              Label("Scan, connect and inspect FR30z", systemImage: "dot.radiowaves.left.and.right")
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)

            statusCard

            if coordinator.authority.activeAuthorization == nil {
              Button("Authorise this exact connection") {
                coordinator.authorizeCurrentConnection()
              }
              .buttonStyle(.borderedProminent)
              .tint(.orange)
              .disabled(!coordinator.canAuthorizeCurrentConnection)
            } else if coordinator.canArm {
              Button("Arm reviewed fixed plan") { coordinator.armReviewedPlan() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
              ProgressView("Waiting for exact profile, indications and fresh complete telemetry")
            }
          }
          .padding(20)
        }
        .navigationTitle("Issue #62 sessions")
      }
    }

    private var exercise: some View {
      WorkoutExerciseView(
        presentation: coordinator.exercisePresentation,
        send: coordinator.handleExercise
      )
    }

    @ViewBuilder
    private var proofControls: some View {
      if let notice = coordinator.notice {
        Text(notice)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.red)
          .padding(10)
          .frame(maxWidth: .infinity)
          .background(.ultraThinMaterial)
      }
      if let title = coordinator.markerTitle {
        VStack(spacing: 4) {
          if let instruction = coordinator.markerInstruction {
            Text(instruction)
              .font(.caption)
              .multilineTextAlignment(.center)
          }
          Button(title) { coordinator.recordPhysicalConsoleMarker() }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
      } else if coordinator.isTerminal {
        VStack(spacing: 8) {
          ShareLink(item: coordinator.sanitizedReport) {
            Label("Share sanitised session report", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(.borderedProminent)
          Button("Explicitly disconnect") { coordinator.disconnect() }
            .buttonStyle(.bordered)
            .disabled(coordinator.explicitDisconnectRecorded)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
      }
    }

    private var statusCard: some View {
      VStack(alignment: .leading, spacing: 6) {
        Text("Current gate").font(.headline)
        Text("Connection: \(treadmill.connectionState.title)")
        Text(
          coordinator.canAuthorizeCurrentConnection
            ? "Exact passive profile is ready for supervised authorisation."
            : "No current exact passive-profile candidate."
        )
        .foregroundStyle(coordinator.canAuthorizeCurrentConnection ? .green : .secondary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func updateLifecycle(_ phase: ScenePhase) {
      let activity: FTMSApplicationActivity
      switch phase {
      case .active: activity = .active
      case .inactive: activity = .inactive
      case .background: activity = .background
      @unknown default: activity = .unknown
      }
      treadmill.setApplicationActivity(activity)
      coordinator.recordLifecycle(activity)
    }
  }
#endif
