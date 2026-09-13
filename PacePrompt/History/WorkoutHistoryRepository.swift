import Foundation

enum WorkoutHistoryStoreSchema {
    static let currentVersion = 1
}

struct WorkoutHistoryStore: Codable, Equatable {
    let formatVersion: Int
    let summaries: [WorkoutExecutionSummary]
}

enum WorkoutHistoryCanonicalState: Equatable {
    case empty
    case available(summaries: [WorkoutExecutionSummary])
    case protectedDataUnavailable
    case readFailure
    case corruptData
    case partialWriteDetected
    case unsupportedStoreVersion(Int)
    case unsupportedSummaryVersion(summaryID: UUID, version: Int)
    case unsupportedPlanVersion(summaryID: UUID, version: Int)
}

enum WorkoutHistoryStagingState: Equatable {
    case absent
    case staleArtifactPresent
    case presenceUnavailable
}

struct WorkoutHistoryRepositoryStatus: Equatable {
    let canonical: WorkoutHistoryCanonicalState
    let staging: WorkoutHistoryStagingState
}

enum WorkoutHistoryMutationFailure: Error, Equatable {
    enum WriteStage: Equatable {
        case encoding
        case directoryPreparation
        case fileProtection
        case backupExclusion
        case stagingWrite
        case stagingValidation
        case synchronization
        case atomicReplacement
    }

    case blocked(WorkoutHistoryRepositoryStatus)
    case invalidSummary
    case immutableAttemptFieldsChanged(UUID)
    case staleUpdate(UUID)
    case unexpectedRepositoryFailure
    case writeFailed(WriteStage)
}

enum WorkoutHistoryFileSystemError: Error {
    case protectedDataUnavailable
}

protocol WorkoutHistoryFileSystem {
    func applicationSupportDirectory() throws -> URL
    func fileExists(at url: URL) throws -> Bool
    func createProtectedDirectory(at url: URL) throws
    func readData(at url: URL) throws -> Data
    func writeProtectedData(_ data: Data, to url: URL) throws
    func synchronizeFile(at url: URL) throws
    func applyCompleteFileProtection(to url: URL) throws
    func hasCompleteFileProtection(at url: URL) throws -> Bool
    func excludeFromBackup(_ url: URL) throws
    func isExcludedFromBackup(_ url: URL) throws -> Bool
    func atomicallyReplaceItem(at canonicalURL: URL, with stagingURL: URL) throws
}

struct FoundationWorkoutHistoryFileSystem: WorkoutHistoryFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func applicationSupportDirectory() throws -> URL {
        try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    func fileExists(at url: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: url.path)
            return true
        } catch {
            let cocoaError = error as NSError
            guard cocoaError.domain == NSCocoaErrorDomain,
                  cocoaError.code == CocoaError.fileNoSuchFile.rawValue
                    || cocoaError.code == CocoaError.fileReadNoSuchFile.rawValue else {
                throw error
            }
            return false
        }
    }

    func createProtectedDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
    }

    func readData(at url: URL) throws -> Data { try Data(contentsOf: url) }
    func writeProtectedData(_ data: Data, to url: URL) throws { try data.write(to: url, options: .completeFileProtection) }

    func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func applyCompleteFileProtection(to url: URL) throws {
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.protectionKey] as? FileProtectionType) == .complete
    }

    func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    func atomicallyReplaceItem(at canonicalURL: URL, with stagingURL: URL) throws {
        if try fileExists(at: canonicalURL) {
            _ = try fileManager.replaceItemAt(canonicalURL, withItemAt: stagingURL, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: stagingURL, to: canonicalURL)
        }
    }
}

protocol WorkoutHistoryStoreCoding {
    func encode(_ store: WorkoutHistoryStore) throws -> Data
    func decodeFormatVersion(from data: Data) throws -> Int
    func decodeStore(from data: Data) throws -> WorkoutHistoryStore
}

struct WorkoutHistoryJSONCodec: WorkoutHistoryStoreCoding {
    func encode(_ store: WorkoutHistoryStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(store)
    }

    func decodeFormatVersion(from data: Data) throws -> Int {
        try JSONDecoder().decode(StoreHeader.self, from: data).formatVersion
    }

    func decodeStore(from data: Data) throws -> WorkoutHistoryStore {
        try JSONDecoder().decode(WorkoutHistoryStore.self, from: data)
    }

    private struct StoreHeader: Decodable { let formatVersion: Int }
}

protocol WorkoutHistoryRepositoryProtocol {
    func list() -> WorkoutHistoryRepositoryStatus
    func record(_ summary: WorkoutExecutionSummary) throws
    func updateHealthExport(summaryID: UUID, state: WorkoutHealthExportState) throws
}

extension WorkoutHistoryRepositoryProtocol {
    func updateHealthExport(summaryID: UUID, state: WorkoutHealthExportState) throws {
        guard case let .available(summaries) = list().canonical,
              let summary = summaries.first(where: { $0.id == summaryID }) else {
            throw WorkoutHistoryMutationFailure.invalidSummary
        }
        try record(summary.replacingHealthExport(with: state))
    }
}

final class WorkoutHistoryRepository: WorkoutHistoryRepositoryProtocol {
    private enum FileName {
        static let directory = "PacePrompt"
        static let canonical = "workout-history.json"
        static let staging = "workout-history.json.staging"
    }

    private let fileSystem: any WorkoutHistoryFileSystem
    private let codec: any WorkoutHistoryStoreCoding

    init(
        fileSystem: any WorkoutHistoryFileSystem = FoundationWorkoutHistoryFileSystem(),
        codec: any WorkoutHistoryStoreCoding = WorkoutHistoryJSONCodec()
    ) {
        self.fileSystem = fileSystem
        self.codec = codec
    }

    func list() -> WorkoutHistoryRepositoryStatus {
        let urls: StoreURLs
        do {
            urls = try storeURLs()
        } catch {
            return .init(canonical: canonicalReadState(for: error), staging: .presenceUnavailable)
        }

        let staging: WorkoutHistoryStagingState
        do {
            staging = try fileSystem.fileExists(at: urls.staging) ? .staleArtifactPresent : .absent
        } catch {
            staging = .presenceUnavailable
        }

        do {
            guard try fileSystem.fileExists(at: urls.canonical) else {
                return .init(canonical: .empty, staging: staging)
            }
            return .init(canonical: decodeCanonical(try fileSystem.readData(at: urls.canonical)), staging: staging)
        } catch {
            return .init(canonical: canonicalReadState(for: error), staging: staging)
        }
    }

    func record(_ summary: WorkoutExecutionSummary) throws {
        guard summaryIsStructurallyValid(summary) else {
            throw WorkoutHistoryMutationFailure.invalidSummary
        }

        var summaries = try summariesForMutation()
        if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
            let existing = summaries[index]
            guard immutableFieldsMatch(existing, summary) else {
                throw WorkoutHistoryMutationFailure.immutableAttemptFieldsChanged(summary.id)
            }
            guard summary.lastUpdatedAt >= existing.lastUpdatedAt else {
                throw WorkoutHistoryMutationFailure.staleUpdate(summary.id)
            }
            summaries[index] = summary
        } else {
            summaries.append(summary)
        }
        try persist(summaries)
    }

    func updateHealthExport(summaryID: UUID, state: WorkoutHealthExportState) throws {
        var summaries = try summariesForMutation()
        guard let index = summaries.firstIndex(where: { $0.id == summaryID }) else {
            throw WorkoutHistoryMutationFailure.invalidSummary
        }
        let existing = summaries[index]
        guard existing.schemaVersion == WorkoutExecutionSummarySchema.currentVersion,
              let previous = existing.healthExport,
              healthExportTransitionIsValid(from: previous, to: state) else {
            throw WorkoutHistoryMutationFailure.invalidSummary
        }
        let updated = existing.replacingHealthExport(with: state)
        guard summaryIsStructurallyValid(updated) else {
            throw WorkoutHistoryMutationFailure.invalidSummary
        }
        summaries[index] = updated
        try persist(summaries)
    }

    private func healthExportTransitionIsValid(
        from previous: WorkoutHealthExportState,
        to next: WorkoutHealthExportState
    ) -> Bool {
        switch (previous, next) {
        case (.notRequested, .pending(_, 1)),
             (.notRequested, .unavailable),
             (.denied, .pending(_, 1)),
             (.unavailable, .pending(_, 1)):
            return true
        case let (.pending(_, previousVersion), .saved(_, nextVersion, _, _, _)),
             let (.pending(_, previousVersion), .failedRetryable(_, nextVersion)),
             let (.pending(_, previousVersion), .failedAmbiguous(_, nextVersion)):
            return previousVersion == nextVersion
        case (.pending, .denied), (.pending, .unavailable):
            return true
        case let (.failedRetryable(_, previousVersion), .pending(_, nextVersion)):
            return nextVersion == previousVersion + 1
        case let (.failedAmbiguous(_, previousVersion), .pending(_, nextVersion)):
            return nextVersion == previousVersion + 1
        case let (.pending(_, previousVersion), .pending(_, nextVersion)):
            return nextVersion == previousVersion + 1
        case let (.saved(previousDate, previousVersion, previousUUID, previousCount, previousDistance),
                  .saved(nextDate, nextVersion, nextUUID, nextCount, nextDistance)):
            return previousDate == nextDate && previousVersion == nextVersion
                && previousUUID == nextUUID && previousCount == nextCount
                && previousDistance == nextDistance
        default:
            return false
        }
    }

    private func summariesForMutation() throws -> [WorkoutExecutionSummary] {
        let status = list()
        guard status.staging == .absent else {
            throw WorkoutHistoryMutationFailure.blocked(status)
        }
        switch status.canonical {
        case .empty:
            return []
        case let .available(summaries):
            return summaries
        case .protectedDataUnavailable, .readFailure, .corruptData, .partialWriteDetected,
             .unsupportedStoreVersion, .unsupportedSummaryVersion, .unsupportedPlanVersion:
            throw WorkoutHistoryMutationFailure.blocked(status)
        }
    }

    private func persist(_ summaries: [WorkoutExecutionSummary]) throws {
        let data: Data
        do {
            data = try codec.encode(.init(formatVersion: WorkoutHistoryStoreSchema.currentVersion, summaries: summaries))
        } catch {
            throw WorkoutHistoryMutationFailure.writeFailed(.encoding)
        }

        let urls: StoreURLs
        do {
            urls = try storeURLs()
            try fileSystem.createProtectedDirectory(at: urls.directory)
        } catch {
            throw WorkoutHistoryMutationFailure.writeFailed(.directoryPreparation)
        }
        try applyAndVerifyProtection(to: urls.directory)
        try applyAndVerifyBackupExclusion(to: urls.directory)

        do { try fileSystem.writeProtectedData(data, to: urls.staging) }
        catch { throw WorkoutHistoryMutationFailure.writeFailed(.stagingWrite) }

        do {
            let stagedData = try fileSystem.readData(at: urls.staging)
            let expected: WorkoutHistoryCanonicalState = summaries.isEmpty ? .empty : .available(summaries: summaries)
            guard decodeCanonical(stagedData) == expected else {
                throw WorkoutHistoryMutationFailure.writeFailed(.stagingValidation)
            }
        } catch let failure as WorkoutHistoryMutationFailure {
            throw failure
        } catch {
            throw WorkoutHistoryMutationFailure.writeFailed(.stagingValidation)
        }

        do { try fileSystem.synchronizeFile(at: urls.staging) }
        catch { throw WorkoutHistoryMutationFailure.writeFailed(.synchronization) }

        try applyAndVerifyProtection(to: urls.staging)
        try applyAndVerifyBackupExclusion(to: urls.staging)

        do { try fileSystem.atomicallyReplaceItem(at: urls.canonical, with: urls.staging) }
        catch { throw WorkoutHistoryMutationFailure.writeFailed(.atomicReplacement) }
    }

    private func applyAndVerifyProtection(to url: URL) throws {
        do {
            try fileSystem.applyCompleteFileProtection(to: url)
            guard try fileSystem.hasCompleteFileProtection(at: url) else {
                throw WorkoutHistoryMutationFailure.writeFailed(.fileProtection)
            }
        } catch let failure as WorkoutHistoryMutationFailure { throw failure }
        catch { throw WorkoutHistoryMutationFailure.writeFailed(.fileProtection) }
    }

    private func applyAndVerifyBackupExclusion(to url: URL) throws {
        do {
            try fileSystem.excludeFromBackup(url)
            guard try fileSystem.isExcludedFromBackup(url) else {
                throw WorkoutHistoryMutationFailure.writeFailed(.backupExclusion)
            }
        } catch let failure as WorkoutHistoryMutationFailure { throw failure }
        catch { throw WorkoutHistoryMutationFailure.writeFailed(.backupExclusion) }
    }

    private func decodeCanonical(_ data: Data) -> WorkoutHistoryCanonicalState {
        let formatVersion: Int
        do { formatVersion = try codec.decodeFormatVersion(from: data) }
        catch { return appearsTruncatedJSON(data) ? .partialWriteDetected : .corruptData }

        guard formatVersion == WorkoutHistoryStoreSchema.currentVersion else {
            return .unsupportedStoreVersion(formatVersion)
        }

        let versions = nestedVersions(in: data)
        if let unsupported = versions.summary {
            return .unsupportedSummaryVersion(summaryID: unsupported.id, version: unsupported.version)
        }
        if let unsupported = versions.plan {
            return .unsupportedPlanVersion(summaryID: unsupported.id, version: unsupported.version)
        }
        guard hasExpectedShape(data) else { return .corruptData }

        let store: WorkoutHistoryStore
        do { store = try codec.decodeStore(from: data) }
        catch { return appearsTruncatedJSON(data) ? .partialWriteDetected : .corruptData }

        guard summariesAreStructurallyValid(store.summaries) else { return .corruptData }
        return store.summaries.isEmpty ? .empty : .available(summaries: store.summaries)
    }

    private func summariesAreStructurallyValid(_ summaries: [WorkoutExecutionSummary]) -> Bool {
        var identifiers = Set<UUID>()
        return summaries.allSatisfy { identifiers.insert($0.id).inserted && summaryIsStructurallyValid($0) }
    }

    private func summaryIsStructurallyValid(_ summary: WorkoutExecutionSummary) -> Bool {
        guard WorkoutExecutionSummarySchema.supportedVersions.contains(summary.schemaVersion),
              summary.planSnapshot.schemaVersion == WorkoutPlanSchema.currentVersion,
              WorkoutPlanValidator.structuralIssues(in: summary.planSnapshot).isEmpty,
              summary.attemptedAt <= summary.lastUpdatedAt,
              summary.progress.completedStepCount >= 0,
              summary.progress.completedStepCount <= summary.planSnapshot.steps.count,
              summary.progress.activeSecondsInCurrentStep >= 0 else { return false }

        if let index = summary.progress.currentStepIndex,
           !(summary.planSnapshot.steps.indices.contains(index)) { return false }

        switch summary.outcome {
        case .inProgress, .completed: break
        case let .stoppedByUser(reason), let .interrupted(reason), let .failed(reason):
            guard reasonIsValid(reason) else { return false }
        }
        switch summary.activeDuration {
        case let .measured(seconds): guard seconds >= 0 else { return false }
        case let .unavailable(reason): guard reasonIsValid(reason) else { return false }
        }
        switch summary.distance {
        case let .measured(metres):
            guard summary.schemaVersion == WorkoutExecutionSummarySchema.legacyVersion,
                  metres.isFinite, metres >= 0 else { return false }
        case let .measuredWithProvenance(metres, provenance):
            guard summary.schemaVersion == WorkoutExecutionSummarySchema.currentVersion,
                  metres.isFinite, metres >= 0,
                  provenance.startCumulativeMetres.isFinite,
                  provenance.finalCumulativeMetres.isFinite,
                  provenance.startCumulativeMetres >= 0,
                  provenance.finalCumulativeMetres >= provenance.startCumulativeMetres,
                  provenance.finalCumulativeMetres - provenance.startCumulativeMetres == metres,
                  provenance.startObservedAt >= summary.attemptedAt,
                  provenance.finalObservedAt >= provenance.startObservedAt,
                  provenance.finalObservedAt <= summary.lastUpdatedAt else { return false }
        case let .unavailable(reason): guard reasonIsValid(reason) else { return false }
        }
        if case let .humanConfirmed(at) = summary.physicalStopConfirmation,
           at < summary.attemptedAt || at > summary.lastUpdatedAt { return false }
        if summary.schemaVersion == WorkoutExecutionSummarySchema.legacyVersion {
            guard summary.activityTimeline == nil, summary.healthExport == nil else { return false }
            if case .measuredWithProvenance = summary.distance { return false }
            return true
        }
        guard let timeline = summary.activityTimeline,
              let healthExport = summary.healthExport,
              timelineIsStructurallyValid(timeline, for: summary),
              healthExportIsStructurallyValid(healthExport, timeline: timeline) else { return false }
        if case let .measuredWithProvenance(_, provenance) = summary.distance {
            guard case let .recorded(startedAt, endedAt, _, _) = timeline,
                  provenance.startObservedAt == startedAt,
                  provenance.finalObservedAt >= endedAt else { return false }
        }
        return true
    }

    private func reasonIsValid(_ reason: WorkoutExecutionReasonCode) -> Bool {
        !reason.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func timelineIsStructurallyValid(
        _ timeline: WorkoutActivityTimeline,
        for summary: WorkoutExecutionSummary
    ) -> Bool {
        switch timeline {
        case let .unavailable(reason):
            return reasonIsValid(reason)
        case let .recorded(startedAt, endedAt, provenance, intervals):
            guard provenance == .executionClock, !intervals.isEmpty,
                  startedAt == intervals.first?.startedAt,
                  endedAt == intervals.last?.endedAt,
                  startedAt >= summary.attemptedAt,
                  endedAt <= summary.lastUpdatedAt,
                  startedAt < endedAt else { return false }
            var previousEnd: Date?
            var previousSegmentIndex: Int?
            var nextIntervalIndex: [Int: Int] = [:]
            var duration: TimeInterval = 0
            for interval in intervals {
                guard summary.planSnapshot.steps.indices.contains(interval.segmentIndex),
                      previousSegmentIndex.map({ interval.segmentIndex >= $0 }) ?? true,
                      interval.intervalIndex == nextIntervalIndex[interval.segmentIndex, default: 0],
                      interval.startedAt < interval.endedAt,
                      interval.startedAt >= startedAt,
                      interval.endedAt <= endedAt else { return false }
                if let previousEnd, interval.startedAt < previousEnd { return false }
                let step = summary.planSnapshot.steps[interval.segmentIndex]
                guard interval.prescribed.kind == step.kind,
                      interval.prescribed.speedKilometresPerHour == step.targetSpeed.value,
                      interval.prescribed.inclinationPercent == step.targetInclination.value,
                      interval.effectiveSpeed.source != .planned
                        || interval.effectiveSpeed.kilometresPerHour
                          == interval.prescribed.speedKilometresPerHour,
                      interval.effectiveInclination.source != .planned
                        || interval.effectiveInclination.percent
                          == interval.prescribed.inclinationPercent,
                      interval.effectiveSpeed.kilometresPerHour.isFinite,
                      interval.effectiveInclination.percent.isFinite,
                      interval.settledObservation.speedKilometresPerHour.isFinite,
                      interval.settledObservation.inclinationPercent.isFinite,
                      interval.settledObservation.observedAt == interval.startedAt,
                      interval.settledObservation.speedKilometresPerHour
                        == interval.effectiveSpeed.kilometresPerHour,
                      interval.settledObservation.inclinationPercent
                        == interval.effectiveInclination.percent else { return false }
                nextIntervalIndex[interval.segmentIndex, default: 0] += 1
                previousEnd = interval.endedAt
                previousSegmentIndex = interval.segmentIndex
                duration += interval.endedAt.timeIntervalSince(interval.startedAt)
            }
            guard case let .measured(seconds) = summary.activeDuration else { return false }
            return Int(floor(duration + 0.000_000_001)) == seconds
        }
    }

    private func healthExportIsStructurallyValid(
        _ state: WorkoutHealthExportState,
        timeline: WorkoutActivityTimeline
    ) -> Bool {
        switch state {
        case .notRequested, .denied, .unavailable:
            return true
        case let .pending(_, version), let .failedRetryable(_, version),
             let .failedAmbiguous(_, version):
            return version > 0
        case let .saved(_, version, _, count, _):
            guard case let .recorded(_, _, _, intervals) = timeline else { return false }
            return version > 0 && count == intervals.count
        }
    }

    private func immutableFieldsMatch(_ lhs: WorkoutExecutionSummary, _ rhs: WorkoutExecutionSummary) -> Bool {
        lhs.id == rhs.id && lhs.schemaVersion == rhs.schemaVersion && lhs.sourcePlanID == rhs.sourcePlanID
            && lhs.planSnapshot == rhs.planSnapshot && lhs.attemptedAt == rhs.attemptedAt
    }

    private func hasExpectedShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["formatVersion", "summaries"],
              let summaries = root["summaries"] as? [[String: Any]] else { return false }
        return summaries.allSatisfy(summaryHasExpectedShape)
    }

    private func summaryHasExpectedShape(_ value: [String: Any]) -> Bool {
        let base = Set(["id", "schemaVersion", "planSnapshot", "attemptedAt", "lastUpdatedAt", "outcome", "activeDuration", "distance", "progress", "physicalStopConfirmation"])
        guard let schemaVersion = value["schemaVersion"] as? Int else { return false }
        let required = schemaVersion == WorkoutExecutionSummarySchema.currentVersion
            ? base.union(["activityTimeline", "healthExport"]) : base
        let allowed = required.union(["sourcePlanID"])
        guard Set(value.keys).isSubset(of: allowed), required.isSubset(of: Set(value.keys)),
              let plan = value["planSnapshot"] as? [String: Any], planHasExpectedShape(plan),
              let outcome = value["outcome"] as? [String: Any], taggedObjectHasExpectedShape(outcome, valueKey: "reasonCode", valueRequiredFor: ["stoppedByUser", "interrupted", "failed"]),
              let duration = value["activeDuration"] as? [String: Any], taggedObjectHasExpectedShape(duration, valueKey: "seconds", valueRequiredFor: ["measured"], alternateKey: "reasonCode", alternateRequiredFor: ["unavailable"]),
              let distance = value["distance"] as? [String: Any], distanceHasExpectedShape(distance),
              let progress = value["progress"] as? [String: Any], Set(progress.keys).isSubset(of: ["completedStepCount", "currentStepIndex", "activeSecondsInCurrentStep"]), Set(["completedStepCount", "activeSecondsInCurrentStep"]).isSubset(of: Set(progress.keys)),
              let stop = value["physicalStopConfirmation"] as? [String: Any], taggedObjectHasExpectedShape(stop, valueKey: "confirmedAt", valueRequiredFor: ["humanConfirmed"]) else { return false }
        if schemaVersion == WorkoutExecutionSummarySchema.currentVersion {
            guard let timeline = value["activityTimeline"] as? [String: Any],
                  activityTimelineHasExpectedShape(timeline),
                  let healthExport = value["healthExport"] as? [String: Any],
                  healthExportHasExpectedShape(healthExport) else { return false }
        }
        return true
    }

    private func distanceHasExpectedShape(_ value: [String: Any]) -> Bool {
        guard let state = value["state"] as? String else { return false }
        if state == "unavailable" { return Set(value.keys) == ["state", "reasonCode"] }
        guard state == "measured" else { return false }
        let keys = Set(value.keys)
        if keys == ["state", "metres"] { return true }
        guard keys == ["state", "metres", "provenance"],
              let provenance = value["provenance"] as? [String: Any] else { return false }
        return Set(provenance.keys) == [
            "method", "startCumulativeMetres", "startObservedAt",
            "finalCumulativeMetres", "finalObservedAt"
        ]
    }

    private func activityTimelineHasExpectedShape(_ value: [String: Any]) -> Bool {
        guard let state = value["state"] as? String else { return false }
        if state == "unavailable" { return Set(value.keys) == ["state", "reasonCode"] }
        guard state == "recorded",
              Set(value.keys) == [
                "state", "startedAt", "endedAt", "timingProvenance", "executedIntervals"
              ],
              let intervals = value["executedIntervals"] as? [[String: Any]] else { return false }
        return intervals.allSatisfy { interval in
            guard Set(interval.keys) == [
                "segmentIndex", "intervalIndex", "startedAt", "endedAt", "prescribed",
                "effectiveSpeed", "effectiveInclination", "settledObservation", "endReason"
            ], let prescribed = interval["prescribed"] as? [String: Any],
               Set(prescribed.keys) == [
                "kind", "speedKilometresPerHour", "inclinationPercent"
               ], let speed = interval["effectiveSpeed"] as? [String: Any],
               Set(speed.keys) == ["kilometresPerHour", "source"],
               let inclination = interval["effectiveInclination"] as? [String: Any],
               Set(inclination.keys) == ["percent", "source"],
               let observation = interval["settledObservation"] as? [String: Any],
               Set(observation.keys) == [
                "observedAt", "speedKilometresPerHour", "inclinationPercent", "provenance"
               ] else { return false }
            return true
        }
    }

    private func healthExportHasExpectedShape(_ value: [String: Any]) -> Bool {
        guard let state = value["state"] as? String else { return false }
        let expected: Set<String>
        switch state {
        case "notRequested": expected = ["state"]
        case "pending": expected = ["state", "attemptedAt", "syncVersion"]
        case "saved": expected = [
            "state", "savedAt", "syncVersion", "workoutUUID", "mirroredIntervalCount",
            "distanceIncluded"
        ]
        case "denied": expected = ["state", "writeType"]
        case "unavailable": expected = ["state", "category"]
        case "failedRetryable", "failedAmbiguous": expected = ["state", "category", "syncVersion"]
        default: return false
        }
        return Set(value.keys) == expected
    }

    private func taggedObjectHasExpectedShape(
        _ value: [String: Any],
        valueKey: String,
        valueRequiredFor: Set<String>,
        alternateKey: String? = nil,
        alternateRequiredFor: Set<String> = []
    ) -> Bool {
        guard let state = value["state"] as? String else { return false }
        var expected: Set<String> = ["state"]
        if valueRequiredFor.contains(state) { expected.insert(valueKey) }
        if alternateRequiredFor.contains(state), let alternateKey { expected.insert(alternateKey) }
        return Set(value.keys) == expected
    }

    private func planHasExpectedShape(_ plan: [String: Any]) -> Bool {
        guard Set(plan.keys) == ["schemaVersion", "suggestedName", "activity", "steps"],
              let steps = plan["steps"] as? [[String: Any]] else { return false }
        return steps.allSatisfy { step in
            guard Set(step.keys) == ["kind", "label", "duration", "targetSpeed", "targetInclination"],
                  let duration = step["duration"] as? [String: Any], Set(duration.keys) == ["value", "unit"],
                  let speed = step["targetSpeed"] as? [String: Any], Set(speed.keys) == ["value", "unit"],
                  let inclination = step["targetInclination"] as? [String: Any], Set(inclination.keys) == ["value", "unit"] else { return false }
            return true
        }
    }

    private func nestedVersions(in data: Data) -> (summary: (id: UUID, version: Int)?, plan: (id: UUID, version: Int)?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summaries = root["summaries"] as? [[String: Any]] else { return (nil, nil) }
        for summary in summaries {
            guard let idText = summary["id"] as? String, let id = UUID(uuidString: idText) else { continue }
            if let version = summary["schemaVersion"] as? Int,
               !WorkoutExecutionSummarySchema.supportedVersions.contains(version) {
                return ((id, version), nil)
            }
            if let plan = summary["planSnapshot"] as? [String: Any], let version = plan["schemaVersion"] as? Int,
               version != WorkoutPlanSchema.currentVersion { return (nil, (id, version)) }
        }
        return (nil, nil)
    }

    private func appearsTruncatedJSON(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard let first = bytes.first(where: { !Self.isJSONWhitespace($0) }) else { return true }
        guard first == UInt8(ascii: "{") || first == UInt8(ascii: "[") else { return false }
        var depth = 0
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth < 0 { return false }
            default: break
            }
        }
        return inString || depth > 0
    }

    private func canonicalReadState(for error: Error) -> WorkoutHistoryCanonicalState {
        if let historyError = error as? WorkoutHistoryFileSystemError, case .protectedDataUnavailable = historyError {
            return .protectedDataUnavailable
        }
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == CocoaError.fileReadNoPermission.rawValue
            ? .protectedDataUnavailable : .readFailure
    }

    private func storeURLs() throws -> StoreURLs {
        let directory = try fileSystem.applicationSupportDirectory().appendingPathComponent(FileName.directory, isDirectory: true)
        return .init(
            directory: directory,
            canonical: directory.appendingPathComponent(FileName.canonical),
            staging: directory.appendingPathComponent(FileName.staging)
        )
    }

    private struct StoreURLs { let directory: URL; let canonical: URL; let staging: URL }
    private static func isJSONWhitespace(_ byte: UInt8) -> Bool { [0x20, 0x09, 0x0A, 0x0D].contains(byte) }
}
