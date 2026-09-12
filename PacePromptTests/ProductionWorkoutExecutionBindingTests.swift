import Foundation
import XCTest

@testable import PacePrompt

@MainActor
final class ProductionWorkoutExecutionBindingTests: XCTestCase {
  func testProductionDefaultRemainsPassiveWithoutSeparateProofAuthority() {
    let h = Harness(authorized: false)
    h.publishExactProfile()

    XCTAssertFalse(h.binding.canExposeArming)
    XCTAssertEqual(h.link.enableIndicationsCount, 0)
    XCTAssertTrue(h.link.writes.isEmpty)
    XCTAssertNil(h.binding.currentCapability)
  }

  func testMismatchedPeripheralCannotEnableControlOrExposeArming() {
    let h = Harness(authorized: true)
    h.client.connectedPeripheralIdentifier = UUID(
      uuidString: "00000000-0000-0000-0000-000000000999"
    )!
    h.publishExactProfile()

    XCTAssertFalse(h.binding.canExposeArming)
    XCTAssertEqual(h.link.enableIndicationsCount, 0)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testMismatchedCapabilityBytesOrControlPointPropertiesRemainPassive() {
    let bytes = Harness(authorized: true)
    bytes.publishExactProfile(
      featureData: Data([0x0C, 0x16, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    )
    XCTAssertEqual(bytes.link.enableIndicationsCount, 0)
    XCTAssertFalse(bytes.binding.canExposeArming)

    let properties = Harness(authorized: true)
    let withoutIndicate = Harness.characteristics.map { info in
      info.uuid == FTMSUUID.fitnessMachineControlPoint
        ? .init(uuid: info.uuid, properties: ["Write"])
        : info
    }
    properties.publishExactProfile(characteristics: withoutIndicate)
    XCTAssertEqual(properties.link.enableIndicationsCount, 0)
    XCTAssertFalse(properties.binding.canExposeArming)
  }

  func testExpiredProofAuthorityInvalidatesTheEstablishedControlLink() {
    let h = Harness(authorized: true)
    h.makeReadyWithFreshStationaryTelemetry()

    h.authority.activeAuthorization = nil
    h.binding.tick()

    XCTAssertFalse(h.binding.canExposeArming)
    XCTAssertNil(h.binding.currentCapability)
    XCTAssertEqual(h.link.invalidateCount, 1)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testExactAuthorisedProfileRequiresControlIndicationAndFreshTelemetry() {
    let h = Harness(authorized: true)
    h.publishExactProfile()

    XCTAssertEqual(h.link.enableIndicationsCount, 1)
    XCTAssertFalse(h.binding.canExposeArming)
    h.link.send(.indicationsEnabled)
    XCTAssertFalse(h.binding.canExposeArming)

    h.binding.receive(
      .value(
        uuid: FTMSUUID.treadmillData,
        data: Data([0x09, 0x00, 0x00, 0x00, 0x00, 0x00]),
        source: .notification
      )
    )
    XCTAssertFalse(
      h.binding.canExposeArming, "A fresh but incomplete packet is not accepted telemetry")

    h.publishTelemetry(speedRaw: 0)
    XCTAssertTrue(h.binding.canExposeArming)
    XCTAssertEqual(h.binding.currentCapability?.fitnessMachineFeatureEvidence, .matched)

    h.clock.advance(by: 2.001)
    XCTAssertFalse(h.binding.canExposeArming)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testEndToEndRequestControlThenPhysicalStartSequencesOnlySpeedAndInclination() throws {
    let h = Harness(authorized: true)
    h.makeReadyWithFreshStationaryTelemetry()
    XCTAssertNotNil(h.binding.arm(plan: h.plan, ceilings: h.ceilings, sourcePlanID: nil))

    let readiness = WorkoutOperatorReadiness(
      deckClear: true,
      consoleImmediatelyReachable: true,
      safetyKeyImmediatelyReachable: true,
      physicallyStationary: true
    )
    XCTAssertNotNil(h.binding.beginWorkout(readiness: readiness))
    XCTAssertEqual(h.link.writes, [Data([0x00])])
    guard case .submitted = h.binding.orchestrator.state.procedure else {
      return XCTFail("Intent and submission must remain separate from ATT acceptance")
    }

    h.link.send(.writeAccepted)
    guard case .attAccepted = h.binding.orchestrator.state.procedure else {
      return XCTFail("ATT acceptance must remain separate from the FTMS result")
    }
    h.link.send(.indication(Data([0x80, 0x00, 0x01])))
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)

    h.publishTelemetry(speedRaw: 0)
    XCTAssertEqual(
      h.link.writes.count, 1, "Accepted zero speed is Stop evidence, not Start evidence")
    h.publishTelemetry(speedRaw: 50)
    XCTAssertEqual(h.link.writes.last, Data([0x02, 0xF4, 0x01]))
    XCTAssertEqual(h.link.writes.map(\.first), [0x00, 0x02])

    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x02, 0x01])))
    XCTAssertEqual(h.link.writes.last, Data([0x03, 0x00, 0x00]))
    XCTAssertEqual(h.link.writes.map(\.first), [0x00, 0x02, 0x03])

    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x03, 0x01])))
    guard case .applyingTargets(.initial) = h.binding.orchestrator.state.execution else {
      return XCTFail("Acknowledged targets still require later matching telemetry")
    }
    h.clock.advance(by: 0.001)
    h.publishTelemetry(speedRaw: 500)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
  }

  func testForegroundLossInvalidatesAndSuppressesFurtherProceduresWithoutReconnect() throws {
    let h = Harness(authorized: true)
    h.makeReadyWithFreshStationaryTelemetry()
    XCTAssertNotNil(h.binding.arm(plan: h.plan, ceilings: h.ceilings, sourcePlanID: nil))
    _ = h.binding.beginWorkout(
      readiness: .init(
        deckClear: true,
        consoleImmediatelyReachable: true,
        safetyKeyImmediatelyReachable: true,
        physicallyStationary: true
      )
    )
    XCTAssertEqual(h.link.writes, [Data([0x00])])

    h.binding.setApplicationActivity(.inactive)
    guard case .interrupted(.foregroundLost) = h.binding.orchestrator.state.execution else {
      return XCTFail("Foreground loss must truthfully interrupt the attempt")
    }
    XCTAssertEqual(h.link.invalidateCount, 1)
    XCTAssertEqual(h.link.writes, [Data([0x00])])

    h.binding.setApplicationActivity(.active)
    XCTAssertEqual(h.link.enableIndicationsCount, 1, "The binding must not reconnect or resume")
    XCTAssertEqual(h.link.writes, [Data([0x00])])
  }

  func testAcceptedPhysicalResumeRestoresEffectiveSpeedThenInclination() throws {
    let h = Harness(authorized: true)
    h.reachRunning()
    h.publishTelemetry(speedRaw: 0)
    guard case .paused = h.binding.orchestrator.state.execution else {
      return XCTFail("Accepted zero-speed telemetry must establish a pause")
    }
    let writeCount = h.link.writes.count

    let epoch = try XCTUnwrap(h.binding.epoch)
    _ = h.binding.handle(
      .setSpeedOverride(
        epoch: epoch,
        .init(value: Decimal(string: "5.5")!, unit: .kilometresPerHour)
      )
    )
    _ = h.binding.handle(
      .setInclinationOverride(
        epoch: epoch,
        .init(value: 1, unit: .percent)
      )
    )
    XCTAssertEqual(h.link.writes.count, writeCount)

    h.publishTelemetry(speedRaw: 50)
    XCTAssertEqual(h.link.writes.last, Data([0x02, 0x26, 0x02]))
    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x02, 0x01])))
    XCTAssertEqual(h.link.writes.last, Data([0x03, 0x0A, 0x00]))
    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x03, 0x01])))
    guard case .restoringTargets = h.binding.orchestrator.state.execution else {
      return XCTFail("Restored commands still require later telemetry evidence")
    }
    h.clock.advance(by: 0.001)
    h.publishTelemetry(speedRaw: 550, inclinationRaw: 10)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
  }

  func testEveryTransmissionRechecksProofEpochForegroundProfileProcedureAndFreshness() throws {
    let h = Harness(authorized: true)
    h.makeReadyWithFreshStationaryTelemetry()
    let capability = try XCTUnwrap(h.binding.currentCapability)
    let profile = try XCTUnwrap(h.binding.executionProfile)
    let authorization = try XCTUnwrap(h.authority.activeAuthorization)
    let epoch = try XCTUnwrap(h.binding.epoch)
    let procedureID = ProcedureID(epoch: epoch, sequence: 41)
    let record = WorkoutProcedureRecord(
      id: procedureID,
      intent: .requestControl,
      stepIndex: nil,
      createdAt: h.clock.read().monotonic
    )
    let frozen = FrozenWorkoutAttemptInputs(
      attemptID: UUID(),
      sourcePlanID: nil,
      plan: h.plan,
      capability: capability,
      ceilings: h.ceilings,
      profile: profile,
      executionProfileIdentity: FR30zExecutionProfile.identity,
      attemptedAt: h.clock.read().wallClock
    )

    let valid = ProductionTransmissionContext(
      authorization: authorization,
      frozenAuthorizationSessionID: authorization.sessionID,
      epoch: epoch,
      foreground: true,
      capability: capability,
      profile: profile,
      frozenAttempt: frozen,
      expectedProcedureID: procedureID,
      latestTelemetryAt: h.clock.read().monotonic,
      now: h.clock.read().monotonic
    )
    var noAuthority = valid
    noAuthority.authorization = nil
    var changedSession = valid
    changedSession.frozenAuthorizationSessionID = UUID()
    var wrongEpoch = valid
    wrongEpoch.epoch = .init(rawValue: epoch.rawValue + 1)
    var background = valid
    background.foreground = false
    var noCapability = valid
    noCapability.capability = nil
    var noProfile = valid
    noProfile.profile = nil
    var noFrozenAttempt = valid
    noFrozenAttempt.frozenAttempt = nil
    var wrongProcedure = valid
    wrongProcedure.expectedProcedureID = nil
    var staleTelemetry = valid
    staleTelemetry.latestTelemetryAt = h.clock.read().monotonic.advanced(by: -2.001)
    let cases: [(String, ProductionTransmissionContext)] = [
      ("proof authority", noAuthority),
      ("proof session identity", changedSession),
      ("connection epoch", wrongEpoch),
      ("foreground", background),
      ("capability", noCapability),
      ("profile", noProfile),
      ("frozen attempt", noFrozenAttempt),
      ("current reducer procedure", wrongProcedure),
      ("telemetry freshness", staleTelemetry),
    ]

    for (name, suppliedContext) in cases {
      let raw = BindingRawTransport(epoch: epoch)
      let adapter = ProductionWorkoutTargetControlTransport(transport: raw)
      adapter.contextProvider = { suppliedContext }
      adapter.perform(.submit(record))
      XCTAssertTrue(raw.submissions.isEmpty, "Expected \(name) to fail closed")
    }

    let busyRaw = BindingRawTransport(epoch: epoch)
    busyRaw.state.inFlight = .init(
      id: .init(epoch: epoch, sequence: 99),
      intent: .requestControl,
      exactRequestBytes: Data([0x00]),
      submittedAt: h.clock.read().monotonic,
      attOutcome: nil
    )
    let busyAdapter = ProductionWorkoutTargetControlTransport(transport: busyRaw)
    busyAdapter.contextProvider = { valid }
    busyAdapter.perform(.submit(record))
    XCTAssertTrue(busyRaw.submissions.isEmpty, "One-procedure state must be rechecked")

    let targetID = ProcedureID(epoch: epoch, sequence: 42)
    let targetRecord = WorkoutProcedureRecord(
      id: targetID,
      intent: .setTargetSpeed(.init(value: 11, unit: .kilometresPerHour)),
      stepIndex: 0,
      createdAt: h.clock.read().monotonic
    )
    let ceilingRaw = BindingRawTransport(epoch: epoch, permissionHeld: true)
    let ceilingAdapter = ProductionWorkoutTargetControlTransport(transport: ceilingRaw)
    var ceilingContext = valid
    ceilingContext.expectedProcedureID = targetID
    ceilingAdapter.contextProvider = { ceilingContext }
    ceilingAdapter.perform(.submit(targetRecord))
    XCTAssertTrue(ceilingRaw.submissions.isEmpty, "Frozen ceilings must be rechecked")
  }
}

@MainActor
extension ProductionWorkoutExecutionBindingTests {
  @MainActor
  fileprivate final class Harness {
    static let peripheralID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
    static let equipment = "Synthetic FR30z"

    let client = BindingClient()
    let authority: BindingAuthority
    let link = BindingControlPointLink()
    let clock = BindingClock()
    let scheduler = BindingScheduler()
    let history = BindingHistory()
    let binding: ProductionWorkoutExecutionBinding
    let plan: WorkoutPlanValidator.ValidatedPlan
    let ceilings = WorkoutSessionCeilings(
      maximumSpeed: .init(value: 10, unit: .kilometresPerHour),
      maximumInclination: .init(value: 6, unit: .percent),
      maximumStepSpeedChange: .init(value: 3, unit: .kilometresPerHour)
    )

    init(authorized: Bool) {
      client.connectedPeripheralIdentifier = Self.peripheralID
      client.connectedPeripheralName = Self.equipment
      client.controlPointLink = link
      authority = BindingAuthority(
        authorization: authorized
          ? .init(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000062")!,
            peripheralIdentifier: Self.peripheralID,
            equipmentIdentity: Self.equipment
          )
          : nil
      )
      let capabilities = Self.capabilities
      let rawPlan = WorkoutPlan(
        schemaVersion: WorkoutPlanSchema.currentVersion,
        suggestedName: "Synthetic binding",
        activity: .indoorRunning,
        steps: [
          Self.step(.warmUp, "Warm up", speed: 5, incline: 0),
          Self.step(.interval, "Run", speed: 7, incline: 1),
          Self.step(.coolDown, "Cool down", speed: 4, incline: 0),
        ]
      )
      plan = try! WorkoutPlanValidator.validate(rawPlan, against: capabilities).get()
      let rawTransport = FTMSSingleProcedureTransport(
        clock: { [clock] in clock.read().monotonic },
        scheduler: scheduler
      )
      binding = ProductionWorkoutExecutionBinding(
        client: client,
        authority: authority,
        controlTransport: rawTransport,
        history: history,
        clock: clock,
        attemptIDs: BindingAttemptIDs(),
        automaticTicks: false
      )
      binding.setApplicationActivity(.active)
    }

    func publishExactProfile(
      featureData: Data = Data([0x0C, 0x16, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00]),
      characteristics suppliedCharacteristics: [FTMSCharacteristicInfo]? = nil
    ) {
      binding.receive(.connection(.connecting(name: Self.equipment)))
      binding.receive(.connection(.connected(name: Self.equipment)))
      binding.receive(.characteristics(suppliedCharacteristics ?? Self.characteristics))
      for uuid in [FTMSUUID.treadmillData, FTMSUUID.trainingStatus, FTMSUUID.fitnessMachineStatus] {
        binding.receive(.subscription(uuid: uuid, state: .subscribed))
      }
      binding.receive(
        .value(
          uuid: FTMSUUID.fitnessMachineFeature,
          data: featureData,
          source: .initialRead
        )
      )
      binding.receive(
        .value(
          uuid: FTMSUUID.supportedSpeedRange,
          data: Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00]),
          source: .initialRead
        )
      )
      binding.receive(
        .value(
          uuid: FTMSUUID.supportedInclinationRange,
          data: Data([0x00, 0x00, 0x96, 0x00, 0x0A, 0x00]),
          source: .initialRead
        )
      )
    }

    func makeReadyWithFreshStationaryTelemetry() {
      publishExactProfile()
      link.send(.indicationsEnabled)
      publishTelemetry(speedRaw: 0)
      XCTAssertTrue(binding.canExposeArming)
    }

    func reachRunning() {
      makeReadyWithFreshStationaryTelemetry()
      XCTAssertNotNil(binding.arm(plan: plan, ceilings: ceilings, sourcePlanID: nil))
      _ = binding.beginWorkout(
        readiness: .init(
          deckClear: true,
          consoleImmediatelyReachable: true,
          safetyKeyImmediatelyReachable: true,
          physicallyStationary: true
        )
      )
      link.send(.writeAccepted)
      link.send(.indication(Data([0x80, 0x00, 0x01])))
      publishTelemetry(speedRaw: 50)
      link.send(.writeAccepted)
      link.send(.indication(Data([0x80, 0x02, 0x01])))
      link.send(.writeAccepted)
      link.send(.indication(Data([0x80, 0x03, 0x01])))
      clock.advance(by: 0.001)
      publishTelemetry(speedRaw: 500)
      XCTAssertEqual(binding.orchestrator.state.execution, .runningSegment)
    }

    func publishTelemetry(speedRaw: UInt16, inclinationRaw: Int16 = 0) {
      let incline = UInt16(bitPattern: inclinationRaw)
      let bytes = Data([
        0x08, 0x00,
        UInt8(speedRaw & 0x00FF), UInt8(speedRaw >> 8),
        UInt8(incline & 0x00FF), UInt8(incline >> 8),
        0x00, 0x00,
      ])
      binding.receive(.value(uuid: FTMSUUID.treadmillData, data: bytes, source: .notification))
    }

    static let capabilities = WorkoutPlanCapabilities(
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

    static let characteristics: [FTMSCharacteristicInfo] = [
      .init(uuid: FTMSUUID.fitnessMachineFeature, properties: ["Read"]),
      .init(uuid: FTMSUUID.treadmillData, properties: ["Notify"]),
      .init(uuid: FTMSUUID.trainingStatus, properties: ["Read", "Notify"]),
      .init(uuid: FTMSUUID.supportedSpeedRange, properties: ["Read"]),
      .init(uuid: FTMSUUID.supportedInclinationRange, properties: ["Read"]),
      .init(uuid: FTMSUUID.fitnessMachineControlPoint, properties: ["Write", "Indicate"]),
      .init(uuid: FTMSUUID.fitnessMachineStatus, properties: ["Notify"]),
    ]

    static func step(
      _ kind: WorkoutStepKind,
      _ label: String,
      speed: Decimal,
      incline: Decimal
    ) -> WorkoutStep {
      .init(
        kind: kind,
        label: label,
        duration: .init(value: 60, unit: .seconds),
        targetSpeed: .init(value: speed, unit: .kilometresPerHour),
        targetInclination: .init(value: incline, unit: .percent)
      )
    }
  }
}

@MainActor
private final class BindingClient: FTMSClientProtocol {
  weak var delegate: (any FTMSClientDelegate)?
  var connectedPeripheralIdentifier: UUID?
  var connectedPeripheralName: String?
  var controlPointLink: (any FTMSControlPointLink)?
  func startScan() {}
  func stopScan() {}
  func connect(to identifier: UUID) {}
  func disconnect() {}
}

@MainActor
private final class BindingAuthority: WorkoutProofSessionAuthorizing {
  var activeAuthorization: WorkoutProofSessionAuthorization?
  init(authorization: WorkoutProofSessionAuthorization?) {
    activeAuthorization = authorization
  }
}

@MainActor
private final class BindingControlPointLink: FTMSControlPointLink {
  let supportsWriteWithResponse = true
  let supportsIndications = true
  var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?
  private(set) var enableIndicationsCount = 0
  private(set) var writes: [Data] = []
  private(set) var invalidateCount = 0

  func enableIndications() { enableIndicationsCount += 1 }
  func writeWithResponse(_ data: Data) { writes.append(data) }
  func invalidate() {
    invalidateCount += 1
    eventHandler = nil
  }
  func send(_ event: FTMSControlPointLinkEvent) { eventHandler?(event) }
}

private final class BindingClock: WorkoutOrchestrationClock {
  private var value = WorkoutOrchestrationTime(
    monotonic: .init(seconds: 10),
    wallClock: Date(timeIntervalSince1970: 10)
  )
  func read() -> WorkoutOrchestrationTime { value }
  func advance(by interval: TimeInterval) {
    value = .init(
      monotonic: value.monotonic.advanced(by: interval),
      wallClock: value.wallClock.addingTimeInterval(interval)
    )
  }
}

private final class BindingAttemptIDs: WorkoutAttemptIDSource {
  func nextAttemptID() -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000063")!
  }
}

private final class BindingHistory: WorkoutHistoryRepositoryProtocol {
  private var summaries: [WorkoutExecutionSummary] = []
  func list() -> WorkoutHistoryRepositoryStatus {
    .init(
      canonical: summaries.isEmpty ? .empty : .available(summaries: summaries),
      staging: .absent
    )
  }
  func record(_ summary: WorkoutExecutionSummary) throws {
    if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
      summaries[index] = summary
    } else {
      summaries.append(summary)
    }
  }
}

@MainActor
private final class BindingScheduler: FTMSDeadlineScheduling {
  func schedule(
    after interval: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any FTMSDeadlineCancellation {
    BindingCancellation()
  }
}

@MainActor
private final class BindingCancellation: FTMSDeadlineCancellation {
  func cancel() {}
}

@MainActor
private final class BindingRawTransport: FitnessMachineControlTransport {
  var state: FTMSControlPointTransportState
  var stateHandler: ((FTMSControlPointTransportState) -> Void)?
  private(set) var submissions: [FitnessMachineControlIntent] = []

  init(epoch: ConnectionEpoch, permissionHeld: Bool = false) {
    state = .init(
      link: .ready(epoch),
      permission: permissionHeld ? .held(epoch, acknowledgedAt: .init(seconds: 1)) : .notHeld
    )
  }

  func establishLink(
    epoch: ConnectionEpoch,
    eligibility: FTMSControlPointEligibility,
    link: any FTMSControlPointLink
  ) throws {}
  func enableIndications() throws {}
  func submit(_ intent: FitnessMachineControlIntent) throws -> ProcedureID {
    submissions.append(intent)
    return .init(epoch: state.link.epoch!, sequence: UInt64(submissions.count))
  }
  func disconnect() { state.link = .disconnected }
}
