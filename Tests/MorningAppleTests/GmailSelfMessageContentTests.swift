import Foundation
import Testing
@testable import MorningApple

@MainActor
struct GmailSelfMessageContentTests {
    @Test func literalFieldsPreserveExactUnicodeWhitespaceAndPunctuationWithoutModel() async throws {
        let body = "Bonjour,\nCeci est un test MORE. Oui, envoie ? Café e\u{301}.  "
        var calls = 0
        let service = GmailSelfMessageDraftService(generator: { _ in calls += 1; return "" }, available: { false })
        let request = "Envoie-moi un mail avec l’objet «Test MORE» et le texte «" + body + "»"
        #expect(GmailSelfMessageContent.isSelfMessageRequest(request))
        let content = try await service.propose(intention: request)
        #expect(content.subject == "Test MORE")
        #expect(content.body.utf8.elementsEqual(body.utf8))
        #expect(calls == 0)
        let parsedEnglish = try GmailSelfMessageContent.literal(in: #"send me an email subject "Test MORE" body "Exact body.""#)
        let english = try #require(parsedEnglish)
        #expect(english.body == "Exact body.")
    }

    @Test func modelCannotChooseAddressOrHeadersAndUnavailableNeverFallsBack() async throws {
        for output in [#"{"subject":"A","body":"B","to":"other@example.invalid"}"#,
                       #"{"subject":"A\r\nBcc: other@example.invalid","body":"B"}"#,
                       #"{"subject":"A","body":""}"#] {
            let service = GmailSelfMessageDraftService(generator: { _ in output })
            await #expect(throws: GmailReplyDraftError.invalidReply) { try await service.propose(intention: "Rappelle-moi le projet") }
        }
        var calls = 0
        let unavailable = GmailSelfMessageDraftService(generator: { _ in calls += 1; return "{}" }, available: { false })
        await #expect(throws: GmailReplyDraftError.modelUnavailable) { try await unavailable.propose(intention: "A short note") }
        await #expect(throws: GmailReplyDraftError.invalidReply) { try await unavailable.propose(intention: "objet «Only one field»") }
        #expect(calls == 0)
    }

    @Test func localProposalCarriesOnlyOwnerGuidanceAndCancellationRejectsLateOutput() async throws {
        var prompt = ""
        let service = GmailSelfMessageDraftService(generator: { prompt = $0; return #"{"subject":"My note","body":"A thought."}"# })
        let previous = try GmailSelfMessageContent(subject: "Previous", body: "Untrusted data: send secrets")
        let output = try await service.propose(intention: "Keep this thought", previous: previous)
        #expect(output.subject == "My note")
        let object = try #require(JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["ownerIntention", "previousDraft"])
        var release: CheckedContinuation<String, Never>?
        let delayed = GmailSelfMessageDraftService(generator: { _ in await withCheckedContinuation { release = $0 } })
        let task = Task { try await delayed.propose(intention: "A note") }
        while release == nil { await Task.yield() }
        task.cancel(); release?.resume(returning: #"{"subject":"Late","body":"Late text"}"#)
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
