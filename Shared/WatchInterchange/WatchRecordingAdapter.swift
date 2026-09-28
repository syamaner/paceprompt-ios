import Foundation

struct WatchRecoveredRecording {
    let start: Date
    let activity: String
    let indoor: Bool
}

@MainActor protocol WatchSessionOperations: WatchBuilderOperations {
    func resetForNewAttempt() throws
    func authorize() async throws -> Bool
    func recoverPrimary() async throws -> WatchRecoveredRecording?
    func createPrimary(activity: String) throws
    func configureCollection() throws
    func preparePrimary()
    func mirrorPrimary() async throws
    func startPrimary() async throws -> Date
    func beginCollection(at: Date) async throws
    func pausePrimary() async throws -> Date
    func resumePrimary() async throws
    func endPrimary()
    func discardBuilder() throws
    func finishBuilder() async throws -> String?
}

// The production adapter sequence is SDK-independent and tested against the same
// operation boundary used by WatchHealthKitAdapter below it.
@MainActor final class WatchRecordingAdapter: WatchRecordingPort {
    private let operations: any WatchSessionOperations
    private var generation: UInt64 = 0
    private var cancelled = false
    private var created = false
    private var prepared = false
    private var began = false
    private var discarded = false
    private var finished = false
    private var assembled = false
    init(operations: any WatchSessionOperations) { self.operations = operations }
    private func check(_ token: UInt64) throws {
        guard token == generation, !cancelled else { throw WatchStoreError.ambiguous }
    }
    func prepare(activity: String) async throws {
        guard !created || discarded || finished else { throw WatchStoreError.ambiguous }
        try operations.resetForNewAttempt()
        generation &+= 1; let token = generation
        cancelled = false; created = false; prepared = false; began = false; discarded = false; finished = false; assembled = false
        let authorized: Bool
        do { authorized = try await operations.authorize() } catch { try check(token); throw WatchStoreError.definite }
        try check(token)
        guard authorized else { throw WatchStoreError.definite }
        let existing = try await operations.recoverPrimary()
        do { try check(token) } catch { operations.endPrimary(); throw error }
        guard existing == nil else { throw WatchStoreError.ambiguous }
        try operations.createPrimary(activity: activity); created = true
        try operations.configureCollection()
        guard operations.sourceExcludesDistance, !operations.hasDistance else { throw WatchStoreError.definite }
        operations.preparePrimary()
        try await operations.mirrorPrimary()
        try check(token); prepared = true
    }
    func recover(activity: String) async throws -> (start: Date, sourceExclusion: Bool) {
        guard !created else { throw WatchStoreError.ambiguous }
        generation &+= 1; let token = generation; cancelled = false
        guard let recovered = try await operations.recoverPrimary() else { throw WatchStoreError.ambiguous }
        try check(token); created = true
        guard recovered.activity == activity, recovered.indoor, !operations.hasDistance, operations.activities.isEmpty else { throw WatchStoreError.ambiguous }
        try operations.configureCollection()
        guard operations.sourceExcludesDistance else { throw WatchStoreError.ambiguous }
        began = true; prepared = true
        return (recovered.start, true)
    }
    func begin() async throws -> Date {
        guard prepared, !began, !cancelled else { throw WatchStoreError.ambiguous }
        began = true; let token = generation
        let date = try await operations.startPrimary()
        try check(token)
        guard operations.sourceExcludesDistance else { throw WatchStoreError.ambiguous }
        try await operations.beginCollection(at: date)
        try check(token)
        return date
    }
    func pause() async throws -> Date {
        guard began, !cancelled else { throw WatchStoreError.ambiguous }
        let token = generation; let date = try await operations.pausePrimary(); try check(token); return date
    }
    func resume() async throws {
        guard began, !cancelled else { throw WatchStoreError.ambiguous }
        let token = generation; try await operations.resumePrimary(); try check(token)
    }
    func end() {
        guard !cancelled else { operations.endPrimary(); return }; generation &+= 1; cancelled = true; operations.endPrimary()
    }
    func discard() throws {
        guard !finished, !discarded else { throw WatchStoreError.ambiguous }
        discarded = true
        // Definite denial/creation failure has no builder. Loaded recovery state is never considered attached by the lifecycle.
        if created { try operations.discardBuilder() }
    }
    func assemble(_ value: WatchAssembly) async throws {
        guard created, began, cancelled, !discarded, !finished, !assembled else { throw WatchStoreError.ambiguous }
        try await WatchBuilderAssemblyWriter(builder: operations).assemble(value)
        assembled = true
    }
    func finish() async throws -> String {
        guard assembled, !finished, !discarded else { throw WatchStoreError.ambiguous }
        finished = true
        guard let result = try await operations.finishBuilder(), UUID(uuidString: result) != nil else { throw WatchStoreError.ambiguous }
        return result
    }
}

// Both native delegate adapters apply this predicate after hopping onto their actor.
// A stale source cannot complete a waiter, deliver bytes or clear a newer session.
enum WatchCallbackIdentity {
    static func accepts(_ incoming: AnyObject, current: AnyObject?) -> Bool { current.map { $0 === incoming } ?? false }
}
