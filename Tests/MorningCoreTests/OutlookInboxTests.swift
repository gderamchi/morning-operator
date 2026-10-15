import Foundation
import Testing
@testable import MorningCore

@Suite("Outlook bounded read projection")
struct OutlookInboxTests {
    private let cutoff = Date(timeIntervalSince1970: 1_792_145_000)
    private func target() throws -> OutlookInboxTarget {
        try .init(connectionID: "ca_synthetic_outlook", accountID: "opaque-provider-account", displayName: "SYNTHETIC Owner", mailboxAddress: "owner@synthetic.invalid")
    }
    private func preview(id: String = "opaque-message", at date: Date? = nil, text: String? = "Short excerpt") throws -> OutlookMessagePreview {
        try .init(id: id, subject: "SYNTHETIC subject", senderName: "SYNTHETIC sender", senderAddress: "sender@synthetic.invalid", receivedAt: date ?? cutoff.addingTimeInterval(-86_400), previewText: text)
    }

    @Test func targetRoundTripsAndRejectsInvalidDecodedIdentityWithoutRetainingMessagesOrDates() throws {
        let value = try target(), data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(OutlookInboxTarget.self, from: data) == value)
        let invalid = Data(#"{"connectionID":"ca_ok","accountID":"","displayName":"Owner"}"#.utf8)
        #expect(throws: OutlookInboxError.invalidIdentity) { try JSONDecoder().decode(OutlookInboxTarget.self, from: invalid) }
        #expect(!String(decoding: data, as: UTF8.self).contains("cutoff"))
        #expect(!String(describing: value).contains("owner@") && !String(reflecting: value).contains("SYNTHETIC Owner"))
        #expect(value.sourceLabel() == "SYNTHETIC Owner · owner@synthetic.invalid")
        let unnamedMailbox = try OutlookInboxTarget(connectionID: value.connectionID, accountID: value.accountID, displayName: "Directory owner")
        #expect(unnamedMailbox.sourceLabel() == "Directory owner")
        let addressName = try OutlookInboxTarget(connectionID: value.connectionID, accountID: value.accountID, displayName: "OWNER@synthetic.invalid", mailboxAddress: "owner@synthetic.invalid")
        #expect(addressName.sourceLabel() == "OWNER@synthetic.invalid")
    }

    @Test func olderUnreadMessagesRemainEligibleButFutureUnsortedDuplicateOrFourMessagesAreRefused() throws {
        let older = try preview(), recent = try preview(id: "recent", at: cutoff.addingTimeInterval(-5))
        let doc = try OutlookInboxDocument(target: target(), cutoff: cutoff, receivedAt: cutoff, messages: [recent, older], isPartial: false)
        #expect(doc.messages.count == 2 && doc.summary(french: false).contains("Previews only"))
        for rows in [[older, recent], [recent, recent], Array(repeating: older, count: 4), [try preview(at: cutoff.addingTimeInterval(1))]] {
            #expect(throws: OutlookInboxError.invalidResponse) { try OutlookInboxDocument(target: target(), cutoff: cutoff, receivedAt: cutoff, messages: rows, isPartial: false) }
        }
        #expect(doc.isCurrent(at: cutoff.addingTimeInterval(300)))
        #expect(!doc.isCurrent(at: cutoff.addingTimeInterval(301)) && !doc.isCurrent(at: cutoff.addingTimeInterval(-1)))
    }

    @Test func partialEmptyUnavailablePreviewAndEmptyPreviewHaveDifferentTruthfulDescriptions() throws {
        let empty = try OutlookInboxDocument(target: target(), cutoff: cutoff, receivedAt: cutoff, messages: [], isPartial: false)
        let partial = try OutlookInboxDocument(target: target(), cutoff: cutoff, receivedAt: cutoff, messages: [], isPartial: true)
        #expect(empty.summary(french: false).contains("No unread messages"))
        #expect(partial.summary(french: false).contains("partial") && !partial.summary(french: false).contains("No unread messages"))
        let missing = try preview(text: nil), blank = try preview(text: "")
        #expect(missing.summary(french: true).contains("indisponible") && blank.summary(french: true).contains("vide"))
    }

    @Test func fullBodyProjectionIsBoundedMarkedAndDoesNotPretendPreviewIsTheBody() throws {
        let message = try preview(text: "This is only a preview")
        let unavailable = try OutlookMessageDocument(target: target(), message: message, sourceCutoff: cutoff, receivedAt: cutoff, bodyText: nil, bodyIsIncomplete: false)
        #expect(unavailable.bodyText == nil && unavailable.bodyIsIncomplete && unavailable.contextText(french: false).contains("body unavailable"))
        let empty = try OutlookMessageDocument(target: target(), message: message, sourceCutoff: cutoff, receivedAt: cutoff, bodyText: "", bodyIsIncomplete: false)
        #expect(empty.bodyText == "" && !empty.bodyIsIncomplete)
        let long = try OutlookMessageDocument(target: target(), message: message, sourceCutoff: cutoff, receivedAt: cutoff, bodyText: String(repeating: "👨‍👩‍👧‍👦\"\\", count: 4_000), bodyIsIncomplete: false)
        #expect(long.bodyIsIncomplete && (long.bodyText?.utf8.count ?? .max) <= 16_000)
        #expect(long.summary().count <= 2_000 && long.summary(french: false).contains("abbreviated"))
        #expect(try JSONEncoder().encode(long.contextText()).count <= 22_500)
        #expect(!String(describing: long).contains("preview") && !String(reflecting: message).contains("subject"))
    }

    @Test func excerptsAndContextRemainBoundedEvenWithEscapesControlsAndComposedGraphemes() throws {
        let text = String(repeating: "\"\\\n👨‍👩‍👧‍👦", count: 1_000) + "\u{0000}"
        let row = try OutlookMessagePreview(id: "provider/id+=", subject: text, senderName: text, senderAddress: nil, receivedAt: cutoff, previewText: text)
        let doc = try OutlookInboxDocument(target: target(), cutoff: cutoff, receivedAt: cutoff, messages: [row], isPartial: true)
        #expect(row.previewIsTruncated && row.subject.utf8.count <= 1_200 && row.previewText!.utf8.count <= 4_000)
        #expect(!doc.contextText().contains("provider/id+="))
        #expect(try JSONEncoder().encode(doc.contextText()).count <= 22_500)
        let three = try OutlookInboxDocument(target: target(), cutoff: cutoff, receivedAt: cutoff,
            messages: [row, try OutlookMessagePreview(id: "second", subject: text, senderName: text, senderAddress: nil, receivedAt: cutoff, previewText: text),
                       try OutlookMessagePreview(id: "third", subject: text, senderName: text, senderAddress: nil, receivedAt: cutoff, previewText: text)], isPartial: true)
        #expect(three.summary().count <= 2_000 && three.contextText().count > three.summary().count)
    }
}
