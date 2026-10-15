import Foundation
import Testing
@testable import MorningCore

@Suite("Reviewed Outlook routine target")
struct OutlookRoutineTargetTests {
    @Test func approvedSessionRetainsTheSelectedMailboxButPortableImportCannotAcquireIt() throws {
        let account = try OutlookInboxTarget(connectionID: "ca_synthetic_outlook", accountID: "synthetic-graph-account",
            displayName: "Synthetic personal mailbox", mailboxAddress: "owner@example.invalid")
        let action = RoutineStepTarget.outlookInbox(account)
        let step = RoutineStep(title: "Inbox", kind: .messages, durationMinutes: 3, target: action)
        let approved = RoutineVersion(sourceLabel: "Synthetic Outlook selection", steps: [step], isApproved: true)
        let session = RoutineSession(routine: approved)
        let data = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(RoutineSession.self, from: data)
        #expect(restored.routine.isApproved && restored.routine.steps[0].target == action)
        #expect(action.integrationRoute == .api && action.isConnectedAction && action.destination == .connectedService)
        let saved = String(decoding: data, as: UTF8.self)
        #expect(!saved.contains("cutoff") && !saved.contains("argumentsJSON") && !saved.contains("OUTLOOK_LIST_MESSAGES"))
        let portable = try PortableRoutineDocument(routine: approved, detail: .includeDetails).encoded()
        let text = String(decoding: portable, as: UTF8.self)
        #expect(!text.contains(account.connectionID) && !text.contains(account.accountID) && !text.contains(account.mailboxAddress!))
        let imported = try PortableRoutineDocument.decode(portable).importedDraft(replacing: nil)
        #expect(!imported.isApproved && imported.steps[0].target == nil && imported.steps[0].automation == nil)
    }
}
