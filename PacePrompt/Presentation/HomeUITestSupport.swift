#if DEBUG
import Foundation

@MainActor
enum HomeUITestConfiguration {
    static func makeTreadmill() -> TreadmillSetupViewModel {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--paceprompt-home-ui-testing") else {
            return TreadmillSetupViewModel()
        }

        let client = HomeUITestFTMSClient()
        let treadmill = TreadmillSetupViewModel(client: client)
        client.seed(scenario: process.environment["PACEPROMPT_HOME_SCENARIO"])
        return treadmill
    }
}

@MainActor
private final class HomeUITestFTMSClient: FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?

    func startScan() { send(.connection(.scanning)) }
    func stopScan() { send(.connection(.idle)) }
    func connect(to identifier: UUID) {}
    func disconnect() {}

    func seed(scenario: String?) {
        switch scenario {
        case "unauthorised":
            send(.availability(.unauthorized))
        case "failed":
            send(.availability(.poweredOn))
            send(.connection(.failed(message: "Feature read timed out.")))
        case "in-progress":
            seedReadableCharacteristics()
            send(.availability(.poweredOn))
            send(.connection(.connected(name: "Synthetic treadmill")))
        case "connected-evidence":
            seedReadableCharacteristics()
            send(.availability(.poweredOn))
            send(.connection(.connected(name: "Synthetic treadmill")))
            send(.value(uuid: FTMSUUID.fitnessMachineFeature, data: Data([0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00]), source: .initialRead))
            send(.value(uuid: FTMSUUID.supportedSpeedRange, data: Data([0x50, 0x00, 0x40, 0x06, 0x0A, 0x00]), source: .initialRead))
            send(.value(uuid: FTMSUUID.supportedInclinationRange, data: Data([0x00, 0x00, 0x78, 0x00, 0x05, 0x00]), source: .initialRead))
        default:
            send(.availability(.poweredOn))
            send(.connection(.idle))
        }
    }

    private func seedReadableCharacteristics() {
        send(
            .characteristics(
                [
                    .init(uuid: FTMSUUID.fitnessMachineFeature, properties: ["Read"]),
                    .init(uuid: FTMSUUID.supportedSpeedRange, properties: ["Read"]),
                    .init(uuid: FTMSUUID.supportedInclinationRange, properties: ["Read"]),
                ]
            )
        )
    }

    private func send(_ event: FTMSClientEvent) {
        delegate?.ftmsClient(self, didReceive: event)
    }
}
#endif
