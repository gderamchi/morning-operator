import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Connected presentation preserves source and localizes app wording")
struct ConnectedPresentationLanguageTests {
    @Test func commonFieldLabelsAndDecimalsFollowExplicitReviewLanguage() throws {
        let source = "Keep café e\u{301} exactly."
        let arguments: ComposioJSONValue = .object(["subject": .string(source), "body": .string(source), "count": .number(1.5)])
        let french = try ConnectedActionReview.valueText(arguments, french: true)
        let english = try ConnectedActionReview.valueText(arguments, french: false)
        #expect(french.contains("Objet : ") && french.contains("Texte : ") && french.contains("1,5"))
        #expect(english.contains("Subject: ") && english.contains("Body: ") && english.contains("1.5"))
        #expect(french.contains(source) && english.contains(source))
        #expect(ConnectedActionReview.label(for: "customProviderKey", definition: .object(["title": .string("Exact provider label")]), french: true) == "Exact provider label")
    }

    @Test func backendDiagnosticsAreNotShownAsUntranslatedOrPrivateUI() throws {
        let failure = ComposioFailure(code: "provider_timeout", message: "PRIVATE_PROVIDER_PROMPT")
        #expect(!failure.localizedMessage.contains("PRIVATE_PROVIDER_PROMPT"))
        #expect(ComposioServiceError.backend(failure).errorDescription == failure.localizedMessage)
        let unknown = ComposioFailure(code: "new_server_code", message: "PRIVATE_UNKNOWN_DETAIL")
        #expect(!unknown.localizedMessage.contains("PRIVATE_UNKNOWN_DETAIL"))
        let encoded = try JSONEncoder().encode(failure)
        #expect(try JSONDecoder().decode(ComposioFailure.self, from: encoded) == failure)
    }
}
