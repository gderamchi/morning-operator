import Testing
@testable import MorningCore

@Suite("Unattended routine mail actions")
struct ConnectedRoutineActionPolicyTests {
    @Test func mailSendsRepliesAndForwardsWaitForOwnerInstruction() {
        for (service, tool) in [
            ("gmail", "GMAIL_SEND_EMAIL"), ("gmail", "GMAIL_REPLY_TO_THREAD"),
            ("gmail", "GMAIL_SEND_DRAFT"), ("outlook", "OUTLOOK_REPLY_ALL"),
            ("microsoft_outlook", "OUTLOOK_FORWARD_EMAIL"), ("outlook", "sendMail"),
            ("email", "sendEmail"), ("smtp", "SMTP_SEND_EMAIL"),
            ("unknown", "GMAIL_SEND_EMAIL"), ("unknown", "MICROSOFTOUTLOOK_REPLY_TO_EMAIL"),
            ("microsoft_graph", "MICROSOFT_GRAPH_SEND_MAIL")
        ] {
            #expect(ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: service, tool: tool), "\(service) / \(tool)")
        }
    }

    @Test func readsDraftPreparationAndNonmailOperationsRemainAvailable() {
        for (service, tool) in [
            ("gmail", "GMAIL_LIST_EMAILS"), ("gmail", "GMAIL_GET_EMAIL"),
            ("gmail", "GMAIL_GET_SEND_AS_ALIAS"), ("gmail", "GMAIL_LIST_SEND_AS_ALIASES"),
            ("gmail", "GMAIL_CREATE_EMAIL_DRAFT"), ("outlook", "OUTLOOK_SEARCH_EMAILS"),
            ("google_calendar", "GOOGLECALENDAR_CREATE_EVENT"), ("slack", "SLACK_SEND_MESSAGE"),
            ("notion", "NOTION_UPDATE_PAGE"), ("gmail", "GMAIL_GET_SENT_MESSAGES")
        ] {
            #expect(!ConnectedRoutineActionPolicy.requiresSpokenMailSend(service: service, tool: tool), "\(service) / \(tool)")
        }
    }
}
