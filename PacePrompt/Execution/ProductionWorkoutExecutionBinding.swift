import Foundation

struct WorkoutProofSessionAuthorization: Equatable {
  let sessionID: UUID
  let peripheralIdentifier: UUID
  let equipmentIdentity: String
}

@MainActor
protocol WorkoutProofSessionAuthorizing: AnyObject {
  var activeAuthorization: WorkoutProofSessionAuthorization? { get }
  func invalidateAuthorization()
}

extension WorkoutProofSessionAuthorizing {
  func invalidateAuthorization() {}
}

/// Production's default authority. A later, separately authorised proof slice
/// must inject a short-lived authority; nothing is read from defaults or launch arguments.
@MainActor
final class LockedWorkoutProofSessionAuthority: WorkoutProofSessionAuthorizing {
  var activeAuthorization: WorkoutProofSessionAuthorization? { nil }
}

struct WorkoutProofConnectionCandidate: Equatable {
  let peripheralIdentifier: UUID
  let equipmentIdentity: String
}

struct SystemWorkoutOrchestrationClock: WorkoutOrchestrationClock {
  func read() -> WorkoutOrchestrationTime {
    .init(
      monotonic: .init(seconds: ProcessInfo.processInfo.systemUptime),
      wallClock: Date()
    )
  }
}

struct SystemWorkoutAttemptIDSource: WorkoutAttemptIDSource {
  func nextAttemptID() -> UUID { UUID() }
}

@MainActor
struct ProductionTransmissionContext {
  var authorization: WorkoutProofSessionAuthorization?
  var frozenAuthorizationSessionID: UUID?
  var epoch: ConnectionEpoch?
  var foreground: Bool
  var capability: FR30zCapabilitySnapshot?
  var profile: FR30zExecutionProfile?
  var frozenAttempt: FrozenWorkoutAttemptInputs?
  var expectedProcedureID: ProcedureID?
  var latestTelemetryAt: MonotonicInstant?
  var now: MonotonicInstant
}

/// The only production adapter from reducer effects to executable FTMS intents.
/// Its exhaustive switch deliberately has no Start, Stop or Pause case.
@MainActor
final class ProductionWorkoutTargetControlTransport: WorkoutTargetControlTransport {
  var contextProvider: (() -> ProductionTransmissionContext?)?
  var eventSink: ((WorkoutExecutionEvent) -> Void)?
  var stateObserver: ((FTMSControlPointTransportState) -> Void)?

  private let transport: any FitnessMachineControlTransport
  private var pendingReducerProcedureID: ProcedureID?
  private var reducerIDsByTransportID: [ProcedureID: ProcedureID] = [:]
  private var submitted: Set<ProcedureID> = []
  private var attAccepted: Set<ProcedureID> = []
  private var processedOutcomeCount = 0

  init(transport: any FitnessMachineControlTransport) {
    self.transport = transport
    transport.stateHandler = { [weak self] state in
      self?.consume(state)
    }
  }

  func perform(_ effect: WorkoutTargetControlTransportEffect) {
    switch effect {
    case .submit(let record):
      submit(record)
    case .cancelAwaitingCallback(let id):
      guard reducerIDsByTransportID.values.contains(id) else { return }
      transport.disconnect()
      reducerIDsByTransportID = reducerIDsByTransportID.filter { $0.value != id }
    }
  }

  private func submit(_ record: WorkoutProcedureRecord) {
    let context = contextProvider?()
    guard let rejection = rejectionReason(for: record, context: context) else {
      pendingReducerProcedureID = record.id
      do {
        let transportID = try transport.submit(ftmsIntent(for: record.intent))
        if !submitted.contains(record.id) {
          reducerIDsByTransportID[transportID] = record.id
          publishSubmitted(record.id)
        }
        pendingReducerProcedureID = nil
      } catch {
        pendingReducerProcedureID = nil
        eventSink?(
          .intentSubmissionRejected(
            epoch: record.id.epoch,
            procedureID: record.id,
            reason: error.localizedDescription
          )
        )
      }
      return
    }

    eventSink?(
      .intentSubmissionRejected(
        epoch: record.id.epoch,
        procedureID: record.id,
        reason: rejection
      )
    )
  }

  private func rejectionReason(
    for record: WorkoutProcedureRecord,
    context: ProductionTransmissionContext?
  ) -> String? {
    guard let context else { return "Production execution context is unavailable" }
    guard let authorization = context.authorization else {
      return "No authorised proof session is active"
    }
    guard context.frozenAuthorizationSessionID == authorization.sessionID else {
      return "The authorised proof session changed before transmission"
    }
    guard context.foreground else { return "The app is not active in the foreground" }
    guard let epoch = context.epoch, epoch == record.id.epoch else {
      return "The connection epoch changed before transmission"
    }
    guard context.expectedProcedureID == record.id else {
      return "The reducer procedure is no longer current"
    }
    guard let capability = context.capability, let profile = context.profile,
      profile.matches(capability)
    else {
      return "The accepted FR30z capability profile is not current"
    }
    guard profile.peripheralIdentity == authorization.peripheralIdentifier.uuidString.lowercased(),
      profile.equipmentIdentity == authorization.equipmentIdentity
    else {
      return "The proof authority no longer matches the accepted FR30z profile"
    }
    guard let attempt = context.frozenAttempt,
      attempt.capability == capability,
      attempt.profile == profile
    else {
      return "The frozen attempt no longer matches current profile evidence"
    }
    guard let telemetryAt = context.latestTelemetryAt,
      context.now >= telemetryAt,
      context.now.seconds - telemetryAt.seconds
        <= FR30zExecutionProfile.telemetryFreshnessInterval
    else {
      return "Current treadmill telemetry is not fresh"
    }
    guard case .ready(epoch) = transport.state.link,
      transport.state.inFlight == nil
    else {
      return "The one-procedure Control Point transport is not ready"
    }

    switch record.intent {
    case .requestControl:
      guard case .notHeld = transport.state.permission else {
        return "Control permission is not available for a new request"
      }
    case .setTargetSpeed(let speed):
      guard case .held(epoch, _) = transport.state.permission else {
        return "Control permission is not held"
      }
      guard speed.value <= attempt.ceilings.maximumSpeed.value else {
        return "The speed target exceeds the frozen session ceiling"
      }
    case .setTargetInclination(let inclination):
      guard case .held(epoch, _) = transport.state.permission else {
        return "Control permission is not held"
      }
      guard inclination.value <= attempt.ceilings.maximumInclination.value else {
        return "The inclination target exceeds the frozen session ceiling"
      }
    }
    return nil
  }

  private func ftmsIntent(for intent: WorkoutControlPointIntent) -> FitnessMachineControlIntent {
    switch intent {
    case .requestControl:
      .requestControl
    case .setTargetSpeed(let speed):
      .setTargetSpeed(kilometresPerHour: NSDecimalNumber(decimal: speed.value).doubleValue)
    case .setTargetInclination(let inclination):
      .setTargetInclination(percent: NSDecimalNumber(decimal: inclination.value).doubleValue)
    }
  }

  private func consume(_ state: FTMSControlPointTransportState) {
    if let evidence = state.inFlight,
      reducerIDsByTransportID[evidence.id] == nil,
      let pendingReducerProcedureID
    {
      reducerIDsByTransportID[evidence.id] = pendingReducerProcedureID
    }
    if let evidence = state.inFlight, let reducerID = reducerIDsByTransportID[evidence.id] {
      publishSubmitted(reducerID)
      if case .accepted = evidence.attOutcome, attAccepted.insert(evidence.id).inserted {
        eventSink?(.attAccepted(epoch: reducerID.epoch, procedureID: reducerID))
      }
    }

    while processedOutcomeCount < state.outcomes.count {
      let outcome = state.outcomes[processedOutcomeCount]
      processedOutcomeCount += 1
      guard let reducerID = reducerIDsByTransportID[outcome.evidence.id] else { continue }
      if case .accepted = outcome.evidence.attOutcome,
        attAccepted.insert(outcome.evidence.id).inserted
      {
        eventSink?(.attAccepted(epoch: reducerID.epoch, procedureID: reducerID))
      }
      publish(outcome.result, for: reducerID)
      reducerIDsByTransportID.removeValue(forKey: outcome.evidence.id)
    }
    stateObserver?(state)
  }

  private func publishSubmitted(_ reducerID: ProcedureID) {
    guard submitted.insert(reducerID).inserted else { return }
    eventSink?(.intentSubmitted(epoch: reducerID.epoch, procedureID: reducerID))
  }

  private func publish(_ result: FTMSControlPointProcedureResult, for id: ProcedureID) {
    switch result {
    case .acknowledged:
      eventSink?(.protocolAcknowledged(epoch: id.epoch, procedureID: id))
    case .attRejected(_, let message):
      eventSink?(.attRejected(epoch: id.epoch, procedureID: id, reason: message))
    case .ftmsRejected(let response):
      if response.result == .opcodeNotSupported {
        eventSink?(.protocolUnsupported(epoch: id.epoch, procedureID: id))
      } else {
        eventSink?(
          .protocolRejected(
            epoch: id.epoch,
            procedureID: id,
            reason: "FTMS result 0x\(String(format: "%02X", response.result.rawValue))"
          )
        )
      }
    case .protocolAnomaly(_, let rawBytes):
      if let rawBytes, rawBytes.count == 3, rawBytes.first == 0x80 {
        eventSink?(.protocolUnknown(epoch: id.epoch, procedureID: id))
      } else {
        eventSink?(.protocolMalformed(epoch: id.epoch, procedureID: id))
      }
    case .timedOut:
      eventSink?(.tick(epoch: id.epoch))
    case .timedOutByDisconnect, .deliveryUnknown, .deliveryUnknownDisconnect:
      eventSink?(.protocolUnknown(epoch: id.epoch, procedureID: id))
    }
  }
}

/// Production composition root for one app-owned FTMS client, reducer,
/// persistence repository and real one-procedure Control Point transport.
@MainActor
final class ProductionWorkoutExecutionBinding {
  private static let expectedFeature = Data([0x0C, 0x16, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00])
  private static let expectedSpeedRange = Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00])
  private static let expectedInclinationRange = Data([0x00, 0x00, 0x96, 0x00, 0x0A, 0x00])

  private let client: any FTMSClientProtocol
  private let authority: any WorkoutProofSessionAuthorizing
  private let clock: any WorkoutOrchestrationClock
  private let controlTransport: any FitnessMachineControlTransport
  private let targetTransport: ProductionWorkoutTargetControlTransport

  private(set) var orchestrator: WorkoutExecutionOrchestrator
  private(set) var applicationActivity: FTMSApplicationActivity = .unknown
  private(set) var epoch: ConnectionEpoch?

  private var nextEpoch: UInt64 = 1
  private var isConnected = false
  private var characteristics: [String: Set<String>] = [:]
  private var values: [String: Data] = [:]
  private var subscriptions: [String: FTMSSubscriptionState] = [:]
  private var latestTelemetryInput: WorkoutTelemetryInput?
  private var latestTelemetryAt: MonotonicInstant?
  private var latestTelemetryIsComplete = false
  private var establishedLinkIdentity: ObjectIdentifier?
  private var lastPublishedCapability: FR30zCapabilitySnapshot?
  private var tickTimer: Timer?
  private var frozenAuthorizationSessionID: UUID?
  private var controlSuppressedUntilNewConnection = false
  private let automaticTicks: Bool

  init(
    client: any FTMSClientProtocol,
    authority: (any WorkoutProofSessionAuthorizing)? = nil,
    controlTransport: (any FitnessMachineControlTransport)? = nil,
    history: any WorkoutHistoryRepositoryProtocol = WorkoutHistoryRepository(),
    clock: any WorkoutOrchestrationClock = SystemWorkoutOrchestrationClock(),
    attemptIDs: any WorkoutAttemptIDSource = SystemWorkoutAttemptIDSource(),
    automaticTicks: Bool = true
  ) {
    self.client = client
    let resolvedAuthority = authority ?? LockedWorkoutProofSessionAuthority()
    let resolvedControlTransport = controlTransport ?? FTMSSingleProcedureTransport()
    self.authority = resolvedAuthority
    self.clock = clock
    self.controlTransport = resolvedControlTransport
    self.automaticTicks = automaticTicks
    let targetTransport = ProductionWorkoutTargetControlTransport(
      transport: resolvedControlTransport)
    self.targetTransport = targetTransport
    orchestrator = WorkoutExecutionOrchestrator(
      transport: targetTransport,
      history: history,
      clock: clock,
      attemptIDs: attemptIDs
    )

    targetTransport.contextProvider = { [weak self] in self?.transmissionContext() }
    targetTransport.eventSink = { [weak self] event in _ = self?.apply(event) }
    targetTransport.stateObserver = { [weak self] state in self?.consumeControlState(state) }
  }

  var executionProfile: FR30zExecutionProfile? {
    guard let authorization = authority.activeAuthorization else { return nil }
    return .init(
      peripheralIdentity: authorization.peripheralIdentifier.uuidString.lowercased(),
      equipmentIdentity: authorization.equipmentIdentity
    )
  }

  var currentCapability: FR30zCapabilitySnapshot? {
    makeCapability(controlPointReady: controlPointIsReady)
  }

  var proofConnectionCandidate: WorkoutProofConnectionCandidate? {
    guard applicationActivity == .active,
      isConnected,
      let peripheralIdentifier = client.connectedPeripheralIdentifier,
      let equipmentIdentity = client.connectedPeripheralName,
      passiveProfileMatches(
        peripheralIdentifier: peripheralIdentifier,
        equipmentIdentity: equipmentIdentity
      )
    else { return nil }
    return .init(
      peripheralIdentifier: peripheralIdentifier,
      equipmentIdentity: equipmentIdentity
    )
  }

  var canExposeArming: Bool {
    guard let capability = currentCapability,
      let profile = executionProfile,
      profile.matches(capability),
      applicationActivity == .active,
      telemetryIsFresh
    else { return false }
    return true
  }

  @discardableResult
  func arm(
    plan: WorkoutPlanValidator.ValidatedPlan,
    ceilings: WorkoutSessionCeilings,
    sourcePlanID: UUID?
  ) -> WorkoutOrchestrationResult? {
    guard canExposeArming, let profile = executionProfile else { return nil }
    guard let authorization = authority.activeAuthorization else { return nil }
    let result = orchestrator.arm(
      plan: plan,
      ceilings: ceilings,
      profile: profile,
      sourcePlanID: sourcePlanID
    )
    if result.reducerDisposition == .accepted {
      frozenAuthorizationSessionID = authorization.sessionID
    }
    return result
  }

  @discardableResult
  func beginWorkout(readiness: WorkoutOperatorReadiness) -> WorkoutOrchestrationResult? {
    guard canExposeArming, let epoch else { return nil }
    return apply(.beginWorkout(epoch: epoch, readiness: readiness))
  }

  @discardableResult
  func handle(_ event: WorkoutExecutionEvent) -> WorkoutOrchestrationResult {
    apply(event)
  }

  func setApplicationActivity(_ activity: FTMSApplicationActivity) {
    guard applicationActivity != activity else { return }
    applicationActivity = activity
    guard activity == .active else {
      stopTicks()
      controlSuppressedUntilNewConnection = true
      if let epoch {
        _ = apply(
          .appBecameInactive(epoch: epoch, reason: "Application left the foreground")
        )
      } else {
        authority.invalidateAuthorization()
      }
      controlTransport.disconnect()
      establishedLinkIdentity = nil
      return
    }
    refreshCapability()
  }

  func receive(_ event: FTMSClientEvent) {
    switch event {
    case .connection(let state):
      consumeConnection(state)
    case .characteristics(let infos):
      characteristics = Dictionary(
        uniqueKeysWithValues: infos.map {
          ($0.uuid.uppercased(), Set($0.properties))
        })
      refreshCapability()
    case .subscription(let uuid, let state):
      subscriptions[uuid.uppercased()] = state
      refreshCapability()
    case .value(let uuid, let data, _):
      consumeValue(uuid: uuid.uppercased(), data: data)
    case .valueError(let uuid, _, let message):
      if uuid.uppercased() == FTMSUUID.treadmillData, let epoch {
        latestTelemetryAt = nil
        latestTelemetryIsComplete = false
        latestTelemetryInput = .malformed(message)
        _ = apply(.telemetry(epoch: epoch, .malformed(message)))
      }
    case .availability, .devices:
      break
    }
  }

  func tick() {
    guard applicationActivity == .active, let epoch else { return }
    refreshCapability()
    _ = apply(.tick(epoch: epoch))
  }

  private var controlPointIsReady: Bool {
    guard let epoch else { return false }
    if case .ready(epoch) = controlTransport.state.link { return true }
    return false
  }

  private var telemetryIsFresh: Bool {
    guard latestTelemetryIsComplete, let latestTelemetryAt else { return false }
    let now = clock.read().monotonic
    return now >= latestTelemetryAt
      && now.seconds - latestTelemetryAt.seconds
        <= FR30zExecutionProfile.telemetryFreshnessInterval
  }

  private func consumeConnection(_ state: TreadmillConnectionState) {
    switch state {
    case .connecting:
      isConnected = false
      controlSuppressedUntilNewConnection = true
      resetConnectionEvidence()
      controlSuppressedUntilNewConnection = false
      guard nextEpoch < UInt64.max else { return }
      let newEpoch = ConnectionEpoch(rawValue: nextEpoch)
      nextEpoch += 1
      epoch = newEpoch
      _ = apply(.userStartsConnection(newEpoch))
    case .connected:
      isConnected = true
      refreshCapability()
    case .disconnected(let message):
      invalidateConnection(reason: message ?? "FTMS connection ended")
    case .failed(let message):
      invalidateConnection(reason: message)
    case .idle, .scanning, .discovering:
      break
    }
  }

  private func consumeValue(uuid: String, data: Data) {
    values[uuid] = data
    if uuid == FTMSUUID.treadmillData {
      let now = clock.read().monotonic
      do {
        let decoded = try FTMSParser.treadmillData(data)
        let speed = decoded.instantaneousSpeedKilometresPerHour.map {
          WorkoutSpeed(value: Self.decimal($0), unit: .kilometresPerHour)
        }
        let inclination: WorkoutInclination?
        if case .value(let value)? = decoded.inclinationPercent {
          inclination = .init(value: Self.decimal(value), unit: .percent)
        } else {
          inclination = nil
        }
        let input = WorkoutTelemetryInput.sample(
          speed: speed,
          inclination: inclination,
          totalDistanceMetres: decoded.totalDistanceMetres.map(Decimal.init)
        )
        latestTelemetryAt = now
        latestTelemetryIsComplete = speed != nil && inclination != nil
        latestTelemetryInput = input
        refreshCapability()
        if let epoch, lastPublishedCapability != nil {
          _ = apply(.telemetry(epoch: epoch, input))
        }
      } catch {
        latestTelemetryAt = nil
        latestTelemetryIsComplete = false
        latestTelemetryInput = .malformed(error.localizedDescription)
        if let epoch {
          _ = apply(
            .telemetry(epoch: epoch, .malformed(error.localizedDescription))
          )
        }
      }
      return
    }
    if uuid == FTMSUUID.fitnessMachineStatus,
      let status = try? FTMSParser.fitnessMachineStatus(data),
      status == .controlPermissionLost,
      let epoch
    {
      _ = apply(
        .controlPermissionLost(epoch: epoch, reason: "FTMS reported control permission lost")
      )
      controlSuppressedUntilNewConnection = true
      controlTransport.disconnect()
      establishedLinkIdentity = nil
      return
    }
    refreshCapability()
  }

  private func refreshCapability() {
    guard applicationActivity == .active,
      isConnected,
      authority.activeAuthorization != nil
    else {
      suppressControlAssumptionsIfEstablished()
      return
    }

    establishControlPointIfEligible()
    guard let capability = currentCapability, let epoch else {
      if lastPublishedCapability != nil
        || (establishedLinkIdentity != nil && !preliminaryProfileMatches)
      {
        suppressControlAssumptionsIfEstablished()
      }
      return
    }
    if lastPublishedCapability == nil {
      lastPublishedCapability = capability
      _ = apply(.connectionBecomesReady(epoch: epoch, capability: capability))
      if let latestTelemetryInput {
        _ = apply(.telemetry(epoch: epoch, latestTelemetryInput))
      }
      startTicks()
    } else if lastPublishedCapability != capability {
      lastPublishedCapability = capability
      _ = apply(.capabilityChanged(epoch: epoch, capability: capability))
    }
  }

  private func suppressControlAssumptionsIfEstablished() {
    guard establishedLinkIdentity != nil || lastPublishedCapability != nil else { return }
    controlSuppressedUntilNewConnection = true
    if lastPublishedCapability != nil { publishCapabilityChange(nil) }
    if case .disconnected = controlTransport.state.link { return }
    controlTransport.disconnect()
  }

  private func consumeControlState(_ state: FTMSControlPointTransportState) {
    if establishedLinkIdentity != nil {
      switch state.link {
      case .disconnected, .invalidated:
        controlSuppressedUntilNewConnection = true
      case .awaitingIndicationEnablement, .enablingIndications, .ready:
        break
      }
    }
    refreshCapability()
  }

  private func establishControlPointIfEligible() {
    guard !controlPointIsReady,
      !controlSuppressedUntilNewConnection,
      case .disconnected = controlTransport.state.link,
      let epoch,
      preliminaryProfileMatches,
      let link = client.controlPointLink
    else { return }
    let identity = ObjectIdentifier(link)
    guard establishedLinkIdentity != identity else { return }
    do {
      let eligibility = FTMSControlPointEligibility(
        features: try FTMSParser.fitnessMachineFeature(Self.expectedFeature),
        speedRange: try FTMSParser.supportedSpeedRange(Self.expectedSpeedRange),
        inclinationRange: try FTMSParser.supportedInclinationRange(Self.expectedInclinationRange)
      )
      try controlTransport.establishLink(epoch: epoch, eligibility: eligibility, link: link)
      establishedLinkIdentity = identity
      try controlTransport.enableIndications()
    } catch {
      controlTransport.disconnect()
    }
  }

  private var preliminaryProfileMatches: Bool {
    guard let authorization = authority.activeAuthorization,
      passiveProfileMatches(
        peripheralIdentifier: authorization.peripheralIdentifier,
        equipmentIdentity: authorization.equipmentIdentity
      )
    else {
      return false
    }
    return true
  }

  private func passiveProfileMatches(
    peripheralIdentifier: UUID,
    equipmentIdentity: String
  ) -> Bool {
    guard client.connectedPeripheralIdentifier == peripheralIdentifier,
      client.connectedPeripheralName == equipmentIdentity,
      values[FTMSUUID.fitnessMachineFeature] == Self.expectedFeature,
      values[FTMSUUID.supportedSpeedRange] == Self.expectedSpeedRange,
      values[FTMSUUID.supportedInclinationRange] == Self.expectedInclinationRange
    else {
      return false
    }
    let expected: [String: Set<String>] = [
      FTMSUUID.fitnessMachineFeature: ["Read"],
      FTMSUUID.treadmillData: ["Notify"],
      FTMSUUID.supportedSpeedRange: ["Read"],
      FTMSUUID.supportedInclinationRange: ["Read"],
      FTMSUUID.fitnessMachineControlPoint: ["Write", "Indicate"],
    ]
    guard expected.allSatisfy({ characteristics[$0.key]?.isSuperset(of: $0.value) == true }) else {
      return false
    }
    guard case .subscribed? = subscriptions[FTMSUUID.treadmillData] else { return false }
    return optionalSubscriptionMatches(
      uuid: FTMSUUID.trainingStatus,
      properties: ["Read", "Notify"]
    )
      && optionalSubscriptionMatches(
        uuid: FTMSUUID.fitnessMachineStatus,
        properties: ["Notify"]
      )
  }

  private func optionalSubscriptionMatches(uuid: String, properties: Set<String>) -> Bool {
    if let actualProperties = characteristics[uuid] {
      guard actualProperties.isSuperset(of: properties) else { return false }
      switch subscriptions[uuid] {
      case .subscribed?, .unsupported?, .failed?: return true
      case .inactive?, .subscribing?, nil: return false
      }
    }
    if case .unsupported? = subscriptions[uuid] { return true }
    return false
  }

  private func makeCapability(controlPointReady: Bool) -> FR30zCapabilitySnapshot? {
    guard preliminaryProfileMatches, controlPointReady,
      let authorization = authority.activeAuthorization
    else { return nil }
    return .init(
      peripheralIdentity: authorization.peripheralIdentifier.uuidString.lowercased(),
      equipmentIdentity: authorization.equipmentIdentity,
      fitnessMachineServicePresent: true,
      requiredCharacteristicPropertiesMatch: true,
      fitnessMachineFeatureEvidence: .matched,
      supportedSpeedRangeEvidence: .matched,
      supportedInclinationRangeEvidence: .matched,
      treadmillDataNotificationsEnabled: true,
      controlPointIndicationsEnabled: true,
      optionalSubscriptionOutcomesResolved: true,
      planCapabilities: .init(
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
    )
  }

  private func publishCapabilityChange(_ replacement: FR30zCapabilitySnapshot?) {
    guard let epoch, lastPublishedCapability != nil else { return }
    lastPublishedCapability = replacement
    let unavailable =
      replacement
      ?? FR30zCapabilitySnapshot(
        peripheralIdentity: "unavailable",
        equipmentIdentity: "unavailable",
        fitnessMachineServicePresent: false,
        requiredCharacteristicPropertiesMatch: false,
        fitnessMachineFeatureEvidence: .unavailable,
        supportedSpeedRangeEvidence: .unavailable,
        supportedInclinationRangeEvidence: .unavailable,
        treadmillDataNotificationsEnabled: false,
        controlPointIndicationsEnabled: false,
        optionalSubscriptionOutcomesResolved: false,
        planCapabilities: .unavailable
      )
    _ = apply(.capabilityChanged(epoch: epoch, capability: unavailable))
  }

  private func invalidateConnection(reason: String) {
    stopTicks()
    isConnected = false
    controlSuppressedUntilNewConnection = true
    controlTransport.disconnect()
    establishedLinkIdentity = nil
    if let epoch {
      _ = apply(.connectionLost(epoch: epoch, reason: reason))
    } else {
      authority.invalidateAuthorization()
    }
    resetConnectionEvidence(keepEpoch: true)
  }

  private func resetConnectionEvidence(keepEpoch: Bool = false) {
    stopTicks()
    controlTransport.disconnect()
    establishedLinkIdentity = nil
    isConnected = false
    characteristics = [:]
    values = [:]
    subscriptions = [:]
    latestTelemetryInput = nil
    latestTelemetryAt = nil
    latestTelemetryIsComplete = false
    lastPublishedCapability = nil
    frozenAuthorizationSessionID = nil
    if !keepEpoch { epoch = nil }
  }

  private func transmissionContext() -> ProductionTransmissionContext {
    .init(
      authorization: authority.activeAuthorization,
      frozenAuthorizationSessionID: frozenAuthorizationSessionID,
      epoch: epoch,
      foreground: applicationActivity == .active,
      capability: currentCapability,
      profile: executionProfile,
      frozenAttempt: orchestrator.frozenAttempt,
      expectedProcedureID: orchestrator.state.procedure.unresolvedRecord?.id,
      latestTelemetryAt: latestTelemetryAt,
      now: clock.read().monotonic
    )
  }

  private func apply(_ event: WorkoutExecutionEvent) -> WorkoutOrchestrationResult {
    let result = orchestrator.handle(event)
    switch result.state.execution {
    case .finished, .interrupted, .failed:
      authority.invalidateAuthorization()
      controlSuppressedUntilNewConnection = true
      controlTransport.disconnect()
      establishedLinkIdentity = nil
    case .idle, .preflight, .acquiringControl, .waitingForPhysicalStart, .applyingTargets,
      .runningSegment, .checkingTreadmill, .paused, .restoringTargets,
      .awaitingPhysicalStopForCompletion, .readyToEnd, .ending:
      break
    }
    return result
  }

  private func startTicks() {
    guard automaticTicks, tickTimer == nil else { return }
    tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
  }

  private func stopTicks() {
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private static func decimal(_ value: Double) -> Decimal {
    Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? .nan
  }
}

extension WorkoutPlanCapabilities {
  fileprivate static var unavailable: WorkoutPlanCapabilities {
    .init(
      speed: .unknown,
      inclination: .unknown
    )
  }
}
