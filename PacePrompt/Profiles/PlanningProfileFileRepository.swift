import Foundation
import UIKit

// All filesystem/URL types remain in this infrastructure seam.
protocol PlanningProfileFileSystem {
    func exists(_ url: URL) throws -> Bool
    func rejectSymlinks(_ url: URL) throws
    func prepareDirectory(_ url: URL) throws
    func verify(_ url: URL) throws
    func read(_ url: URL) throws -> Data
    func stage(_ data: Data, at url: URL) throws
    func replace(_ canonical: URL, with staging: URL) throws
    func remove(_ url: URL) throws
}

struct FoundationPlanningProfileFileSystem: PlanningProfileFileSystem {
    private let files = FileManager.default
    func exists(_ url: URL) throws -> Bool {
        do { _ = try files.attributesOfItem(atPath: url.path); return true }
        catch {
            let value = error as NSError
            let missing = value.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code)
                || value.domain == NSPOSIXErrorDomain && value.code == 2
            if missing { return false }
            throw error
        }
    }
    func rejectSymlinks(_ url: URL) throws {
        // The repository canonicalises the trusted parent once and checks every owned path explicitly.
        if try exists(url) {
            let attributes = try files.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw PlanningProfileFailure.readFailure }
        }
    }

    func prepareDirectory(_ url: URL) throws {
        try rejectSymlinks(url)
        try files.createDirectory(at: url, withIntermediateDirectories: true,
                                  attributes: [.protectionKey: FileProtectionType.complete])
        try protect(url)
        try verify(url)
    }
    private func protect(_ url: URL) throws {
        try files.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }
    func verify(_ url: URL) throws {
        try rejectSymlinks(url)
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.protectionKey] as? FileProtectionType == .complete,
              try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw PlanningProfileFailure.readFailure
        }
    }
    func read(_ url: URL) throws -> Data {
        try verify(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: PlanningProfileCodec.maximumBytes + 1) ?? Data()
        guard data.count <= PlanningProfileCodec.maximumBytes else { throw PlanningProfileFailure.corrupt }
        return data
    }
    func stage(_ data: Data, at url: URL) throws {
        try rejectSymlinks(url)
        // Create and verify an empty protected/excluded sibling before any private bytes are written.
        try Data().write(to: url, options: [.completeFileProtection])
        try protect(url)
        try verify(url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try verify(url)
    }
    func replace(_ canonical: URL, with staging: URL) throws {
        try rejectSymlinks(canonical)
        try verify(staging)
        if try exists(canonical) {
            _ = try files.replaceItemAt(canonical, withItemAt: staging)
        } else {
            try files.moveItem(at: staging, to: canonical)
        }
    }
    func remove(_ url: URL) throws {
        try rejectSymlinks(url)
        if try exists(url) { try files.removeItem(at: url) }
    }
}

@MainActor
final class FilePlanningProfileRepository: PlanningProfileRepository {
    private let directory: URL
    private let files: any PlanningProfileFileSystem
    private let protectedDataAvailable: @MainActor () -> Bool
    private let codec = PlanningProfileCodec()
    private var canonical: URL { directory.appendingPathComponent("profiles-v1.json") }
    private var staging: URL { directory.appendingPathComponent("profiles-v1.staging") }
    init(directory: URL? = nil, files: any PlanningProfileFileSystem = FoundationPlanningProfileFileSystem(),
         protectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }) {
        let requested = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlanningProfiles", isDirectory: true)
        self.directory = requested.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(requested.lastPathComponent, isDirectory: true)
        self.files = files
        self.protectedDataAvailable = protectedDataAvailable
    }
    func load() throws -> PlanningProfileStore? {
        guard protectedDataAvailable() else { throw PlanningProfileFailure.protectedDataUnavailable }
        do {
            try files.rejectSymlinks(directory)
            try files.rejectSymlinks(canonical)
            try files.rejectSymlinks(staging)
            if try files.exists(directory) { try files.verify(directory) }
            let hasStaging = try files.exists(staging)
            if hasStaging { try files.verify(staging) }
            guard try files.exists(canonical) else {
                if hasStaging { throw PlanningProfileFailure.interruptedWrite }
                return nil
            }
            return try codec.decode(files.read(canonical))
        } catch let failure as PlanningProfileFailure { throw failure }
        catch { throw PlanningProfileFailure.readFailure }
    }
    func commit(_ replacement: PlanningProfileStore, expectedRevision: Int?) throws {
        let old = try load()
        try PlanningProfileTransactions.validate(replacement, replacing: old, expectedRevision: expectedRevision)
        let bytes = try codec.encode(replacement)
        var replacementAttempted = false
        do {
            try files.prepareDirectory(directory)
            try files.remove(staging) // Never promote an orphan; validated canonical remains authoritative.
            try files.stage(bytes, at: staging)
            guard protectedDataAvailable() else { throw PlanningProfileFailure.protectedDataUnavailable }
            // Same actor, synchronous transaction: check CAS immediately before replacement.
            let diskRevision = try files.exists(canonical) ? codec.decode(files.read(canonical)).storeRevision : nil
            guard diskRevision == expectedRevision else { throw PlanningProfileFailure.conflict }
            replacementAttempted = true
            try files.replace(canonical, with: staging)
            try files.verify(directory)
            try files.verify(canonical)
            guard try codec.decode(files.read(canonical)) == replacement else { throw PlanningProfileFailure.partialWrite }
            try files.remove(staging)
        } catch {
            if replacementAttempted { throw PlanningProfileFailure.partialWrite }
            // Discard only this failed staging write; never erase canonical or recover by empty replacement.
            try? files.remove(staging)
            if let failure = error as? PlanningProfileFailure { throw failure }
            throw PlanningProfileFailure.writeFailure
        }
    }
}
