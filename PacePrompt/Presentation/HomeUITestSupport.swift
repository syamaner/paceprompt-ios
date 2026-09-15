#if DEBUG
import Foundation

@MainActor
enum HomeUITestConfiguration {
    static func makeTreadmill() -> TreadmillSetupViewModel {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--paceprompt-home-ui-testing")
            || process.arguments.contains("--paceprompt-workout-session-ui-testing") else {
            return TreadmillSetupViewModel()
        }

        let client = HomeUITestFTMSClient()
        let treadmill = TreadmillSetupViewModel(client: client)
        let scenario = process.environment["PACEPROMPT_HOME_SCENARIO"]
        treadmill.activateUITestScenario = { [weak client] in
            client?.seed(scenario: scenario)
        }
        return treadmill
    }
}

@MainActor
private final class HomeUITestFTMSClient: FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?
    let connectedPeripheralIdentifier: UUID? = UUID(
        uuidString: "00000000-0000-0000-0000-000000000107"
    )
    let connectedPeripheralName: String? = "Synthetic FR30z"
    let controlPointLink: (any FTMSControlPointLink)? = HomeUITestControlPointLink()

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
        case "workout-ready":
            send(.availability(.poweredOn))
            send(.connection(.connecting(name: "Synthetic FR30z")))
            send(.connection(.connected(name: "Synthetic FR30z")))
            send(
                .characteristics(
                    [
                        .init(uuid: FTMSUUID.fitnessMachineFeature, properties: ["Read"]),
                        .init(uuid: FTMSUUID.treadmillData, properties: ["Notify"]),
                        .init(uuid: FTMSUUID.trainingStatus, properties: ["Read", "Notify"]),
                        .init(uuid: FTMSUUID.supportedSpeedRange, properties: ["Read"]),
                        .init(uuid: FTMSUUID.supportedInclinationRange, properties: ["Read"]),
                        .init(
                            uuid: FTMSUUID.fitnessMachineControlPoint,
                            properties: ["Write", "Indicate"]
                        ),
                        .init(uuid: FTMSUUID.fitnessMachineStatus, properties: ["Notify"]),
                    ]
                )
            )
            for uuid in [
                FTMSUUID.treadmillData,
                FTMSUUID.trainingStatus,
                FTMSUUID.fitnessMachineStatus,
            ] {
                send(.subscription(uuid: uuid, state: .subscribed))
            }
            send(
                .value(
                    uuid: FTMSUUID.fitnessMachineFeature,
                    data: Data([0x0C, 0x16, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00]),
                    source: .initialRead
                )
            )
            send(
                .value(
                    uuid: FTMSUUID.supportedSpeedRange,
                    data: Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00]),
                    source: .initialRead
                )
            )
            send(
                .value(
                    uuid: FTMSUUID.supportedInclinationRange,
                    data: Data([0x00, 0x00, 0x96, 0x00, 0x0A, 0x00]),
                    source: .initialRead
                )
            )
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

@MainActor
private final class HomeUITestControlPointLink: FTMSControlPointLink {
    let supportsWriteWithResponse = true
    let supportsIndications = true
    var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?

    func enableIndications() {
        eventHandler?(.indicationsEnabled)
    }
    func writeWithResponse(_ data: Data) {}
    func invalidate() { eventHandler = nil }
}
#endif
