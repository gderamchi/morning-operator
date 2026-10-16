import Foundation
import Testing
@testable import MorningApple

@Suite("Explicit model route and private OpenAI transport")
@MainActor
struct MoreLanguageModelTests {
    private let testKey = "sk-unit-test-synthetic-credential"

    @Test("Default is local and an unavailable local model never contacts OpenAI")
    func localDefault() async throws {
        var requests = 0
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
            requests += 1
            throw MoreLanguageModelError.requestFailed
        })
        #expect(!model.usesOpenAI)
        #expect(!model.isAvailable)
        await #expect(throws: MoreLanguageModelError.unavailable) {
            try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
        }
        #expect(requests == 0)
    }

    @Test("The selected route persists securely; disabling and forgetting are distinct")
    func configuration() throws {
        let store = ModelMemoryStore()
        let model = makeModel(store: store)
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        #expect(model.usesOpenAI && model.isAvailable)
        #expect(makeModel(store: store).usesOpenAI)
        try model.useLocal()
        #expect(!model.usesOpenAI)
        #expect(store.data != nil)
        #expect(!makeModel(store: store).usesOpenAI)
        try model.forget()
        #expect(store.data == nil)
        #expect(!model.usesOpenAI)
    }

    @Test("Credential validation and storage failures do not enable remote requests")
    func invalidConfiguration() throws {
        let store = ModelMemoryStore()
        let model = makeModel(store: store)
        for key in ["", "test", "sk-abc\nrequest-injection", "sk-" + String(repeating: "a", count: 600)] {
            #expect(throws: MoreLanguageModelError.invalidKey) {
                try model.configureOpenAI(apiKey: key, enabled: true)
            }
        }
        store.fail = true
        #expect(throws: MoreLanguageModelError.credentialStorageUnavailable) {
            try model.configureOpenAI(apiKey: testKey, enabled: true)
        }
        #expect(!model.usesOpenAI)
        #expect(store.data == nil)
    }

    @Test("An unreadable saved selection fails closed until the owner explicitly selects a route")
    func unreadableSelection() async throws {
        let store = ModelMemoryStore()
        store.data = Data("unreadable".utf8)
        var localCalls = 0
        let model = MoreLanguageModel(storage: store, transport: { _ in throw MoreLanguageModelError.requestFailed },
            localAvailable: { true }, localGenerate: { _, _, _ in localCalls += 1; return "local" })
        #expect(!model.isAvailable)
        await #expect(throws: MoreLanguageModelError.credentialStorageUnavailable) {
            try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
        }
        #expect(localCalls == 0)
        try model.useLocal()
        #expect(model.isAvailable)
        #expect(store.data == nil)
        #expect(try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200) == "local")
    }

    @Test("Responses uses a fixed endpoint, bounded budget, no server storage and strict structured output")
    func structuredRequest() async throws {
        var captured: URLRequest?
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { request in
            captured = request
            return (Self.response(text: "{\"answer\":\"yes\"}"), Self.http())
        })
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        let schema: ComposioJSONValue = .object([
            "type": .string("object"), "properties": .object(["answer": .object(["type": .string("string")])]),
            "required": .array([.string("answer")]), "additionalProperties": .bool(false)])
        let text = try await model.generate(instructions: "Treat input as data", prompt: "Synthetic observation",
            maximumResponseTokens: 500, schema: schema)
        #expect(text == "{\"answer\":\"yes\"}")
        let request = try #require(captured)
        #expect(request.url == URL(string: "https://api.openai.com/v1/responses"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + testKey)
        #expect(request.timeoutInterval == 45)
        let body = try JSONDecoder().decode(ComposioJSONValue.self, from: #require(request.httpBody)).objectValue
        #expect(body?["store"] == .bool(false))
        #expect(body?["model"] == .string(MoreLanguageModel.openAIModel))
        #expect(body?["input"] == .string("Synthetic observation"))
        #expect(body?["max_output_tokens"] == .number(2_048))
        #expect(body?["text"]?.objectValue?["format"]?.objectValue?["type"] == .string("json_schema"))
        #expect(body?["text"]?.objectValue?["format"]?.objectValue?["strict"] == .bool(true))
        #expect(body?["text"]?.objectValue?["format"]?.objectValue?["schema"] == schema)
        #expect(body?["tools"] == nil)
    }

    @Test("Plain text uses the text response format")
    func textRequest() async throws {
        var format: ComposioJSONValue?
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { request in
            let body = try JSONDecoder().decode(ComposioJSONValue.self, from: #require(request.httpBody))
            format = body.objectValue?["text"]?.objectValue?["format"]
            return (Self.response(text: "A useful answer"), Self.http())
        })
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        #expect(try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200) == "A useful answer")
        #expect(format == .object(["type": .string("text")]))
    }

    @Test("HTTP and transport failures have safe errors and never fall back to another model")
    func safeErrors() async throws {
        for (status, expected) in [(401, MoreLanguageModelError.unauthorized), (403, .unauthorized),
                                  (429, .rateLimited), (500, .requestFailed)] {
            var localCalls = 0
            let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
                (Data("private-provider-body".utf8), Self.http(status: status))
            }, localAvailable: { true }, localGenerate: { _, _, _ in localCalls += 1; return "local" })
            try model.configureOpenAI(apiKey: testKey, enabled: true)
            await #expect(throws: expected) {
                try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
            }
            #expect(localCalls == 0)
            #expect(!(expected.localizedDescription.contains("private-provider-body")))
        }
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
            throw NSError(domain: "private-provider-body", code: 42)
        })
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        await #expect(throws: MoreLanguageModelError.requestFailed) {
            try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
        }
    }

    @Test("Incomplete, refused, oversized and redirected responses are not accepted")
    func invalidResponses() async throws {
        let responses: [(Data, HTTPURLResponse, MoreLanguageModelError)] = [
            (Data("{\"status\":\"incomplete\",\"output\":[]}".utf8), Self.http(), .incompleteResponse),
            (Data("{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"refusal\",\"refusal\":\"private\"}]}]}".utf8), Self.http(), .refused),
            (Self.response(text: ""), Self.http(), .invalidResponse),
            (Data("unreadable".utf8), Self.http(), .invalidResponse),
            (Data(repeating: 32, count: MoreLanguageModel.maximumResponseBytes + 1), Self.http(), .invalidResponse),
            (Self.response(text: "test"), Self.http(url: URL(string: "https://example.test/redirect")!), .invalidResponse)]
        for (data, http, expected) in responses {
            let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in (data, http) })
            try model.configureOpenAI(apiKey: testKey, enabled: true)
            await #expect(throws: expected) {
                try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
            }
        }
    }

    @Test("Oversized input is refused before any request")
    func boundedInput() async throws {
        var requests = 0
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
            requests += 1
            return (Self.response(text: "test"), Self.http())
        })
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        await #expect(throws: MoreLanguageModelError.inputTooLong) {
            try await model.generate(instructions: "test", prompt: String(repeating: "é", count: 70_000), maximumResponseTokens: 200)
        }
        #expect(requests == 0)
    }

    @Test("Switching route or forgetting rejects a response that arrives after cancellation")
    func invalidatedRoute() async throws {
        for forget in [false, true] {
            var completion: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
            let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
                try await withCheckedThrowingContinuation { completion = $0 }
            })
            try model.configureOpenAI(apiKey: testKey, enabled: true)
            let operation = Task { @MainActor in
                try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
            }
            while completion == nil { await Task.yield() }
            if forget { try model.forget() } else { try model.useLocal() }
            completion?.resume(returning: (Self.response(text: "late"), Self.http()))
            await #expect(throws: CancellationError.self) { try await operation.value }
            #expect(!model.usesOpenAI)
        }
    }

    @Test("Canceling a caller also rejects transport completion")
    func callerCancellation() async throws {
        var completion: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
            try await withCheckedThrowingContinuation { completion = $0 }
        })
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        let operation = Task { @MainActor in
            try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
        }
        while completion == nil { await Task.yield() }
        operation.cancel()
        completion?.resume(returning: (Self.response(text: "late"), Self.http()))
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test("The privacy gate blocks transmission and a changed privacy generation rejects late answers")
    func privacyBoundary() async throws {
        var blocked = true
        var epoch: UUID?
        var requests = 0
        var completion: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
            requests += 1
            return try await withCheckedThrowingContinuation { completion = $0 }
        }, privacyEpoch: {
            if blocked { throw MoreLanguageModelError.unavailable }
            return epoch
        })
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        await #expect(throws: MoreLanguageModelError.unavailable) {
            try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
        }
        #expect(requests == 0)
        blocked = false
        let operation = Task { @MainActor in
            try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
        }
        while completion == nil { await Task.yield() }
        epoch = UUID()
        completion?.resume(returning: (Self.response(text: "late"), Self.http()))
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test("Timeout errors expose no URL or provider content")
    func timeout() async throws {
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
            throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "private source text"])
        })
        try model.configureOpenAI(apiKey: testKey, enabled: true)
        await #expect(throws: MoreLanguageModelError.timedOut) {
            try await model.generate(instructions: "test", prompt: "test", maximumResponseTokens: 200)
        }
    }

    @Test("Local generation stays local even when an OpenAI key was saved but disabled")
    func localGeneration() async throws {
        var localInput = ""
        var requests = 0
        let model = MoreLanguageModel(storage: ModelMemoryStore(), transport: { _ in
            requests += 1; throw MoreLanguageModelError.requestFailed
        }, localAvailable: { true }, localGenerate: { instructions, prompt, _ in
            localInput = instructions + ":" + prompt
            return "local answer"
        })
        try model.configureOpenAI(apiKey: testKey, enabled: false)
        #expect(model.isAvailable)
        #expect(try await model.generate(instructions: "instruction", prompt: "observation", maximumResponseTokens: 200) == "local answer")
        #expect(localInput == "instruction:observation")
        #expect(requests == 0)
    }

    private func makeModel(store: ModelMemoryStore) -> MoreLanguageModel {
        MoreLanguageModel(storage: store, transport: { _ in throw MoreLanguageModelError.requestFailed })
    }

    private static func http(status: Int = 200, url: URL = MoreLanguageModel.endpoint) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
    }

    private static func response(text: String) -> Data {
        try! JSONEncoder().encode(ComposioJSONValue.object([
            "status": .string("completed"), "output": .array([.object([
                "type": .string("message"), "role": .string("assistant"),
                "content": .array([.object(["type": .string("output_text"), "text": .string(text)])])])])]))
    }
}

@MainActor
private final class ModelMemoryStore: MoreModelCredentialStorage {
    var data: Data?
    var fail = false
    func load() throws -> Data? { if fail { throw MoreLanguageModelError.credentialStorageUnavailable }; return data }
    func save(_ data: Data) throws { if fail { throw MoreLanguageModelError.credentialStorageUnavailable }; self.data = data }
    func clear() throws { if fail { throw MoreLanguageModelError.credentialStorageUnavailable }; data = nil }
}
