@preconcurrency import CoreBluetooth
import Foundation

/// The production CoreBluetooth edge for one discovered FTMS Control Point.
/// It cannot choose an opcode, reconnect, retry or infer protocol success.
@MainActor
final class CoreBluetoothFTMSControlPointLink: FTMSControlPointLink {
  weak var peripheral: CBPeripheral?
  let characteristic: CBCharacteristic
  var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?

  private(set) var isValid = true

  init(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
    self.peripheral = peripheral
    self.characteristic = characteristic
  }

  var supportsWriteWithResponse: Bool {
    characteristic.properties.contains(.write)
  }

  var supportsIndications: Bool {
    characteristic.properties.contains(.indicate)
  }

  func enableIndications() {
    guard isValid, let peripheral, peripheral.state == .connected else {
      eventHandler?(.indicationEnableFailed("The Control Point link is not connected"))
      return
    }
    peripheral.setNotifyValue(true, for: characteristic)
  }

  func writeWithResponse(_ data: Data) {
    guard isValid, let peripheral, peripheral.state == .connected else {
      eventHandler?(.writeDeliveryUnknown("The Control Point link is not connected"))
      return
    }
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
  }

  func invalidate() {
    isValid = false
    eventHandler = nil
  }

  func receiveNotificationState(isNotifying: Bool, error: Error?) {
    guard isValid else { return }
    if let error {
      eventHandler?(.indicationEnableFailed(error.localizedDescription))
    } else if isNotifying {
      eventHandler?(.indicationsEnabled)
    } else {
      eventHandler?(.indicationEnableFailed("CoreBluetooth did not enable indications"))
    }
  }

  func receiveWriteResult(_ error: Error?) {
    guard isValid else { return }
    if let error {
      let nsError = error as NSError
      guard nsError.domain == CBATTErrorDomain else {
        eventHandler?(.writeDeliveryUnknown(error.localizedDescription))
        return
      }
      eventHandler?(
        .writeATTRejected(
          code: nsError.code,
          message: error.localizedDescription
        )
      )
    } else {
      eventHandler?(.writeAccepted)
    }
  }

  func receiveIndication(_ value: Data?, error: Error?) {
    guard isValid else { return }
    if let error {
      eventHandler?(.indicationFailed(error.localizedDescription))
    } else if let value {
      eventHandler?(.indication(value))
    } else {
      eventHandler?(.indicationFailed("The Control Point indication contained no value"))
    }
  }

  func receiveDisconnect(_ reason: String?) {
    guard isValid else { return }
    eventHandler?(.disconnected(reason))
    invalidate()
  }
}
