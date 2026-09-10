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
    private var retainedRequestControlJournalRecords: [RequestControlDiagnosticJournalEntry] = []
#endif

    override init() {
#if DEBUG
        do {
            retainedRequestControlJournalRecords = try RequestControlDiagnosticJournal.readOnlyRecords(
                store: RequestControlDiagnosticJournalFileStore()
            )
        } catch {
            // The completed issue #51 journal is retained as historical evidence.
            // Failure to load it cannot enable or affect the read-only FTMS client.
            retainedRequestControlJournalRecords = []
        }
#endif
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

#if DEBUG
    var requestControlDiagnosticJournalRecords: [RequestControlDiagnosticJournalEntry] {
        retainedRequestControlJournalRecords
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
        centralManager.cancelPeripheralConnection(currentPeripheral)
    }

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
        central.stopScan()
        resetPendingOperations()
        currentPeripheral = nil
        publishInactiveSubscriptions(reason: availability.title)
        if hadActivePeripheral {
            delegate?.ftmsClient(
                self,
                didReceive: .connection(.disconnected(message: availability.title))
            )
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
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        resetPendingOperations()
        currentPeripheral = nil
        publishInactiveSubscriptions(reason: "Disconnected")
        delegate?.ftmsClient(
            self,
            didReceive: .connection(.disconnected(message: error?.localizedDescription))
        )
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

        for uuid in FTMSUUID.passiveNotifications.sorted() {
            guard let characteristic = characteristicsByUUID[uuid] else {
                delegate?.ftmsClient(
                    self,
                    didReceive: .subscription(
                        uuid: uuid,
                        state: .unsupported(reason: "Characteristic was not discovered")
                    )
                )
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
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString.uppercased()
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
            return
        }
        delegate?.ftmsClient(self, didReceive: .value(uuid: uuid, data: value, source: source))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString.uppercased()
        guard FTMSUUID.passiveNotifications.contains(uuid) else { return }

        if let error {
            delegate?.ftmsClient(
                self,
                didReceive: .subscription(uuid: uuid, state: .failed(message: error.localizedDescription))
            )
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
    }
}

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
