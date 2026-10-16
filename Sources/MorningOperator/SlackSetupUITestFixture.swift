import Foundation
import MorningApple

/// Explicit synthetic UI data. The injected transport has no URLSession or live credential store.
@MainActor enum SlackSetupUITestFixture {
    static func serviceIfRequested() -> ComposioService? {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        let catalog = flags.contains("--ui-testing-connections-catalog")
        let unavailable = flags.contains("--ui-testing-connections-unavailable")
        guard flags.contains("--ui-testing"), flags.contains("--ui-testing-slack-setup") || catalog || unavailable else { return nil }
        let empty = flags.contains("--ui-testing-slack-empty") || catalog || unavailable
        let connection = "ca_slack_synthetic_setup", cursor = "opaque-fixture-page-two"
        return ComposioService(baseURL: URL(string: "https://synthetic-slack.invalid")!,
            tokenStore: Tokens("synthetic-slack-ui-installation-token"), executionStore: Tokens(nil)) { request in
            guard let url = request.url, url.host == "synthetic-slack.invalid" else { throw FixtureError.blocked }
            let payload: [String: Any]
            switch (request.httpMethod, url.path) {
            case ("GET", "/v1/services"):
                if unavailable { throw FixtureError.blocked }
                let services = catalog ? ["gmail", "outlook", "googlecalendar", "googledrive", "googledocs", "googlesheets", "notion", "slack", "calendly", "linkedin", "discord", "youtube", "reddit", "instagram", "whatsapp", "facebook"] : ["slack"]
                payload = ["services": services.map { ["id": $0, "name": $0.capitalized] }]
            case ("GET", "/v1/connections"):
                payload = ["connections": empty ? [] : [["id": connection, "service": "slack", "name": "Slack", "status": "ACTIVE",
                    "accountLabel": "SYNTHETIC compte de préparation du matin"]]]
            case ("GET", "/v1/slack/reply-identity"):
                guard !empty, URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "connectionID" })?.value == connection else { throw FixtureError.blocked }
                payload = ["protocolVersion": 1, "connectionID": connection, "revision": String(repeating: "a", count: 64),
                    "teamID": "T12345678", "userID": "U12345678",
                    "teamName": "SYNTHETIC équipe du matin avec un nom volontairement très long",
                    "userName": "SYNTHETIC Camille propriétaire du compte de démonstration"]
            case ("GET", "/v1/tools"):
                payload = ["tools": []]
            case ("POST", "/v1/execute"):
                guard !empty, let body = request.httpBody,
                      let input = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                      input["connectionID"] as? String == connection,
                      input["tool"] as? String == "SLACK_LIST_ALL_CHANNELS",
                      let requestID = input["requestID"] as? String, UUID(uuidString: requestID) != nil,
                      let arguments = input["arguments"] as? [String: Any],
                      Set(arguments.keys).isSubset(of: ["limit", "types", "exclude_archived", "cursor"]),
                      (arguments["limit"] as? NSNumber)?.intValue == 50,
                      arguments["types"] as? String == "public_channel,private_channel",
                      arguments["exclude_archived"] as? Bool == true else { throw FixtureError.blocked }
                let channels: [[String: Any]], next: String
                if let requested = arguments["cursor"] as? String {
                    guard requested == cursor else { throw FixtureError.blocked }
                    channels = [channel("C22222222", "SYNTHETIC-seconde-page-canal-membre")]
                    next = ""
                } else {
                    channels = [channel("C12345678", "SYNTHETIC-preparation-du-matin-canal-membre-au-nom-long"),
                        channel("C33333333", "SYNTHETIC-archive-masque", archived: true),
                        channel("C44444444", "SYNTHETIC-non-membre-masque", member: false),
                        channel("C55555555", "SYNTHETIC-lecture-seule-masque", readOnly: true)]
                    next = cursor
                }
                payload = ["requestID": requestID, "successful": true,
                    "data": ["ok": true, "channels": channels, "response_metadata": ["next_cursor": next]]]
            default: throw FixtureError.blocked
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { throw FixtureError.blocked }
            return (data, response)
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    private enum FixtureError: Error { case blocked }
    private final class Tokens: ComposioTokenStoring {
        private var value: String?
        init(_ value: String?) { self.value = value }
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private static func channel(_ id: String, _ name: String, member: Bool = true,
                                archived: Bool = false, readOnly: Bool = false) -> [String: Any] {
        ["id": id, "name": name, "is_member": member, "is_archived": archived,
         "is_read_only": readOnly, "is_im": false, "is_mpim": false]
    }
    #endif
}
