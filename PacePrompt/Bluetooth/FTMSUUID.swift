import Foundation

enum FTMSUUID {
    static let service = "1826"
    static let fitnessMachineFeature = "2ACC"
    static let treadmillData = "2ACD"
    static let trainingStatus = "2AD3"
    static let supportedSpeedRange = "2AD4"
    static let supportedInclinationRange = "2AD5"
    static let supportedResistanceLevelRange = "2AD6"
    static let supportedHeartRateRange = "2AD7"
    static let supportedPowerRange = "2AD8"
    static let fitnessMachineControlPoint = "2AD9"
    static let fitnessMachineStatus = "2ADA"

    static let readableCapabilities: Set<String> = [
        fitnessMachineFeature,
        supportedSpeedRange,
        supportedInclinationRange,
    ]

    static let passiveNotifications: Set<String> = [
        treadmillData,
        trainingStatus,
        fitnessMachineStatus,
    ]

    static func name(for uuid: String) -> String {
        switch uuid.uppercased() {
        case service: "Fitness Machine Service"
        case fitnessMachineFeature: "Fitness Machine Feature"
        case treadmillData: "Treadmill Data"
        case trainingStatus: "Training Status"
        case supportedSpeedRange: "Supported Speed Range"
        case supportedInclinationRange: "Supported Inclination Range"
        case supportedResistanceLevelRange: "Supported Resistance Level Range"
        case supportedHeartRateRange: "Supported Heart Rate Range"
        case supportedPowerRange: "Supported Power Range"
        case fitnessMachineControlPoint: "Fitness Machine Control Point"
        case fitnessMachineStatus: "Fitness Machine Status"
        default: "Unknown characteristic"
        }
    }
}
