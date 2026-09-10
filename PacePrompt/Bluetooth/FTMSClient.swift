@preconcurrency import CoreBluetooth
import Foundation

@MainActor
protocol FTMSClientDelegate: AnyObject {
    func ftmsClient(_ client: any FTMSClientProtocol, didReceive event: FTMSClientEvent)
}

@MainActor
protocol FTMSClientProtocol: AnyObject {
    var delegate: (any FTMSClientDelegate)? { get set }
#if DEBUG
    var requestControlDiagnosticJournalRecords: [RequestControlDiagnosticJournalEntry] { get }
#endif

    func startScan()
    func stopScan()
    func connect(to identifier: UUID)
    func disconnect()
#if DEBUG
    func submitRequestControlDiagnosticOnce()
#endif
}

#if DEBUG
extension FTMSClientProtocol {
    var requestControlDiagnosticJournalRecords: [RequestControlDiagnosticJournalEntry] { [] }
}
#endif

@MainActor
final class FTMSClient: NSObject, FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?

    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var discoveries: [UUID: FTMSDiscoveredDevice] = [:]
    private var currentPeripheral: CBPeripheral?
    private var currentName = "Treadmill"
    private var pendingInitialReads: Set<String> = []
    private var deferredNotificationCharacteristics: [String: CBCharacteristic] = [:]
#if DEBUG
    private let requestControlWriteGate = RequestControlWriteGate()
    private var requestControlJournal: RequestControlDiagnosticJournal?
    private var requestControlJournalFailure: String?
    private var requestControlTransport: FTMSSingleProcedureTransport?
    private var requestControlLink: RequestControlOnlyLink?
    private var requestControlCoreLink: CoreBluetoothFTMSControlPointLink?
    private var requestControlResolvedCapabilityReads: Set<String> = []
    private var requestControlResolvedPassiveSubscriptions: Set<String> = []
    private var requestControlPrerequisiteFailure: String?
    private var requestControlIndicationsConfirmed = false
    private var requestControlEpochSequence: UInt64 = 0
    private var publishedRequestControlOutcomeCount = 0
    private var requestControlReadiness: RequestControlDiagnosticReadiness = .awaitingConnection
#endif

    override init() {
#if DEBUG
        do {
            requestControlJournal = try RequestControlDiagnosticJournal(
                store: RequestControlDiagnosticJournalFileStore()
            )
        } catch {
            requestControlJournalFailure = error.localizedDescription
        }
#endif
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

#if DEBUG
    var requestControlDiagnosticJournalRecords: [RequestControlDiagnosticJournalEntry] {
        requestControlJournal?.records ?? []
    }
#endif

    func startScan() {
        guard centralManager.state == .poweredOn else {
            let availability = Self.availability(from: centralManager.state)
            delegate?.ftmsClient(self, didReceive: .availability(availability))
            delegate?.ftmsClient(
                self,
                didReceive: .connection(.failed(message: availability.title))
            )
            return
        }

        discoveries.removeAll()
        peripherals.removeAll()
        resetPendingOperations()
        publishInactiveSubscriptions(reason: "Not connected")
        delegate?.ftmsClient(self, didReceive: .devices([]))
        delegate?.ftmsClient(self, didReceive: .connection(.scanning))
        centralManager.scanForPeripherals(
            withServices: [CBUUID(string: FTMSUUID.service)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        centralManager.stopScan()
        delegate?.ftmsClient(self, didReceive: .connection(.idle))
    }

    func connect(to identifier: UUID) {
        guard let peripheral = peripherals[identifier] else {
            delegate?.ftmsClient(
                self,
                didReceive: .connection(.failed(message: "The selected treadmill is no longer available. Scan again."))
            )
            return
        }

        centralManager.stopScan()
        resetPendingOperations()
        currentPeripheral = peripheral
        currentName = discoveries[identifier]?.name ?? peripheral.name ?? "Treadmill"
        peripheral.delegate = self
        delegate?.ftmsClient(self, didReceive: .connection(.connecting(name: currentName)))
        publishInactiveSubscriptions(reason: "Awaiting characteristic discovery")
        centralManager.connect(peripheral)
    }

    func disconnect() {
        centralManager.stopScan()
        guard let currentPeripheral else {
            delegate?.ftmsClient(self, didReceive: .connection(.idle))
            return
        }
#if DEBUG
        publishRequestControlDiagnostic(.disconnectRequested)
#endif
        centralManager.cancelPeripheralConnection(currentPeripheral)
    }

#if DEBUG
    func submitRequestControlDiagnosticOnce() {
        guard requestControlReadiness.permitsRequest else {
            publishRequestControlDiagnostic(
                .blocked(requestControlReadiness.detail ?? "The diagnostic is not ready.")
            )
            return
        }
        guard let requestControlTransport else {
            publishRequestControlDiagnostic(.blocked("The single-procedure transport is unavailable."))
            return
        }

        do {
            let id = try requestControlTransport.submit(.requestControl)
            publishRequestControlDiagnostic(.procedureSubmitted(id))
            updateRequestControlReadiness()
        } catch {
            publishRequestControlDiagnostic(.blocked(error.localizedDescription))
            updateRequestControlReadiness()
        }
    }
#endif

    private func publishDiscoveries() {
        let sorted = discoveries.values.sorted {
            if $0.rssi == $1.rssi { return $0.name < $1.name }
            return $0.rssi > $1.rssi
        }
        delegate?.ftmsClient(self, didReceive: .devices(sorted))
    }

    private func publishInactiveSubscriptions(reason: String) {
        for uuid in FTMSUUID.passiveNotifications.sorted() {
            delegate?.ftmsClient(
                self,
                didReceive: .subscription(uuid: uuid, state: .inactive(reason: reason))
            )
        }
    }

    private func resetPendingOperations() {
        pendingInitialReads.removeAll()
        deferredNotificationCharacteristics.removeAll()
#if DEBUG
        resetRequestControlConnectionState()
#endif
    }

    private static func availability(from state: CBManagerState) -> BluetoothAvailability {
        switch state {
        case .unknown: .notDetermined
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unsupported
        }
    }
}

extension FTMSClient: @MainActor CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let availability = Self.availability(from: central.state)
        delegate?.ftmsClient(self, didReceive: .availability(availability))

        guard central.state != .poweredOn else { return }
        let hadActivePeripheral = currentPeripheral != nil
#if DEBUG
        if hadActivePeripheral {
            let disconnectError = NSError(
                domain: "PacePrompt.BluetoothAvailability",
                code: central.state.rawValue,
                userInfo: [NSLocalizedDescriptionKey: availability.title]
            )
            // Preserve pre-ATT delivery uncertainty or post-ATT timeout evidence
            // before clearing the link on a Bluetooth availability transition.
            requestControlCoreLink?.receiveDisconnect(error: disconnectError)
        }
#endif
        central.stopScan()
        resetPendingOperations()
        currentPeripheral = nil
        publishInactiveSubscriptions(reason: availability.title)
        if hadActivePeripheral {
            delegate?.ftmsClient(
                self,
                didReceive: .connection(.disconnected(message: availability.title))
            )
#if DEBUG
            publishRequestControlDiagnostic(.disconnected(availability.title))
#endif
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unnamed FTMS device"
        peripherals[peripheral.identifier] = peripheral
        discoveries[peripheral.identifier] = FTMSDiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )
        publishDiscoveries()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        delegate?.ftmsClient(self, didReceive: .connection(.discovering(name: currentName)))
        peripheral.discoverServices([CBUUID(string: FTMSUUID.service)])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        resetPendingOperations()
        currentPeripheral = nil
        publishInactiveSubscriptions(reason: "Connection failed")
        delegate?.ftmsClient(
            self,
            didReceive: .connection(
                .failed(message: error?.localizedDescription ?? "The connection could not be established.")
            )
        )
#if DEBUG
        publishRequestControlDiagnostic(.disconnected(error?.localizedDescription ?? "Connection failed"))
#endif
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
#if DEBUG
        requestControlCoreLink?.receiveDisconnect(error: error)
#endif
        resetPendingOperations()
        currentPeripheral = nil
        publishInactiveSubscriptions(reason: "Disconnected")
        delegate?.ftmsClient(
            self,
            didReceive: .connection(.disconnected(message: error?.localizedDescription))
        )
#if DEBUG
        // Publish the terminal audit event only after presentation state reflects
        // the disconnect, so the emitted raw report cannot still say Connected.
        publishRequestControlDiagnostic(.disconnected(error?.localizedDescription))
#endif
    }
}

extension FTMSClient: @MainActor CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            delegate?.ftmsClient(self, didReceive: .connection(.failed(message: error.localizedDescription)))
            return
        }

        guard let service = peripheral.services?.first(where: {
            $0.uuid == CBUUID(string: FTMSUUID.service)
        }) else {
            delegate?.ftmsClient(
                self,
                didReceive: .connection(.failed(message: "The Fitness Machine Service was not found."))
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            delegate?.ftmsClient(self, didReceive: .connection(.failed(message: error.localizedDescription)))
            return
        }

        let characteristics = service.characteristics ?? []
        let infos = characteristics.map {
            FTMSCharacteristicInfo(
                uuid: $0.uuid.uuidString.uppercased(),
                properties: $0.properties.displayNames
            )
        }.sorted { $0.uuid < $1.uuid }
        delegate?.ftmsClient(self, didReceive: .characteristics(infos))
        delegate?.ftmsClient(self, didReceive: .connection(.connected(name: currentName)))

        var characteristicsByUUID: [String: CBCharacteristic] = [:]
        for characteristic in characteristics {
            characteristicsByUUID[characteristic.uuid.uuidString.uppercased()] = characteristic
        }

        for (uuid, characteristic) in characteristicsByUUID {
            if FTMSUUID.initialReads.contains(uuid),
               characteristic.properties.contains(.read) {
                pendingInitialReads.insert(uuid)
                peripheral.readValue(for: characteristic)
            }
        }

#if DEBUG
        for uuid in Self.requestControlRequiredCapabilityReads {
            guard let characteristic = characteristicsByUUID[uuid] else {
                requestControlResolvedCapabilityReads.insert(uuid)
                failRequestControlPrerequisite("Required capability 0x\(uuid) was not discovered.")
                continue
            }
            guard characteristic.properties.contains(.read) else {
                requestControlResolvedCapabilityReads.insert(uuid)
                failRequestControlPrerequisite("Required capability 0x\(uuid) was not readable.")
                continue
            }
        }
#endif

        for uuid in FTMSUUID.passiveNotifications.sorted() {
            guard let characteristic = characteristicsByUUID[uuid] else {
                delegate?.ftmsClient(
                    self,
                    didReceive: .subscription(
                        uuid: uuid,
                        state: .unsupported(reason: "Characteristic was not discovered")
                    )
                )
#if DEBUG
                requestControlResolvedPassiveSubscriptions.insert(uuid)
                failRequestControlPrerequisite("Required passive characteristic 0x\(uuid) was not discovered.")
#endif
                continue
            }
            guard characteristic.properties.contains(.notify) else {
                delegate?.ftmsClient(
                    self,
                    didReceive: .subscription(
                        uuid: uuid,
                        state: .unsupported(reason: "Notify property was not discovered")
                    )
                )
#if DEBUG
                requestControlResolvedPassiveSubscriptions.insert(uuid)
                failRequestControlPrerequisite("Required passive characteristic 0x\(uuid) did not expose Notify.")
#endif
                continue
            }
            delegate?.ftmsClient(self, didReceive: .subscription(uuid: uuid, state: .subscribing))
            if uuid == FTMSUUID.trainingStatus,
               pendingInitialReads.contains(uuid) {
                deferredNotificationCharacteristics[uuid] = characteristic
                continue
            }
            peripheral.setNotifyValue(true, for: characteristic)
        }

#if DEBUG
        prepareRequestControlDiagnostic(
            peripheral: peripheral,
            characteristic: characteristicsByUUID[FTMSUUID.fitnessMachineControlPoint]
        )
        updateRequestControlReadiness()
#endif
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString.uppercased()
#if DEBUG
        if uuid == FTMSUUID.fitnessMachineControlPoint {
            if let error {
                publishRequestControlDiagnostic(.indicationFailed(error.localizedDescription))
                requestControlCoreLink?.receiveIndication(nil, error: error)
            } else {
                publishRequestControlDiagnostic(.indication(characteristic.value ?? Data()))
                requestControlCoreLink?.receiveIndication(characteristic.value, error: nil)
            }
            return
        }
#endif
        let wasInitialRead = pendingInitialReads.remove(uuid) != nil
        let source: FTMSValueSource = wasInitialRead
            ? .initialRead
            : .notification
        if wasInitialRead,
           let deferredCharacteristic = deferredNotificationCharacteristics.removeValue(forKey: uuid) {
            peripheral.setNotifyValue(true, for: deferredCharacteristic)
        }
        if let error {
            delegate?.ftmsClient(
                self,
                didReceive: .valueError(uuid: uuid, source: source, message: error.localizedDescription)
            )
#if DEBUG
            if wasInitialRead, Self.requestControlRequiredCapabilityReads.contains(uuid) {
                resolveRequestControlCapabilityRead(uuid: uuid, data: nil, error: error)
            }
#endif
            return
        }
        guard let value = characteristic.value else {
            let message = "The characteristic returned no value."
            delegate?.ftmsClient(
                self,
                didReceive: .valueError(
                    uuid: uuid,
                    source: source,
                    message: message
                )
            )
#if DEBUG
            if wasInitialRead, Self.requestControlRequiredCapabilityReads.contains(uuid) {
                resolveRequestControlCapabilityRead(
                    uuid: uuid,
                    data: nil,
                    error: NSError(
                        domain: "PacePrompt.FTMSCapabilityRead",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                )
            }
#endif
            return
        }
        delegate?.ftmsClient(self, didReceive: .value(uuid: uuid, data: value, source: source))
#if DEBUG
        if wasInitialRead, Self.requestControlRequiredCapabilityReads.contains(uuid) {
            resolveRequestControlCapabilityRead(uuid: uuid, data: value, error: nil)
        }
        if FTMSUUID.passiveNotifications.contains(uuid) {
            validateRequestControlPassiveEvidence(uuid: uuid, data: value)
        }
#endif
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString.uppercased()
#if DEBUG
        if uuid == FTMSUUID.fitnessMachineControlPoint {
            requestControlIndicationsConfirmed = error == nil && characteristic.isNotifying
            if let error {
                publishRequestControlDiagnostic(.indicationSubscriptionFailed(error.localizedDescription))
            } else if characteristic.isNotifying {
                publishRequestControlDiagnostic(.indicationSubscriptionSucceeded)
            } else {
                publishRequestControlDiagnostic(
                    .indicationSubscriptionFailed("CoreBluetooth did not enable indications")
                )
            }
            requestControlCoreLink?.receiveIndicationState(error: error)
            updateRequestControlReadiness()
            return
        }
#endif
        guard FTMSUUID.passiveNotifications.contains(uuid) else { return }

#if DEBUG
        requestControlResolvedPassiveSubscriptions.insert(uuid)
#endif

        if let error {
            delegate?.ftmsClient(
                self,
                didReceive: .subscription(uuid: uuid, state: .failed(message: error.localizedDescription))
            )
#if DEBUG
            failRequestControlPrerequisite(
                "Passive subscription 0x\(uuid) failed: \(error.localizedDescription)"
            )
            updateRequestControlReadiness()
#endif
            return
        }

        let subscribed = characteristic.isNotifying
        delegate?.ftmsClient(
            self,
            didReceive: .subscription(
                uuid: uuid,
                state: subscribed
                    ? .subscribed
                    : .failed(message: "CoreBluetooth did not enable notifications")
            )
        )
#if DEBUG
        if !subscribed {
            failRequestControlPrerequisite(
                "Passive subscription 0x\(uuid) was not enabled by CoreBluetooth."
            )
        }
        updateRequestControlReadiness()
#endif
    }

#if DEBUG
    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == CBUUID(string: FTMSUUID.fitnessMachineControlPoint) else { return }
        if let error {
            let nsError = error as NSError
            if nsError.domain == CBATTErrorDomain {
                publishRequestControlDiagnostic(
                    .attRejected(code: nsError.code, message: nsError.localizedDescription)
                )
            } else {
                publishRequestControlDiagnostic(.writeDeliveryUnknown(nsError.localizedDescription))
            }
        } else {
            publishRequestControlDiagnostic(.attAccepted)
        }
        requestControlCoreLink?.receiveWriteResult(error: error)
    }
#endif
}

#if DEBUG
private extension FTMSClient {
    static let requestControlRequiredCapabilityReads: Set<String> = [
        FTMSUUID.fitnessMachineFeature,
        FTMSUUID.supportedSpeedRange,
        FTMSUUID.supportedInclinationRange,
    ]

    func prepareRequestControlDiagnostic(
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic?
    ) {
        guard let characteristic else {
            setRequestControlReadiness(
                .failed("Fitness Machine Control Point 0x2AD9 was not discovered.")
            )
            return
        }

        let coreLink = CoreBluetoothFTMSControlPointLink(
            peripheral: peripheral,
            characteristic: characteristic
        )
        publishRequestControlDiagnostic(
            .controlPointDiscovered(
                write: coreLink.supportsWriteWithResponse,
                indicate: coreLink.supportsIndications
            )
        )
        guard coreLink.supportsWriteWithResponse, coreLink.supportsIndications else {
            coreLink.invalidate()
            setRequestControlReadiness(
                .failed("Control Point must expose both Write and Indicate.")
            )
            return
        }
        guard let requestControlJournal else {
            coreLink.invalidate()
            setRequestControlReadiness(
                .failed("Protected diagnostic evidence is unavailable. No write is permitted.")
            )
            return
        }

        let restrictedLink = RequestControlOnlyLink(
            underlying: coreLink,
            gate: requestControlWriteGate,
            journal: requestControlJournal
        )
        restrictedLink.requestSubmitted = { [weak self] data in
            self?.publishRequestControlDiagnostic(.requestSubmitted(data))
        }
        restrictedLink.requestBlocked = { [weak self] message in
            self?.publishRequestControlDiagnostic(.blocked(message))
        }

        requestControlEpochSequence += 1
        let epoch = ConnectionEpoch(rawValue: requestControlEpochSequence)
        let transport = FTMSSingleProcedureTransport()
        publishedRequestControlOutcomeCount = 0
        transport.stateHandler = { [weak self] state in
            guard let self else { return }
            if state.outcomes.count > self.publishedRequestControlOutcomeCount {
                for outcome in state.outcomes.dropFirst(self.publishedRequestControlOutcomeCount) {
                    self.publishRequestControlDiagnostic(.outcome(outcome))
                }
                self.publishedRequestControlOutcomeCount = state.outcomes.count
            }
            self.updateRequestControlReadiness()
        }

        requestControlCoreLink = coreLink
        requestControlLink = restrictedLink
        requestControlTransport = transport

        do {
            try transport.establishLink(
                epoch: epoch,
                eligibility: FTMSControlPointEligibility(
                    features: FTMSFeatureFlags(machineFeatures: 0, targetSettingFeatures: 0),
                    speedRange: nil,
                    inclinationRange: nil
                ),
                link: restrictedLink
            )
            try transport.enableIndications()
        } catch {
            restrictedLink.invalidate()
            setRequestControlReadiness(.failed(error.localizedDescription))
        }
    }

    func resetRequestControlConnectionState() {
        requestControlLink?.invalidate()
        requestControlTransport = nil
        requestControlLink = nil
        requestControlCoreLink = nil
        requestControlResolvedCapabilityReads.removeAll()
        requestControlResolvedPassiveSubscriptions.removeAll()
        requestControlPrerequisiteFailure = nil
        requestControlIndicationsConfirmed = false
        publishedRequestControlOutcomeCount = 0
        setRequestControlReadiness(
            requestControlWriteGate.wasConsumed ? .attemptConsumed : .awaitingConnection
        )
    }

    func updateRequestControlReadiness() {
        if let requestControlJournalFailure {
            setRequestControlReadiness(
                .failed("Protected diagnostic evidence is unavailable. \(requestControlJournalFailure)")
            )
            return
        }
        if let requestControlPrerequisiteFailure {
            setRequestControlReadiness(.failed(requestControlPrerequisiteFailure))
            return
        }
        if requestControlWriteGate.wasConsumed {
            setRequestControlReadiness(.attemptConsumed)
            return
        }
        guard currentPeripheral != nil else {
            setRequestControlReadiness(.awaitingConnection)
            return
        }
        guard let requestControlTransport else {
            setRequestControlReadiness(.preparing("Awaiting Control Point discovery."))
            return
        }
        guard requestControlIndicationsConfirmed,
              case .ready = requestControlTransport.state.link else {
            if case let .invalidated(_, reason) = requestControlTransport.state.link {
                setRequestControlReadiness(.failed(reason))
            } else {
                setRequestControlReadiness(.preparing("Awaiting confirmed Control Point indications."))
            }
            return
        }
        guard Self.requestControlRequiredCapabilityReads
            .isSubset(of: requestControlResolvedCapabilityReads) else {
            setRequestControlReadiness(.preparing("Awaiting current feature and range read outcomes."))
            return
        }
        guard FTMSUUID.passiveNotifications
            .isSubset(of: requestControlResolvedPassiveSubscriptions) else {
            setRequestControlReadiness(.preparing("Awaiting all passive subscription outcomes."))
            return
        }
        setRequestControlReadiness(.ready)
    }

    func setRequestControlReadiness(_ readiness: RequestControlDiagnosticReadiness) {
        guard requestControlReadiness != readiness else { return }
        requestControlReadiness = readiness
        publishRequestControlDiagnostic(.readiness(readiness))
    }

    func publishRequestControlDiagnostic(_ event: RequestControlDiagnosticEvent) {
        if requestControlJournalFailure != nil {
            if case .readiness = event {
                delegate?.ftmsClient(self, didReceive: .requestControlDiagnostic(event))
            } else if case .blocked = event {
                delegate?.ftmsClient(self, didReceive: .requestControlDiagnostic(event))
            } else {
                delegate?.ftmsClient(
                    self,
                    didReceive: .requestControlDiagnostic(
                        .blocked("Protected diagnostic evidence remains unavailable. Suppressed event: \(event.reportLine)")
                    )
                )
            }
            return
        }

        guard let requestControlJournal else {
            failRequestControlJournal(
                "The protected diagnostic journal was not initialised.",
                whileRecording: event
            )
            return
        }

        do {
            try requestControlJournal.record(event.journalKind, detail: event.reportLine)
        } catch {
            failRequestControlJournal(error.localizedDescription, whileRecording: event)
            return
        }
        delegate?.ftmsClient(self, didReceive: .requestControlDiagnostic(event))
    }

    func failRequestControlJournal(
        _ detail: String,
        whileRecording event: RequestControlDiagnosticEvent
    ) {
        let message = "Protected diagnostic evidence failed while recording \(event.journalKind.rawValue). No further write is authorised. \(detail)"
        requestControlJournalFailure = message
        if requestControlPrerequisiteFailure == nil {
            requestControlPrerequisiteFailure = message
        }
        requestControlReadiness = .failed(message)
        requestControlLink?.abort(reason: message)
        delegate?.ftmsClient(self, didReceive: .requestControlDiagnostic(.blocked(message)))
        delegate?.ftmsClient(
            self,
            didReceive: .requestControlDiagnostic(.readiness(.failed(message)))
        )
    }

    func resolveRequestControlCapabilityRead(uuid: String, data: Data?, error: Error?) {
        requestControlResolvedCapabilityReads.insert(uuid)
        if let error {
            failRequestControlPrerequisite(
                "Required capability read 0x\(uuid) failed: \(error.localizedDescription)"
            )
            updateRequestControlReadiness()
            return
        }

        do {
            guard let data else {
                throw NSError(
                    domain: "PacePrompt.FTMSCapabilityRead",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No value was returned."]
                )
            }
            switch uuid {
            case FTMSUUID.fitnessMachineFeature:
                _ = try FTMSParser.fitnessMachineFeature(data)
            case FTMSUUID.supportedSpeedRange:
                _ = try FTMSParser.supportedSpeedRange(data)
            case FTMSUUID.supportedInclinationRange:
                _ = try FTMSParser.supportedInclinationRange(data)
            default:
                break
            }
        } catch {
            failRequestControlPrerequisite(
                "Required capability read 0x\(uuid) was malformed: \(error.localizedDescription)"
            )
        }
        updateRequestControlReadiness()
    }

    func validateRequestControlPassiveEvidence(uuid: String, data: Data) {
        do {
            let decoded: FTMSDecodedPacket
            switch uuid {
            case FTMSUUID.treadmillData:
                decoded = .treadmillData(try FTMSParser.treadmillData(data))
            case FTMSUUID.trainingStatus:
                decoded = .trainingStatus(try FTMSParser.trainingStatus(data))
            case FTMSUUID.fitnessMachineStatus:
                let status = try FTMSParser.fitnessMachineStatus(data)
                if status == .controlPermissionLost {
                    abortRequestControlDiagnostic("Fitness Machine Status reported Control Permission Lost (0x2ADA FF).")
                    return
                }
                decoded = .fitnessMachineStatus(status)
            default:
                return
            }
            if decoded.isUnknown {
                abortRequestControlDiagnostic(
                    "Passive characteristic 0x\(uuid) contained an unknown or reserved value."
                )
            }
        } catch {
            abortRequestControlDiagnostic(
                "Passive characteristic 0x\(uuid) was malformed: \(error.localizedDescription)"
            )
        }
    }

    func failRequestControlPrerequisite(_ reason: String) {
        if requestControlPrerequisiteFailure == nil {
            requestControlPrerequisiteFailure = reason
        }
    }

    func abortRequestControlDiagnostic(_ reason: String) {
        failRequestControlPrerequisite(reason)
        publishRequestControlDiagnostic(.blocked("Diagnostic aborted: \(reason)"))
        requestControlLink?.abort(reason: reason)
        updateRequestControlReadiness()
    }
}
#endif

private extension CBCharacteristicProperties {
    var displayNames: [String] {
        var names: [String] = []
        if contains(.read) { names.append("Read") }
        if contains(.notify) { names.append("Notify") }
        if contains(.indicate) { names.append("Indicate") }
        if contains(.write) { names.append("Write") }
        if contains(.writeWithoutResponse) { names.append("Write without response") }
        return names.isEmpty ? ["None"] : names
    }
}
