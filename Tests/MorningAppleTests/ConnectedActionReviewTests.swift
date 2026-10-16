import Foundation
import Testing
@testable import MorningApple

@Suite("Saved account-action consent")
struct ConnectedActionReviewTests {
    @Test("Account, schema labels and every nested value survive the saved review")
    func completeReview() throws {
        let schema = ComposioJSONValue.object(["properties": .object([
            "to": .object(["title": .string("Recipient")]),
            "message": .object(["properties": .object(["body": .object(["title": .string("Reply text")])])])
        ])])
        let json = "{\"to\":\"person@example.test\",\"message\":{\"body\":\"First line\\nLast sentence with a complete commitment.\"},\"attachments\":[\"plan.pdf\",\"agenda.txt\"]}"
        let review = try ConnectedActionReview.summary(argumentsJSON: json, schema: schema,
            account: "Work · owner@example.test", french: false)
        #expect(review.contains("Account: Work · owner@example.test"))
        #expect(review.contains("Recipient: person@example.test"))
        #expect(review.contains("Reply text: First line"))
        #expect(review.contains("Last sentence with a complete commitment."))
        #expect(review.contains("1. plan.pdf") && review.contains("2. agenda.txt"))
        #expect(!review.contains("{\"") && !review.contains("CREATE_MESSAGE"))
    }

    @Test("Empty, unknown, false and zero remain distinct")
    func emptyValues() throws {
        let review = try ConnectedActionReview.summary(argumentsJSON: "{\"emptyText\":\"\",\"list\":[],\"details\":{},\"unknown\":null,\"flag\":false,\"count\":0}", french: true)
        for expected in ["Texte vide", "Aucun élément", "Aucun détail", "Aucune valeur", "Non", "0"] {
            #expect(review.contains(expected))
        }
        #expect(try ConnectedActionReview.summary(argumentsJSON: "{}", french: false) == "No extra details to send.")
    }

    @Test("Unreadable or over-limit content is refused in full, never shortened")
    func bounds() throws {
        let complete = String(repeating: "é", count: ConnectedActionReview.maximumSummaryCharacters - 10)
        let json = try ComposioJSONValue.object(["body": .string(complete)]).prettyPrintedJSON()
        let review = try ConnectedActionReview.summary(argumentsJSON: json, french: false)
        #expect(review.hasSuffix(complete))
        let oversized = try ComposioJSONValue.object(["body": .string(String(repeating: "x", count: 32_001))]).prettyPrintedJSON()
        #expect(throws: ConnectedActionReviewError.tooLarge) {
            try ConnectedActionReview.summary(argumentsJSON: oversized, french: false)
        }
        #expect(throws: ConnectedActionReviewError.unreadable) {
            try ConnectedActionReview.summary(argumentsJSON: "[1,2,3]")
        }
        #expect(throws: ConnectedActionReviewError.unreadable) {
            try ConnectedActionReview.summary(argumentsJSON: "{\"body\":\"hidden\\u0000content\"}")
        }
    }

    @Test("Multiline labels cannot impersonate another parameter")
    func labels() throws {
        #expect(ConnectedActionReview.label(for: "replyToAddress") == "Reply To Address")
        #expect(ConnectedActionReview.label(for: "reply_to", definition: .object(["title": .string("Body\nRecipient: impostor")])) == "Reply To")
        var nested: ComposioJSONValue = .string("deep")
        for _ in 0..<14 { nested = .object(["child": nested]) }
        #expect(throws: ConnectedActionReviewError.tooLarge) {
            try ConnectedActionReview.valueText(nested)
        }
    }
}
