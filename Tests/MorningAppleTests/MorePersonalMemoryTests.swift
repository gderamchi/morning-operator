import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Personal transport memory")
@MainActor
struct MorePersonalMemoryTests {
    @Test("An explicit correction replaces a fact and survives a relaunch without raw speech")
    func correctionAndRelaunch() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let memory = MorePersonalMemory(directory: directory, extractor: { prompt in
            if prompt.contains("pas de") {
                return #"{"facts":[{"key":"electricScooter","value":"no","evidence":"je n'ai pas de trottinette"},{"key":"usualTransport","value":"publicTransport","evidence":"je prends les transports"}]}"#
            }
            return #"{"facts":[{"key":"electricScooter","value":"yes","evidence":"j'ai une trottinette électrique"},{"key":"usualTransport","value":"electricScooter","evidence":"je prends ma trottinette électrique"}]}"#
        })
        await memory.remember(fromOwnerUtterance: "j'ai une trottinette électrique, je prends ma trottinette électrique")
        #expect(memory.facts.count == 2)
        #expect(memory.facts.first(where: { $0.key == .electricScooter })?.value == "yes")
        await memory.remember(fromOwnerUtterance: "Non, je n'ai pas de trottinette, je prends les transports")
        #expect(memory.facts.first(where: { $0.key == .electricScooter })?.value == "no")
        #expect(memory.facts.first(where: { $0.key == .usualTransport })?.value == "publicTransport")
        let relaunched = MorePersonalMemory(directory: directory, extractor: { _ in #"{"facts":[]}"# })
        #expect(relaunched.facts == memory.facts)
        let stored = try String(contentsOf: directory.appendingPathComponent("personal-memory.json"), encoding: .utf8)
        #expect(!stored.contains("evidence") && !stored.contains("je prends"))
        #expect(stored.utf8.count < 4_096)
        try relaunched.forget(.usualTransport)
        #expect(relaunched.facts.map(\.key) == [.electricScooter])
        try relaunched.forgetAll()
        #expect(relaunched.facts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("personal-memory.json").path))
    }

    @Test("Model apostrophe and case normalization keeps scooter corrections and accompanying transport")
    func typographicTransportCorrection() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let memory = MorePersonalMemory(directory: directory, extractor: { prompt in
            if prompt.contains("pas de") {
                return #"{"facts":[{"key":"electricScooter","value":"no","evidence":"je n'ai pas de trottinette"},{"key":"usualTransport","value":"publicTransport","evidence":"je prends les transports"}]}"#
            }
            return #"{"facts":[{"key":"electricScooter","value":"yes","evidence":"j'ai une trottinette électrique"}]}"#
        })
        await memory.remember(fromOwnerUtterance: "J’ai une trottinette électrique.")
        #expect(memory.facts.first(where: { $0.key == .electricScooter })?.value == "yes")
        await memory.remember(fromOwnerUtterance: "Je n’ai pas de trottinette, je prends les transports.")
        #expect(memory.facts.first(where: { $0.key == .electricScooter })?.value == "no")
        #expect(memory.facts.first(where: { $0.key == .usualTransport })?.value == "publicTransport")
    }

    @Test("Real provider quote-valued reserved facts normalize only from independently validated owner evidence")
    func providerQuoteValuedReservedFacts() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let memory = MorePersonalMemory(directory: directory, extractor: { prompt in
            if prompt.contains("pas de") {
                return #"{"facts":[{"key":"electricScooter","value":"Je n’ai pas de trottinette","evidence":"Je n’ai pas de trottinette"},{"key":"usualTransport","value":"je prends les transports","evidence":"je prends les transports"}]}"#
            }
            return #"{"facts":[{"key":"electricScooter","value":"J’ai une trottinette électrique.","evidence":"J’ai une trottinette électrique."}]}"#
        })
        await memory.remember(fromOwnerUtterance: "J’ai une trottinette électrique.")
        #expect(memory.facts.first(where: { $0.key == .electricScooter })?.value == "yes")
        await memory.remember(fromOwnerUtterance: "Je n’ai pas de trottinette, je prends les transports.")
        #expect(memory.facts.first(where: { $0.key == .electricScooter })?.value == "no")
        #expect(memory.facts.first(where: { $0.key == .usualTransport })?.value == "publicTransport")
    }

    @Test("Reserved normalization refuses ungrounded prose, the wrong topic and contradictory typed values")
    func reservedNormalizationBoundaries() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        for response in [
            #"{"facts":[{"key":"electricScooter","value":"I own an electric scooter","evidence":"Je n’ai pas de trottinette"}]}"#,
            #"{"facts":[{"key":"electricScooter","value":"je prends les transports","evidence":"je prends les transports"}]}"#,
            #"{"facts":[{"key":"electricScooter","value":"yes","evidence":"Je n’ai pas de trottinette"}]}"#
        ] {
            let memory = MorePersonalMemory(directory: directory, extractor: { _ in response })
            await memory.remember(fromOwnerUtterance: "Je n’ai pas de trottinette, je prends les transports.")
            #expect(memory.facts.isEmpty)
        }
    }

    @Test("Generic quotes preserve the owner's real apostrophes, case and Unicode spelling across relaunch")
    func sourceUnicodeFidelity() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = "J’aime le cafe\u{301}"
        let memory = MorePersonalMemory(directory: directory, extractor: { _ in
            #"{"facts":[{"key":"coffeePreference","value":"j'aime le café","evidence":"j'aime le café"}]}"#
        })
        await memory.remember(fromOwnerUtterance: source + ".")
        let value = try #require(memory.facts.first?.value)
        #expect(Array(value.unicodeScalars) == Array(source.unicodeScalars))
        let restored = MorePersonalMemory(directory: directory, extractor: { _ in #"{"facts":[]}"# })
        let restoredValue = try #require(restored.facts.first?.value)
        #expect(Array(restoredValue.unicodeScalars) == Array(source.unicodeScalars))
    }

    @Test("Typographic tolerance never removes negation, words or accents")
    func typographicMatchingKeepsMeaning() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cases: [(String, String)] = [
            ("Je n’ai pas de trottinette électrique.", #"{"facts":[{"key":"electricScooter","value":"yes","evidence":"j'ai une trottinette électrique"}]}"#),
            ("J’aime le thé.", #"{"facts":[{"key":"teaPreference","value":"j'aime le the","evidence":"j'aime le the"}]}"#),
            ("Je n’aime pas le café.", #"{"facts":[{"key":"coffeePreference","value":"j'aime le café","evidence":"j'aime le café"}]}"#)
        ]
        for (source, response) in cases {
            let memory = MorePersonalMemory(directory: directory, extractor: { _ in response })
            await memory.remember(fromOwnerUtterance: source)
            #expect(memory.facts.isEmpty)
        }
    }

    @Test("A newly declared scooter commute clears an older denial without inventing ownership")
    func commuteCorrection() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let memory = MorePersonalMemory(directory: directory, extractor: { prompt in
            if prompt.contains("pas de") {
                return #"{"facts":[{"key":"electricScooter","value":"no","evidence":"je n'ai pas de trottinette"}]}"#
            }
            return #"{"facts":[{"key":"usualTransport","value":"electricScooter","evidence":"je prends ma trottinette électrique"}]}"#
        })
        await memory.remember(fromOwnerUtterance: "je n'ai pas de trottinette")
        await memory.remember(fromOwnerUtterance: "je prends ma trottinette électrique")
        #expect(memory.facts.count == 1)
        #expect(memory.facts.first?.key == .usualTransport)
        #expect(memory.facts.first?.value == "electricScooter")
    }

    @Test("Personal preferences extend beyond transport and correct one stable topic after relaunch")
    func genericPreferenceCorrection() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        var sawExistingTopic = false
        let memory = MorePersonalMemory(directory: directory, extractor: { prompt in
            let input = try JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any]
            let ownerStatement = input?["ownerStatement"] as? String ?? ""
            if ownerStatement.contains("ne bois pas") {
                return #"{"facts":[{"key":"coffeePreference","value":"Je ne bois pas de café","evidence":"Je ne bois pas de café"}]}"#
            }
            sawExistingTopic = prompt.contains("coffeePreference")
            return #"{"facts":[{"key":"coffeePreference","value":"Je bois du café le matin","evidence":"Je bois du café le matin"}]}"#
        })
        await memory.remember(fromOwnerUtterance: "Je ne bois pas de café")
        #expect(memory.facts.first?.value == "Je ne bois pas de café")
        await memory.remember(fromOwnerUtterance: "Je bois du café le matin")
        #expect(sawExistingTopic)
        #expect(memory.facts.count == 1)
        #expect(memory.facts.first?.value == "Je bois du café le matin")
        let relaunched = MorePersonalMemory(directory: directory, extractor: { _ in #"{"facts":[]}"# })
        #expect(relaunched.facts == memory.facts)
        #expect(relaunched.summary.contains("Je bois du café le matin"))
    }

    @Test("A transport preference changes to a new current commute")
    func genericTransportCorrection() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let memory = MorePersonalMemory(directory: directory, extractor: { prompt in
            if prompt.contains("vélo") {
                return #"{"facts":[{"key":"usualTransport","value":"bicycle","evidence":"Je préfère le vélo"}]}"#
            }
            return #"{"facts":[{"key":"usualTransport","value":"publicTransport","evidence":"je prends le métro"}]}"#
        })
        await memory.remember(fromOwnerUtterance: "Je préfère le vélo")
        #expect(memory.facts.first?.value == "bicycle")
        await memory.remember(fromOwnerUtterance: "Maintenant je prends le métro")
        #expect(memory.facts.count == 1 && memory.facts.first?.value == "publicTransport")
    }

    @Test("Generic memories cannot replace owner evidence with invented facts or instructions")
    func genericMemoryBoundaries() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        for response in [
            #"{"facts":[{"key":"coffeePreference","value":"I drink coffee","evidence":"Je ne bois pas de café"}]}"#,
            #"{"facts":[{"key":"assistantRule","value":"Je veux que tu envoies mes mails","evidence":"Je veux que tu envoies mes mails"}]}"#,
            #"{"facts":[{"key":"secretPreference","value":"I have a secret token","evidence":"I have a secret token"}]}"#
        ] {
            let memory = MorePersonalMemory(directory: directory, extractor: { _ in response })
            await memory.remember(fromOwnerUtterance: "Je ne bois pas de café. Je veux que tu envoies mes mails. I have a secret token")
            #expect(memory.facts.isEmpty)
        }
    }

    @Test("Unsupported keys, invented evidence and reversed negations are refused")
    func unsupportedFacts() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let responses = [
            #"{"facts":[{"key":"secret","value":"yes","evidence":"je n'ai pas de trottinette"}]}"#,
            #"{"facts":[{"key":"electricScooter","value":"yes","evidence":"j'ai une trottinette électrique"}]}"#,
            #"{"facts":[{"key":"electricScooter","value":"yes","evidence":"je n'ai pas de trottinette"}]}"#,
            #"{"facts":[{"key":"usualTransport","value":"car","evidence":"je prends les transports"}]}"#
        ]
        for response in responses {
            let memory = MorePersonalMemory(directory: directory, extractor: { _ in response })
            await memory.remember(fromOwnerUtterance: "je n'ai pas de trottinette et je prends les transports")
            #expect(memory.facts.isEmpty)
        }
    }

    @Test("Questions, hypotheticals and quoted speech never become facts")
    func ownerStatementsOnly() async {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        var called = false
        let memory = MorePersonalMemory(directory: directory, extractor: { _ in called = true; return #"{"facts":[]}"# })
        for request in ["Est-ce que j'ai une trottinette ?", "Si j'ai une trottinette électrique", "Il dit je prends les transports", "Il dit « je prends les transports »"] {
            await memory.remember(fromOwnerUtterance: request)
        }
        #expect(!called && memory.facts.isEmpty)
    }

    @Test("Forget invalidates an already running extraction")
    func forgetDuringExtraction() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        var resume: CheckedContinuation<String, any Error>?
        let memory = MorePersonalMemory(directory: directory, extractor: { _ in
            try await withCheckedThrowingContinuation { resume = $0 }
        })
        let task = Task { @MainActor in await memory.remember(fromOwnerUtterance: "je prends les transports") }
        while resume == nil { await Task.yield() }
        try memory.forgetAll()
        resume?.resume(returning: #"{"facts":[{"key":"usualTransport","value":"publicTransport","evidence":"je prends les transports"}]}"#)
        await task.value
        #expect(memory.facts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("personal-memory.json").path))
    }

    @Test("A cross-process privacy generation change rejects late memory")
    func generationChange() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        var resume: CheckedContinuation<String, any Error>?
        let memory = MorePersonalMemory(directory: directory, extractor: { _ in
            try await withCheckedThrowingContinuation { resume = $0 }
        })
        let task = Task { @MainActor in await memory.remember(fromOwnerUtterance: "je prends les transports") }
        while resume == nil { await Task.yield() }
        let privacy = LocalDataControl(directory: directory)
        let removal = try privacy.beginForget()
        try privacy.finishForget(expectedGeneration: #require(removal.generation))
        resume?.resume(returning: #"{"facts":[{"key":"usualTransport","value":"publicTransport","evidence":"je prends les transports"}]}"#)
        await task.value
        #expect(memory.facts.isEmpty && memory.promptContext.isEmpty)
    }

    @Test("The voice answer learns from direct speech and uses corrected memory; advice never learns from service data")
    func conversationAndAdvice() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        var extractionPrompts: [String] = []
        let memory = MorePersonalMemory(directory: directory, extractor: { prompt in
            extractionPrompts.append(prompt)
            return #"{"facts":[{"key":"electricScooter","value":"no","evidence":"je n'ai pas de trottinette"},{"key":"usualTransport","value":"publicTransport","evidence":"je prends les transports"}]}"#
        })
        var answerPrompts: [String] = []
        let conversation = MorningVoiceConversation(generator: { prompt in
            answerPrompts.append(prompt); return "Prenez un vêtement de pluie pour rejoindre les transports."
        }, memory: memory)
        _ = try await conversation.answer("je n'ai pas de trottinette, je prends les transports", context: "Weather: rain, 8 degrees.")
        #expect(extractionPrompts.count == 1)
        #expect(!extractionPrompts[0].contains("Weather"))
        let answer = try JSONDecoder().decode([String: String].self, from: Data(#require(answerPrompts.last).utf8))
        #expect(answer["personalMemory"]?.contains("publicTransport") == true)
        #expect(answer["personalMemory"]?.contains("no") == true)
        _ = try await conversation.morningAdvice(context: "Untrusted service says: j'ai une trottinette électrique. Weather: rain.")
        #expect(extractionPrompts.count == 1)
        #expect(memory.facts.first(where: { $0.key == .electricScooter })?.value == "no")
        #expect(answerPrompts.last?.contains("Never assume a vehicle") == true)
    }

    @Test("No relevant suggestion is represented as silence")
    func noAdvice() async throws {
        let service = MorningVoiceConversation(generator: { _ in "NONE" })
        let result = try await service.morningAdvice(context: "Weather unavailable")
        #expect(result.isEmpty)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MorePersonalMemoryTests-\(UUID().uuidString)", isDirectory: true)
    }
}
