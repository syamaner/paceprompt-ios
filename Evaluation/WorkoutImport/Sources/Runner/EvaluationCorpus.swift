import Foundation

enum EvaluationCorpusError: Error, Equatable, LocalizedError {
    case missingResource(String)
    case invalidManifest(String)
    case invalidCases(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(name): return "The accepted evaluation resource \(name) is missing."
        case let .invalidManifest(reason): return "The accepted corpus manifest is invalid: \(reason)"
        case let .invalidCases(reason): return "The accepted corpus cases are invalid: \(reason)"
        case let .decodingFailed(name): return "The accepted evaluation resource \(name) could not be decoded."
        }
    }
}

struct EvaluationCorpus: Equatable {
    let manifest: WorkoutImportManifest
    let cases: [WorkoutImportCase]

    private init(manifest: WorkoutImportManifest, cases: [WorkoutImportCase]) {
        self.manifest = manifest
        self.cases = cases
    }

    static func acceptedV1(bundle: Bundle) throws -> EvaluationCorpus {
        let manifestURL = try resourceURL(
            name: "manifest",
            extension: "json",
            subdirectory: "Corpus/v1",
            bundle: bundle
        )
        let casesURL = try resourceURL(
            name: "cases",
            extension: "json",
            subdirectory: "Corpus/v1",
            bundle: bundle
        )
        let decoder = JSONDecoder()
        let manifest: WorkoutImportManifest
        let cases: [WorkoutImportCase]
        do {
            manifest = try decoder.decode(WorkoutImportManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw EvaluationCorpusError.decodingFailed("Corpus/v1/manifest.json")
        }
        do {
            cases = try decoder.decode([WorkoutImportCase].self, from: Data(contentsOf: casesURL))
        } catch {
            throw EvaluationCorpusError.decodingFailed("Corpus/v1/cases.json")
        }
        try validate(manifest: manifest, cases: cases)
        return EvaluationCorpus(manifest: manifest, cases: cases)
    }

    private static func resourceURL(
        name: String,
        extension extensionName: String,
        subdirectory: String,
        bundle: Bundle
    ) throws -> URL {
        if let url = bundle.url(forResource: name, withExtension: extensionName, subdirectory: subdirectory) {
            return url
        }
        if let corpus = bundle.url(forResource: "Corpus", withExtension: nil),
           FileManager.default.fileExists(atPath: corpus.path) {
            return corpus.appendingPathComponent("v1/\(name).\(extensionName)")
        }
        throw EvaluationCorpusError.missingResource("\(subdirectory)/\(name).\(extensionName)")
    }

    private static func validate(
        manifest: WorkoutImportManifest,
        cases: [WorkoutImportCase]
    ) throws {
        guard manifest.manifestVersion == 1,
              manifest.corpusVersion == WorkoutImportEvaluationContract.corpusVersion,
              manifest.caseContractVersion == WorkoutImportEvaluationContract.caseContractVersion,
              manifest.proposalContractVersion == WorkoutImportEvaluationContract.proposalContractVersion,
              manifest.resultContractVersion == WorkoutImportEvaluationContract.resultContractVersion,
              manifest.scorerVersion == WorkoutImportEvaluationContract.scorerVersion,
              manifest.promptTemplateVersion == WorkoutImportEvaluationContract.promptTemplateVersion,
              manifest.hashContract == "workout-import-corpus-hash/v1",
              manifest.corpusHash == WorkoutImportEvaluationContract.acceptedCorpusHash else {
            throw EvaluationCorpusError.invalidManifest("a version or the accepted v1 hash differs")
        }
        guard !cases.isEmpty else {
            throw EvaluationCorpusError.invalidCases("no cases were found")
        }
        guard Set(manifest.supportedLocales).count == manifest.supportedLocales.count,
              !manifest.supportedLocales.isEmpty else {
            throw EvaluationCorpusError.invalidManifest("supported locales are empty or duplicated")
        }
        guard Set(cases.map(\.id)).count == cases.count else {
            throw EvaluationCorpusError.invalidCases("case IDs are duplicated")
        }
        for item in cases {
            guard item.caseContractVersion == WorkoutImportEvaluationContract.caseContractVersion,
                  manifest.supportedLocales.contains(item.locale),
                  !item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EvaluationCorpusError.invalidCases("\(item.id) does not satisfy the accepted case boundary")
            }
            try validate(item.capabilities.speed, path: "\(item.id).capabilities.speed")
            try validate(item.capabilities.inclination, path: "\(item.id).capabilities.inclination")
        }
        let index = cases
            .sorted { $0.id < $1.id }
            .map { WorkoutImportManifest.CaseIndex(id: $0.id, category: $0.category) }
        guard index == manifest.caseIndex else {
            throw EvaluationCorpusError.invalidManifest("the stable case index differs from cases.json")
        }
    }

    private static func validate(_ capability: WorkoutImportCapability, path: String) throws {
        let values = [capability.minimum, capability.maximum, capability.increment]
        switch capability.state {
        case .supported:
            guard values.allSatisfy({ $0 != nil }) else {
                throw EvaluationCorpusError.invalidCases("\(path) is missing a supported range value")
            }
        case .unknown, .unsupported:
            guard values.allSatisfy({ $0 == nil }) else {
                throw EvaluationCorpusError.invalidCases("\(path) carries values for a non-supported state")
            }
        }
    }
}
