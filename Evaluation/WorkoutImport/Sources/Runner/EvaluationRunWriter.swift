import Foundation

enum EvaluationRunWriterError: Error, Equatable, LocalizedError {
    case outsideIgnoredRunsBoundary
    case invalidRunID

    var errorDescription: String? {
        switch self {
        case .outsideIgnoredRunsBoundary:
            return "Raw normalized results may be written only under Evaluation/WorkoutImport/.runs/."
        case .invalidRunID:
            return "The run ID cannot be represented as a safe evidence filename."
        }
    }
}

enum EvaluationRunWriter {
    static func write(_ run: NormalizedEvaluationRun, to runsDirectory: URL) throws -> URL {
        let directory = runsDirectory.standardizedFileURL
        guard Array(directory.pathComponents.suffix(3)) == ["Evaluation", "WorkoutImport", ".runs"] else {
            throw EvaluationRunWriterError.outsideIgnoredRunsBoundary
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !run.provenance.runID.isEmpty,
              run.provenance.runID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw EvaluationRunWriterError.invalidRunID
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("\(run.provenance.runID).json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(run)
        data.append(0x0A)
        try data.write(to: output, options: .atomic)
        return output
    }
}
