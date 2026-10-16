import CryptoKit
import Darwin
import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Explicitly authorized OCR-only replay. Never reads a movie, Keychain, inbox or oracle.
@Suite("Opt-in OpenAI comparison of the frozen synthetic OCR only", .serialized)
struct SyntheticOpenAIComparisonTests {
    private static let allowedReportSHA256 = "fcad0666217a3638c6e786d88a9554a98285448e2539f9c0ad08a4cb7c536e20"
    private static let allowedMovieSHA256 = "82d0dd41e50654186b7848b6463aebdd1e1013977a6da2bab4593f98d3a67815"

    @Test @MainActor func egressRequiresTheExactPreparedTextAndSchema() throws {
        let prompt = "Invented OCR task: review a fictional agenda."
        let instructions = "Test-only instructions."
        let schema: ComposioJSONValue = .object(["type": .string("object")])
        let allowed = [prompt: schema]
        let body: [String: ComposioJSONValue] = [
            "model": .string(MoreLanguageModel.openAIModel), "instructions": .string(instructions),
            "input": .string(prompt), "store": .bool(false),
            "reasoning": .object(["effort": .string("minimal")]), "max_output_tokens": .number(4_400),
            "text": .object(["format": .object(["type": .string("json_schema"), "name": .string("more_response"),
                                                "strict": .bool(true), "schema": schema])])]
        func request(_ body: [String: ComposioJSONValue]) throws -> URLRequest {
            var request = URLRequest(url: MoreLanguageModel.endpoint)
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(ComposioJSONValue.object(body))
            return request
        }
        #expect(Self.permits(try request(body), instructions: instructions, allowed: allowed))
        for (field, value) in ["input": ComposioJSONValue.string("Unapproved text"),
                               "instructions": .string("Changed instructions"), "store": .bool(true),
                               "extra": .string("Unexpected data"), "text": .object([:])] {
            var changed = body; changed[field] = value
            #expect(!Self.permits(try request(changed), instructions: instructions, allowed: allowed))
        }
        var changedEndpoint = try request(body)
        changedEndpoint.url = URL(string: "https://example.invalid/v1/responses")
        #expect(!Self.permits(changedEndpoint, instructions: instructions, allowed: allowed))
        var changedMethod = try request(body); changedMethod.httpMethod = "GET"
        #expect(!Self.permits(changedMethod, instructions: instructions, allowed: allowed))
    }

    @Test(.enabled("Requires explicit synthetic-text consent, a protected key file and private input/output paths.") {
        let env = ProcessInfo.processInfo.environment
        return env["MO_RUN_OPENAI_SYNTHETIC_COMPARISON"] == "1" && env["MO_OPENAI_SYNTHETIC_TEXT_CONSENT"] == "1"
    })
    @MainActor func frozenOCRThroughTheOrdinaryRemoteProposalAndNativeValidation() async throws {
        let env = ProcessInfo.processInfo.environment
        let work = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("work").resolvingSymlinksInPath()
        let input = try Self.privateURL(env["MO_OPENAI_SYNTHETIC_INPUT"], below: work)
        let output = try Self.privateURL(env["MO_OPENAI_SYNTHETIC_OUTPUT"], below: work)
        guard output != input, !FileManager.default.fileExists(atPath: output.path) else { throw ComparisonFailure.invalidPath }
        var report = ComparisonReport(model: MoreLanguageModel.openAIModel, interfaceLanguage: AppLanguage.code)
        let storage = EphemeralCredentialStorage()
        var client: MoreLanguageModel?
        defer { try? client?.forget(); storage.clear() }
        do {
            let data = try Data(contentsOf: input)
            guard data.count <= 1_024 * 1_024, Self.digest(data) == Self.allowedReportSHA256 else { throw ComparisonFailure.unapprovedInput }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let source = try decoder.decode(FrozenInput.self, from: data), acquisition = source.acquisition
            guard source.schemaVersion == 2, source.mode == nil,
                  source.fingerprint.sha256 == Self.allowedMovieSHA256, source.fingerprint.byteCount == 5_164_714,
                  acquisition.fileSHA256 == source.fingerprint.sha256, acquisition.origin == .synthetic,
                  acquisition.sourceKind == .video, acquisition.correctedText == nil, acquisition.frameReviews.isEmpty,
                  acquisition.videoEvidence == source.videoEvidence, acquisition.classification == source.classification else {
                throw ComparisonFailure.unapprovedInput
            }
            report.inputReportSHA256 = Self.digest(data)
            report.fingerprint = source.fingerprint
            report.acquisition = acquisition; report.videoEvidence = source.videoEvidence
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [acquisition])
            let anchored = try ModelCitationPreparation.prepare(evidence)
            let instructions = AppleIntelligenceService.groundedProposalInstructions(french: AppLanguage.isFrench)
            var allowed: [String: ComposioJSONValue] = [:]
            for batch in anchored.batchesByFirstUnitID.values {
                allowed[batch.prompt] = OpenAIRoutineSchema.make(citationIDs: batch.anchors.map(\.id))
            }
            guard !allowed.isEmpty, allowed.count <= 24 else { throw ComparisonFailure.unapprovedInput }
            report.instructionSHA256 = Self.digest(Data(instructions.utf8))
            report.preparedRequestCount = allowed.count
            let model = MoreLanguageModel(storage: storage, transport: { request in
                guard report.requestsAttempted < allowed.count,
                      Self.permits(request, instructions: instructions, allowed: allowed) else { throw ComparisonFailure.egressRefused }
                report.requestsAttempted += 1
                let result = try await MoreLanguageModel.send(request)
                report.requestsReturned += 1
                report.httpStatuses.append(result.1.statusCode)
                return result
            })
            client = model
            try model.configureOpenAI(apiKey: Self.readProtectedKey(env["MO_OPENAI_SYNTHETIC_KEY_FILE"]), enabled: true)
            let service = AppleIntelligenceService(model: model)
            let proposal = try await service.propose(evidence: evidence, preserving: nil)
            guard proposal.isCurrent(archive: try ObservationArchive(entries: [acquisition]), baseRoutine: nil),
                  proposal.routine.isSynthetic, !proposal.routine.isApproved,
                  proposal.routine.steps.allSatisfy({ $0.target == nil && $0.automation == nil && !$0.isRequired }),
                  service.proposalDiagnostics == nil else { throw ComparisonFailure.invalidProposal }
            report.proposal = proposal; report.status = "completed"
        } catch {
            report.errorCategory = Self.category(error)
        }
        report.elapsedSeconds = Date().timeIntervalSince(report.createdAt)
        try Self.write(report, to: output)
        print("SYNTHETIC_OPENAI_COMPARISON status=\(report.status) requests=\(report.requestsAttempted) returned=\(report.requestsReturned)")
        guard report.status == "completed" else { throw ComparisonFailure.failed }
    }

    @MainActor private static func permits(_ request: URLRequest, instructions: String,
                                          allowed: [String: ComposioJSONValue]) -> Bool {
        guard request.url == MoreLanguageModel.endpoint, request.httpMethod == "POST", let data = request.httpBody,
              let body = try? JSONDecoder().decode(ComposioJSONValue.self, from: data).objectValue,
              Set(body.keys) == ["model", "instructions", "input", "store", "reasoning", "max_output_tokens", "text"],
              body["model"]?.stringValue == MoreLanguageModel.openAIModel, body["instructions"]?.stringValue == instructions,
              body["store"] == .bool(false), let prompt = body["input"]?.stringValue, let schema = allowed[prompt],
              body["reasoning"] == .object(["effort": .string("minimal")]),
              body["max_output_tokens"] == .number(4_400),
              body["text"] == .object(["format": .object(["type": .string("json_schema"), "name": .string("more_response"),
                                                          "strict": .bool(true), "schema": schema])]) else { return false }
        return true
    }

    private static func privateURL(_ path: String?, below work: URL) throws -> URL {
        guard let path, path.hasPrefix("/") else { throw ComparisonFailure.invalidPath }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        guard parent.path.hasPrefix(work.path + "/"), url.pathExtension == "json" else { throw ComparisonFailure.invalidPath }
        return parent.appendingPathComponent(url.lastPathComponent)
    }
    private static func readProtectedKey(_ path: String?) throws -> String {
        guard let path, path.hasPrefix("/") else { throw ComparisonFailure.credentialUnavailable }
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ComparisonFailure.credentialUnavailable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size <= 1_024,
              let bytes = try file.read(upToCount: 1_025), bytes.count <= 1_024,
              let key = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ComparisonFailure.credentialUnavailable
        }
        return key
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func category(_ error: any Error) -> String {
        if let failure = error as? ComparisonFailure { return failure.rawValue }
        if let model = error as? MoreLanguageModelError {
            switch model { case .unauthorized: return "unauthorized"; case .rateLimited: return "rateLimited"; default: return "modelRequestOrResponseRejected" }
        }
        if case RoutineEvidenceProposalError.insufficientEvidence = error { return "insufficientEvidence" }
        if error is RoutineEvidenceProposalError { return "nativeEvidencePolicyRejected" }
        if error is CancellationError { return "cancelled" }
        return "comparisonUnavailable"
    }
    private static func write(_ report: ComparisonReport, to output: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(report)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let descriptor = Darwin.open(output.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw ComparisonFailure.reportNotSaved }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? file.close() }
        try file.write(contentsOf: bytes); try file.synchronize()
    }
}

@MainActor private final class EphemeralCredentialStorage: MoreModelCredentialStorage {
    private var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
    func clear() { data = nil }
}
private struct FrozenInput: Decodable {
    let schemaVersion: Int, mode: String?
    let fingerprint: ObservationFileFingerprint, acquisition: ObservationAcquisition
    let videoEvidence: ObservationVideoEvidence, classification: ObservationContextClassification?
}
private struct ComparisonReport: Encodable {
    let mode = "explicit-openai-synthetic-ocr-replay", schemaVersion = 1, createdAt = Date()
    let scope = "Explicitly consented frozen synthetic OCR text only. No new extraction/classification, movie/audio upload, oracle, personal data, approval or external action. Exact input hash and each outgoing prompt/schema are allowlisted. Key is ephemeral and never recorded. Not a full movie-pipeline or MORE acceptance report."
    let model: String, interfaceLanguage: String
    var status = "failed", elapsedSeconds = 0.0, requestsAttempted = 0, requestsReturned = 0
    var preparedRequestCount = 0, httpStatuses: [Int] = []
    var inputReportSHA256: String?, instructionSHA256: String?, errorCategory: String?
    var fingerprint: ObservationFileFingerprint?, acquisition: ObservationAcquisition?, videoEvidence: ObservationVideoEvidence?
    var proposal: EvidenceRoutineProposal?
}
private enum ComparisonFailure: String, Error { case invalidPath, unapprovedInput, egressRefused, credentialUnavailable, invalidProposal, reportNotSaved, failed }
