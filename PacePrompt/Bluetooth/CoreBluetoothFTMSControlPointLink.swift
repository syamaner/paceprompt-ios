@preconcurrency import CoreBluetooth
import Foundation

/// CoreBluetooth I/O for one already-discovered Fitness Machine Control Point.
///
/// The owning `CBPeripheralDelegate` forwards subscription, write, indication,
/// and disconnect callbacks through the `receive...` methods. No production
/// view, reducer, or orchestration code constructs this type in issue #50.
@MainActor
final class CoreBluetoothFTMSControlPointLink: FTMSControlPointLink {
    var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?

    let supportsWriteWithResponse: Bool
    let supportsIndications: Bool

    private let peripheral: CBPeripheral
    private let characteristic: CBCharacteristic
    private var isValid = true

    init(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        self.peripheral = peripheral
        self.characteristic = characteristic
        let isControlPoint = characteristic.uuid == CBUUID(string: FTMSUUID.fitnessMachineControlPoint)
        supportsWriteWithResponse = isControlPoint && characteristic.properties.contains(.write)
        supportsIndications = isControlPoint && characteristic.properties.contains(.indicate)
    }

    func enableIndications() {
        guard isValid else { return }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func writeWithResponse(_ data: Data) {
        guard isValid else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func invalidate() {
        isValid = false
    }

    func receiveIndicationState(error: Error?) {
        guard isValid else { return }
        if let error {
            eventHandler?(.indicationEnableFailed(error.localizedDescription))
        } else if characteristic.isNotifying {
            eventHandler?(.indicationsEnabled)
        } else {
            eventHandler?(.indicationEnableFailed("CoreBluetooth did not enable indications"))
        }
    }

    func receiveWriteResult(error: Error?) {
        guard isValid else { return }
        guard let error else {
            eventHandler?(.writeAccepted)
            return
        }

        let nsError = error as NSError
        if nsError.domain == CBATTErrorDomain {
            eventHandler?(
                .writeATTRejected(code: nsError.code, message: nsError.localizedDescription)
            )
        } else {
            eventHandler?(.writeDeliveryUnknown(nsError.localizedDescription))
        }
    }

    func receiveIndication(_ data: Data?, error: Error?) {
        guard isValid else { return }
        if let error {
            eventHandler?(.indicationFailed(error.localizedDescription))
        } else if let data {
            eventHandler?(.indication(data))
        } else {
            eventHandler?(.indicationFailed("The Control Point indication contained no value"))
        }
    }

    func receiveDisconnect(error: Error?) {
        guard isValid else { return }
        eventHandler?(.disconnected(error?.localizedDescription))
    }
}
