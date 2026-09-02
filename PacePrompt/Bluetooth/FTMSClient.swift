@preconcurrency import CoreBluetooth
import Foundation

@MainActor
protocol FTMSClientDelegate: AnyObject {
    func ftmsClient(_ client: any FTMSClientProtocol, didReceive event: FTMSClientEvent)
}

@MainActor
protocol FTMSClientProtocol: AnyObject {
    var delegate: (any FTMSClientDelegate)? { get set }

    func startScan()
    func stopScan()
    func connect(to identifier: UUID)
    func disconnect()
}

@MainActor
final class FTMSClient: NSObject, FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?

    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var discoveries: [UUID: FTMSDiscoveredDevice] = [:]
    private var currentPeripheral: CBPeripheral?
    private var currentName = "Treadmill"

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

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
        currentPeripheral = peripheral
        currentName = discoveries[identifier]?.name ?? peripheral.name ?? "Treadmill"
        peripheral.delegate = self
        delegate?.ftmsClient(self, didReceive: .connection(.connecting(name: currentName)))
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
        central.stopScan()
        if currentPeripheral != nil {
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
        currentPeripheral = nil
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
        currentPeripheral = nil
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

        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString.uppercased()
            if FTMSUUID.readableCapabilities.contains(uuid),
               characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            if FTMSUUID.passiveNotifications.contains(uuid),
               characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString.uppercased()
        if let error {
            delegate?.ftmsClient(
                self,
                didReceive: .valueError(uuid: uuid, message: error.localizedDescription)
            )
            return
        }
        guard let value = characteristic.value else {
            delegate?.ftmsClient(
                self,
                didReceive: .valueError(uuid: uuid, message: "The characteristic returned no value.")
            )
            return
        }
        delegate?.ftmsClient(self, didReceive: .value(uuid: uuid, data: value))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let error else { return }
        delegate?.ftmsClient(
            self,
            didReceive: .valueError(
                uuid: characteristic.uuid.uuidString.uppercased(),
                message: "Notification subscription failed: \(error.localizedDescription)"
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
