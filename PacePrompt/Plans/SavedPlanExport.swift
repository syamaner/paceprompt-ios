import Foundation

enum SavedPlanExportSchema {
    static let currentVersion = 1
    static let fileName = "PacePrompt-saved-plans.json"
    static let category = "savedPlans"
    static let includedFields = [
        "formatVersion",
        "createdAt",
        "savedPlans[].id",
        "savedPlans[].createdAt",
        "savedPlans[].modifiedAt",
        "savedPlans[].plan.schemaVersion",
        "savedPlans[].plan.suggestedName",
        "savedPlans[].plan.activity",
        "savedPlans[].plan.steps[].kind",
        "savedPlans[].plan.steps[].label",
        "savedPlans[].plan.steps[].duration.value",
        "savedPlans[].plan.steps[].duration.unit",
        "savedPlans[].plan.steps[].targetSpeed.value",
        "savedPlans[].plan.steps[].targetSpeed.unit",
        "savedPlans[].plan.steps[].targetInclination.value",
        "savedPlans[].plan.steps[].targetInclination.unit",
    ]
}

struct SavedPlanExportDocument: Codable, Equatable {
    let formatVersion: Int
    let createdAt: Date
    let savedPlans: [SavedPlanRecord]
}

struct SavedPlanExportPreview: Equatable {
    let createdAt: Date
    let fileName: String
    let records: [SavedPlanRecord]

    var category: String { SavedPlanExportSchema.category }
    var recordCount: Int { records.count }
    var includedFields: [String] { SavedPlanExportSchema.includedFields }
}

struct SavedPlanExportArtifact: Identifiable, Equatable {
    let url: URL

    var id: URL { url }
}

enum SavedPlanExportFailure: Error, Equatable {
    case noRecords
    case encoding
    case directoryPreparation
    case previousArtifactCleanup
    case protectedWrite
    case fileProtection
    case cleanup
}

protocol SavedPlanExportCoding {
    func encode(_ document: SavedPlanExportDocument) throws -> Data
}

struct SavedPlanExportJSONCodec: SavedPlanExportCoding {
    func encode(_ document: SavedPlanExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}

protocol SavedPlanExportFileSystem {
    func temporaryDirectory() throws -> URL
    func createProtectedDirectory(at url: URL) throws
    func removeItemIfPresent(at url: URL) throws
    func writeProtectedData(_ data: Data, to url: URL) throws
    func applyCompleteFileProtection(to url: URL) throws
    func hasCompleteFileProtection(at url: URL) throws -> Bool
}

struct FoundationSavedPlanExportFileSystem: SavedPlanExportFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func temporaryDirectory() throws -> URL {
        fileManager.temporaryDirectory
    }

    func createProtectedDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    func removeItemIfPresent(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            let cocoaError = error as NSError
            guard cocoaError.domain == NSCocoaErrorDomain,
                  cocoaError.code == CocoaError.fileNoSuchFile.rawValue
                    || cocoaError.code == CocoaError.fileReadNoSuchFile.rawValue else {
                throw error
            }
        }
    }

    func writeProtectedData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func applyCompleteFileProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.protectionKey] as? FileProtectionType) == .complete
    }
}

protocol SavedPlanExporting {
    func prepare(_ preview: SavedPlanExportPreview) throws -> SavedPlanExportArtifact
    func cleanup(_ artifact: SavedPlanExportArtifact) throws
}

final class SavedPlanExporter: SavedPlanExporting {
    private enum DirectoryName {
        static let application = "PacePrompt"
        static let exports = "Exports"
    }

    private let fileSystem: any SavedPlanExportFileSystem
    private let codec: any SavedPlanExportCoding

    init(
        fileSystem: any SavedPlanExportFileSystem = FoundationSavedPlanExportFileSystem(),
        codec: any SavedPlanExportCoding = SavedPlanExportJSONCodec()
    ) {
        self.fileSystem = fileSystem
        self.codec = codec
    }

    func prepare(_ preview: SavedPlanExportPreview) throws -> SavedPlanExportArtifact {
        guard !preview.records.isEmpty else { throw SavedPlanExportFailure.noRecords }

        let directory: URL
        do {
            directory = try fileSystem.temporaryDirectory()
                .appendingPathComponent(DirectoryName.application, isDirectory: true)
                .appendingPathComponent(DirectoryName.exports, isDirectory: true)
            try fileSystem.createProtectedDirectory(at: directory)
        } catch {
            throw SavedPlanExportFailure.directoryPreparation
        }

        do {
            try fileSystem.applyCompleteFileProtection(to: directory)
            guard try fileSystem.hasCompleteFileProtection(at: directory) else {
                throw SavedPlanExportFailure.fileProtection
            }
        } catch {
            throw SavedPlanExportFailure.fileProtection
        }

        let url = directory.appendingPathComponent(preview.fileName, isDirectory: false)
        do {
            try fileSystem.removeItemIfPresent(at: url)
        } catch {
            throw SavedPlanExportFailure.previousArtifactCleanup
        }

        let data: Data
        do {
            data = try codec.encode(
                SavedPlanExportDocument(
                    formatVersion: SavedPlanExportSchema.currentVersion,
                    createdAt: preview.createdAt,
                    savedPlans: preview.records
                )
            )
        } catch {
            throw SavedPlanExportFailure.encoding
        }

        do {
            try fileSystem.writeProtectedData(data, to: url)
        } catch {
            throw SavedPlanExportFailure.protectedWrite
        }

        do {
            try fileSystem.applyCompleteFileProtection(to: url)
            guard try fileSystem.hasCompleteFileProtection(at: url) else {
                throw SavedPlanExportFailure.fileProtection
            }
        } catch {
            try? fileSystem.removeItemIfPresent(at: url)
            throw SavedPlanExportFailure.fileProtection
        }

        return SavedPlanExportArtifact(url: url)
    }

    func cleanup(_ artifact: SavedPlanExportArtifact) throws {
        do {
            try fileSystem.removeItemIfPresent(at: artifact.url)
        } catch {
            throw SavedPlanExportFailure.cleanup
        }
    }
}
