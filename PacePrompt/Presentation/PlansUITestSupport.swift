#if DEBUG
import Foundation

struct PlansUITestConfiguration {
    let repository: (any SavedPlanRepositoryProtocol)?
    let capabilities: WorkoutPlanCapabilities?
    let makeNewDraft: () -> ManualWorkoutDraft

    static var current: PlansUITestConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard ProcessInfo.processInfo.arguments.contains("--paceprompt-ui-testing") else {
            return PlansUITestConfiguration(
                repository: nil,
                capabilities: nil,
                makeNewDraft: { .empty }
            )
        }

        return PlansUITestConfiguration(
            repository: PlansUITestRepository(scenario: environment["PACEPROMPT_UI_REPOSITORY"]),
            capabilities: capabilities(for: environment["PACEPROMPT_UI_CAPABILITIES"]),
            makeNewDraft: {
                draft(for: environment["PACEPROMPT_UI_DRAFT"])
            }
        )
    }

    private static func capabilities(for scenario: String?) -> WorkoutPlanCapabilities {
        switch scenario {
        case "unsupported":
            return .init(speed: .unsupported, inclination: .unsupported)
        case "malformed":
            return .init(
                speed: .supported(
                    .init(
                        minimum: .init(value: .nan, unit: .kilometresPerHour),
                        maximum: .init(value: .nan, unit: .kilometresPerHour),
                        increment: .init(value: .nan, unit: .kilometresPerHour)
                    )
                ),
                inclination: knownCapabilities().inclination
            )
        case "known":
            return knownCapabilities()
        default:
            return .init(speed: .unknown, inclination: .unknown)
        }
    }

    fileprivate static func draft(for scenario: String?) -> ManualWorkoutDraft {
        guard scenario == "valid" || scenario == "invalid" else { return .empty }
        var draft = ManualWorkoutDraft(
            suggestedName: "Synthetic progression",
            activity: .indoorRunning,
            steps: [
                .init(kind: .warmUp, label: "Prepare", durationSeconds: "360", speedKilometresPerHour: "5.0", inclinationPercent: "0.0"),
                .init(kind: .interval, label: "Effort", durationSeconds: "360", speedKilometresPerHour: "10.5", inclinationPercent: "1.0"),
                .init(kind: .recovery, label: "Recover", durationSeconds: "180", speedKilometresPerHour: "5.0", inclinationPercent: "0.0"),
                .init(kind: .coolDown, label: "Settle", durationSeconds: "360", speedKilometresPerHour: "4.0", inclinationPercent: "0.0"),
            ]
        )
        if scenario == "invalid" {
            draft.steps[1].speedKilometresPerHour = "20.1"
            draft.steps[1].inclinationPercent = "1.2"
        }
        return draft
    }

    fileprivate static func knownCapabilities() -> WorkoutPlanCapabilities {
        .init(
            speed: .supported(
                .init(
                    minimum: .init(value: decimal("0.5"), unit: .kilometresPerHour),
                    maximum: .init(value: decimal("20"), unit: .kilometresPerHour),
                    increment: .init(value: decimal("0.1"), unit: .kilometresPerHour)
                )
            ),
            inclination: .supported(
                .init(
                    minimum: .init(value: decimal("-3"), unit: .percent),
                    maximum: .init(value: decimal("15"), unit: .percent),
                    increment: .init(value: decimal("0.5"), unit: .percent)
                )
            )
        )
    }

    private static func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

private final class PlansUITestRepository: SavedPlanRepositoryProtocol {
    private let scenario: String?
    private var records: [SavedPlanRecord]

    init(scenario: String?) {
        self.scenario = scenario
        records = ["edit-failure", "delete", "delete-failure"].contains(scenario)
            ? [Self.seedRecord()]
            : []
    }

    func list() -> SavedPlanRepositoryStatus {
        switch scenario {
        case "protected":
            .init(canonical: .protectedDataUnavailable, staging: .absent)
        case "corrupt":
            .init(canonical: .corruptData, staging: .absent)
        case "unsupported":
            .init(canonical: .unsupportedStoreVersion(2), staging: .absent)
        case "staging":
            .init(canonical: records.isEmpty ? .empty : .available(records: records), staging: .staleArtifactPresent)
        default:
            .init(canonical: records.isEmpty ? .empty : .available(records: records), staging: .absent)
        }
    }

    func create(_ validatedPlan: WorkoutPlanValidator.ValidatedPlan) throws -> SavedPlanRecord {
        if scenario == "save-failure" {
            throw SavedPlanMutationFailure.writeFailed(.atomicReplacement)
        }
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let record = SavedPlanRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            createdAt: timestamp,
            modifiedAt: timestamp,
            plan: validatedPlan.plan
        )
        records.append(record)
        return record
    }

    func replace(
        id: UUID,
        with validatedPlan: WorkoutPlanValidator.ValidatedPlan
    ) throws -> SavedPlanRecord {
        if scenario == "edit-failure" {
            throw SavedPlanMutationFailure.recordNotFound(id)
        }
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SavedPlanMutationFailure.recordNotFound(id)
        }
        let original = records[index]
        let replacement = SavedPlanRecord(
            id: original.id,
            createdAt: original.createdAt,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            plan: validatedPlan.plan
        )
        records[index] = replacement
        return replacement
    }

    func delete(id: UUID) throws {
        if scenario == "delete-failure" {
            throw SavedPlanMutationFailure.writeFailed(.atomicReplacement)
        }
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SavedPlanMutationFailure.recordNotFound(id)
        }
        records.remove(at: index)
    }

    private static func seedRecord() -> SavedPlanRecord {
        let draft = PlansUITestConfiguration.draft(for: "valid")
        let plan = try! ManualWorkoutDraftParser.parse(
            draft,
            locale: Locale(identifier: "en_GB")
        ).get()
        return SavedPlanRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plan: plan
        )
    }
}
#endif

#if DEBUG
@MainActor
enum ImportUITestConfiguration {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--paceprompt-ui-testing") }
    static func credential() -> ImportCredentialStore { ImportCredentialStore(backend: MemoryKeychain()) }
    static func generator() -> any WorkoutImportGenerating { FixedGenerator() }

    private final class MemoryKeychain: ImportKeychainBackend {
        private var data: Data?
        func contains() throws -> Bool { data != nil }
        func add(_ data: Data) throws { self.data = data }
        func replace(_ data: Data) throws { self.data = data }
        func delete() throws { data = nil }
        func read() throws -> Data { guard let data else { throw ImportFailure.missingCredential }; return data }
    }
    private final class FixedGenerator: WorkoutImportGenerating {
        func generate(_ request: ImportRequestSnapshot, completion: @escaping @MainActor (WorkoutImportOutcome) -> Void) {
            let steps: [WorkoutProposal.Step] = [WorkoutStepKind.warmUp, .interval, .coolDown].map { kind in
                .init(kind: kind, label: "Synthetic \(kind.rawValue)",
                      duration: .init(number: .number("60"), unit: "seconds"),
                      speed: .init(number: .number("5"), unit: "kilometresPerHour"),
                      inclination: .init(number: .number("0"), unit: "percent"))
            }
            completion(.proposal(.init(suggestedName: "Synthetic imported plan", activity: .indoorWalking, steps: steps)))
        }
        func cancel() {}
    }
}
#endif
