import Foundation
import MorningCore

/// A separately supplied vocabulary of visible headers, never an expected event sequence.
/// Neither field is an OS bundle identifier or evidence that the app was opened.
public struct ObservationContextCatalogEntry: Codable, Sendable, Equatable {
    public let label: String
    public let headerText: String
    public init(label: String, headerText: String? = nil) {
        self.label = label
        self.headerText = headerText ?? label
    }
}

public enum ObservationContextClassificationError: LocalizedError, Sendable, Equatable {
    case invalidFrames, invalidCatalog, alreadyClassifying
    public var errorDescription: String? {
        switch self {
        case .invalidFrames: "The observation frames have invalid or duplicate identifiers or timestamps."
        case .invalidCatalog: "The visible-context catalog is invalid, ambiguous or too large."
        case .alreadyClassifying: "A visible-context analysis is already running."
        }
    }
}

public enum ObservationContextInferenceStatus: String, Codable, Sendable {
    case noEligibleFrames, unavailable, completed, partialFailure, failed
}

public struct ObservationContextDiagnostic: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case unknownSampleID, duplicateSampleID, invalidResponse, invalidEvidence
        case unsupportedIdentity, generationFailed
    }
    public let kind: Kind
    public let sampleID: UUID?
    public init(kind: Kind, sampleID: UUID? = nil) { self.kind = kind; self.sampleID = sampleID }
}

/// Inference completion is not a claim that all frames were identified or correctly classified.
/// Unavailable/failed calls have explicit status; there is no deterministic fallback labeler.
public struct ObservationContextClassification: Codable, Sendable, Equatable {
    public let decisions: [ObservationFrameIdentityDecision]
    public let status: ObservationContextInferenceStatus
    public let attemptedBatchCount: Int
    public let respondedBatchCount: Int
    public let failedBatchCount: Int
    public let diagnostics: [ObservationContextDiagnostic]
    public let modelAvailability: String
    public let modelIdentifier: String

    init(decisions: [ObservationFrameIdentityDecision], status: ObservationContextInferenceStatus,
         attemptedBatchCount: Int, respondedBatchCount: Int, failedBatchCount: Int,
         diagnostics: [ObservationContextDiagnostic], modelAvailability: String) {
        self.decisions = decisions; self.status = status
        self.attemptedBatchCount = attemptedBatchCount; self.respondedBatchCount = respondedBatchCount
        self.failedBatchCount = failedBatchCount; self.diagnostics = diagnostics
        self.modelAvailability = modelAvailability
        self.modelIdentifier = "Apple Foundation Models / SystemLanguageModel.default"
    }
}

public enum ObservationContextLimits {
    public static let maximumFrames = 24
    public static let maximumFrameCharacters = 900
    public static let maximumTotalTextCharacters = 9_000
    public static let maximumBatchFrames = 4
    public static let maximumPromptCharacters = 2_000
    public static let maximumCatalogEntries = 8
    public static let maximumCatalogCharacters = 480
    public static let maximumResponseCharacters = 12_000
}

struct ObservationContextBatch: Sendable {
    let frames: [ObservationFrameEvidence]
    let prompt: String
}

struct ObservationContextPreparedInput: Sendable {
    let frames: [ObservationFrameEvidence]
    let catalog: [ObservationContextCatalogEntry]
    let batches: [ObservationContextBatch]
    let initialDecisions: [ObservationFrameIdentityDecision]
}

struct ObservationContextValidatedBatch: Sendable {
    let decisions: [ObservationFrameIdentityDecision]
    let diagnostics: [ObservationContextDiagnostic]
    let responseWasValid: Bool
}

/// Pure validation: exact citations constrain a model proposal; they do not prove that an
/// OCR line is a true app header. The identity namespace deliberately says visual-context.
enum ObservationContextValidation {
    static func prepare(frames: [ObservationFrameEvidence], catalog: [ObservationContextCatalogEntry]) throws -> ObservationContextPreparedInput {
        var ids = Set<UUID>()
        var previous = 0.0
        for frame in frames {
            guard ids.insert(frame.id).inserted,
                  frame.requestedTimeSeconds.isFinite, frame.requestedTimeSeconds >= 0,
                  frame.actualTimeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  frame.timeSeconds.isFinite, frame.timeSeconds >= previous else {
                throw ObservationContextClassificationError.invalidFrames
            }
            previous = frame.timeSeconds
        }
        let catalog = try validatedCatalog(catalog)
        var reasons: [UUID: String] = [:]
        var totalText = 0
        var batches: [ObservationContextBatch] = []
        var current: [ObservationFrameEvidence] = []
        var currentOrders: [Int] = []
        func flush() throws {
            guard !current.isEmpty else { return }
            batches.append(.init(frames: current, prompt: try prompt(frames: current, orders: currentOrders, catalog: catalog)))
            current = []; currentOrders = []
        }
        for (index, frame) in frames.enumerated() {
            let text = frame.text
            let reason: String?
            if frame.outcome != .observed { reason = "The source frame was blank or could not be extracted." }
            else if frame.textWasTruncated { reason = "The source text was truncated; context remains unknown." }
            else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reason = "No visible text was extracted." }
            else if index >= ObservationContextLimits.maximumFrames { reason = "Excluded by the model frame limit." }
            else if text.count > ObservationContextLimits.maximumFrameCharacters { reason = "Excluded by the per-frame text limit." }
            else if totalText + text.count > ObservationContextLimits.maximumTotalTextCharacters { reason = "Excluded by the total text limit." }
            else { reason = nil }
            if let reason { reasons[frame.id] = reason; continue }
            let singlePrompt = try prompt(frames: [frame], orders: [index], catalog: catalog)
            guard singlePrompt.count <= ObservationContextLimits.maximumPromptCharacters else {
                reasons[frame.id] = "Excluded by the encoded model-context limit."
                continue
            }
            let candidate = try prompt(frames: current + [frame], orders: currentOrders + [index], catalog: catalog)
            if current.count >= ObservationContextLimits.maximumBatchFrames || candidate.count > ObservationContextLimits.maximumPromptCharacters {
                try flush()
            }
            current.append(frame); currentOrders.append(index); totalText += text.count
            reasons[frame.id] = "The local model has not classified this frame."
        }
        try flush()
        return .init(frames: frames, catalog: catalog, batches: batches,
                     initialDecisions: frames.map { unknown($0, reason: reasons[$0.id] ?? "Context remains unknown.") })
    }

    static func validate(json: String, batch: ObservationContextBatch,
                         catalog: [ObservationContextCatalogEntry]) -> ObservationContextValidatedBatch {
        guard json.count <= ObservationContextLimits.maximumResponseCharacters,
              let response = try? JSONDecoder().decode(ContextModelResponse.self, from: Data(json.utf8)),
              response.frames.count <= ObservationContextLimits.maximumBatchFrames * 2 else {
            return .init(decisions: batch.frames.map { unknown($0, reason: "The model response could not be validated.") },
                         diagnostics: [.init(kind: .invalidResponse)], responseWasValid: false)
        }
        let knownIDs = Set(batch.frames.map(\.id))
        var proposals: [UUID: [ContextModelProposal]] = [:]
        var diagnostics: [ObservationContextDiagnostic] = []
        for proposal in response.frames {
            guard let id = UUID(uuidString: proposal.sampleID), knownIDs.contains(id) else {
                diagnostics.append(.init(kind: .unknownSampleID, sampleID: UUID(uuidString: proposal.sampleID)))
                continue
            }
            proposals[id, default: []].append(proposal)
        }
        let decisions = batch.frames.map { frame -> ObservationFrameIdentityDecision in
            guard let candidates = proposals[frame.id] else {
                return unknown(frame, reason: "The local model omitted this frame.")
            }
            guard candidates.count == 1, let proposal = candidates.first else {
                diagnostics.append(.init(kind: .duplicateSampleID, sampleID: frame.id))
                return unknown(frame, reason: "Conflicting or duplicate proposals were rejected.")
            }
            if proposal.outcome == "unknown", proposal.contextLabel.isEmpty, proposal.evidenceQuote.isEmpty {
                return unknown(frame, reason: "The local model abstained.")
            }
            let quote = proposal.evidenceQuote
            guard !quote.isEmpty, quote.count <= 240, frame.text.contains(quote),
                  frame.outcome == .observed, !frame.textWasTruncated else {
                diagnostics.append(.init(kind: .invalidEvidence, sampleID: frame.id))
                return unknown(frame, reason: "The proposed quote was not grounded in this frame.")
            }
            if proposal.outcome == "ambiguous", proposal.contextLabel.isEmpty {
                return .init(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                             evidence: .ambiguous(reference: frame.evidenceReference), evidenceQuote: quote,
                             reason: "The local model reported ambiguous visible context.")
            }
            guard proposal.outcome == "identified", let identity = identity(for: proposal, frame: frame, catalog: catalog) else {
                diagnostics.append(.init(kind: .unsupportedIdentity, sampleID: frame.id))
                return unknown(frame, reason: "The proposed visual identity was unsupported.")
            }
            return .init(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
                         evidence: .identified(app: identity, reference: frame.evidenceReference),
                         evidenceQuote: quote, reason: "Model-proposed visual header; not an OS-verified app identity.")
        }
        return .init(decisions: decisions, diagnostics: diagnostics, responseWasValid: true)
    }

    static func unknown(_ frame: ObservationFrameEvidence, reason: String) -> ObservationFrameIdentityDecision {
        .init(sampleID: frame.id, timeSeconds: frame.timeSeconds, timeBasis: frame.timeBasis,
              evidence: .unknown, evidenceQuote: nil, reason: reason)
    }

    private static func identity(for proposal: ContextModelProposal, frame: ObservationFrameEvidence,
                                 catalog: [ObservationContextCatalogEntry]) -> ObservationAppIdentity? {
        let headers = headerLines(frame.text)
        let label: String
        if catalog.isEmpty {
            guard isSafeLabel(proposal.contextLabel), proposal.contextLabel == proposal.evidenceQuote,
                  headers.contains(proposal.evidenceQuote) else { return nil }
            label = proposal.contextLabel
        } else {
            let visibleCatalog = catalog.filter { headers.contains($0.headerText) }
            guard visibleCatalog.count == 1, let entry = visibleCatalog.first,
                  proposal.contextLabel == entry.label, proposal.evidenceQuote == entry.headerText else { return nil }
            label = entry.label
        }
        // Generic casing/diacritics may vary between OCR frames. Canonicalize the
        // display name with the key so one trace cannot contain conflicting names.
        let canonical = normalized(label)
        return .init(key: "visual-context:\(canonical)", displayName: catalog.isEmpty ? canonical : label)
    }

    /// A lexical first-lines guard, not a claim about the pixels' layout or a verified app.
    private static func headerLines(_ text: String) -> [String] {
        var lines: [String] = []
        var characterCount = 0
        for line in text.components(separatedBy: .newlines) {
            characterCount += line.count + 1
            guard characterCount <= 320 else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lines.append(trimmed) }
            if lines.count == 6 { break }
        }
        return lines
    }

    private static func validatedCatalog(_ entries: [ObservationContextCatalogEntry]) throws -> [ObservationContextCatalogEntry] {
        guard entries.count <= ObservationContextLimits.maximumCatalogEntries,
              entries.reduce(0, { $0 + $1.label.count + $1.headerText.count }) <= ObservationContextLimits.maximumCatalogCharacters else {
            throw ObservationContextClassificationError.invalidCatalog
        }
        var labels = Set<String>(); var headers = Set<String>()
        for entry in entries {
            guard isSafeLabel(entry.label), isSafeLabel(entry.headerText),
                  labels.insert(normalized(entry.label)).inserted,
                  headers.insert(normalized(entry.headerText)).inserted else {
                throw ObservationContextClassificationError.invalidCatalog
            }
        }
        return entries
    }

    private static func isSafeLabel(_ label: String) -> Bool {
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: " -_&'’"))
        return (2...80).contains(label.count) && label == label.trimmingCharacters(in: .whitespacesAndNewlines) &&
            label.unicodeScalars.contains(where: CharacterSet.letters.contains) &&
            label.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private struct InputFrame: Encodable {
        let sampleID: String
        let order: Int
        let timeSeconds: Double
        let timeBasis: String
        let text: String
    }
    private struct Input: Encodable {
        let catalog: [ObservationContextCatalogEntry]
        let frames: [InputFrame]
    }
    private static func prompt(frames: [ObservationFrameEvidence], orders: [Int],
                               catalog: [ObservationContextCatalogEntry]) throws -> String {
        let input = Input(catalog: catalog, frames: zip(frames, orders).map { frame, order in
            .init(sampleID: frame.id.uuidString, order: order, timeSeconds: frame.timeSeconds,
                  timeBasis: frame.timeBasis.rawValue, text: frame.text)
        })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(input), as: UTF8.self)
    }
}

private struct ContextModelResponse: Decodable {
    let frames: [ContextModelProposal]
    init(from decoder: any Decoder) throws {
        try requireOnlyKeys(["frames"], from: decoder)
        let values = try decoder.container(keyedBy: Keys.self)
        frames = try values.decode([ContextModelProposal].self, forKey: .frames)
    }
    private enum Keys: String, CodingKey { case frames }
}

private struct ContextModelProposal: Decodable {
    let sampleID: String
    let outcome: String
    let contextLabel: String
    let evidenceQuote: String
    init(from decoder: any Decoder) throws {
        try requireOnlyKeys(["sampleID", "outcome", "contextLabel", "evidenceQuote"], from: decoder)
        let values = try decoder.container(keyedBy: Keys.self)
        sampleID = try values.decode(String.self, forKey: .sampleID)
        outcome = try values.decode(String.self, forKey: .outcome)
        contextLabel = try values.decode(String.self, forKey: .contextLabel)
        evidenceQuote = try values.decode(String.self, forKey: .evidenceQuote)
    }
    private enum Keys: String, CodingKey { case sampleID, outcome, contextLabel, evidenceQuote }
}

private struct ContextResponseKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireOnlyKeys(_ expected: Set<String>, from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: ContextResponseKey.self)
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                               debugDescription: "Unexpected visible-context response fields."))
    }
}
