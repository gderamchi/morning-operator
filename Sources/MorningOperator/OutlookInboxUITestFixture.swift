import Foundation
import MorningApple
import MorningCore

/// Pure intercepted reads. The synthetic installation token never reaches a network.
@MainActor enum OutlookInboxUITestFixture {
    static let connectionID = "ca_synthetic_outlook"
    static let accountID = "synthetic-outlook-owner"
    static let displayName = "SYNTHETIC Camille, compte Outlook de préparation du matin avec un nom volontairement très long"
    static let mailboxAddress = "camille@synthetic.invalid"
    #if DEBUG
    private(set) static var inboxReadCount = 0
    private(set) static var messageReadCount = 0
    private static var observedMessages: [[String: Any]] = []
    #else
    static var inboxReadCount: Int { 0 }
    static var messageReadCount: Int { 0 }
    #endif

    static var isRequested: Bool {
        #if DEBUG
        let flags = ProcessInfo.processInfo.arguments
        return flags.contains("--ui-testing") && flags.contains("--ui-testing-outlook-inbox")
        #else
        return false
        #endif
    }
    static func serviceIfRequested() -> ComposioService? {
        #if DEBUG
        guard isRequested else { return nil }
        inboxReadCount = 0; messageReadCount = 0; observedMessages = []
        let flags = ProcessInfo.processInfo.arguments
        let emptyAccount = flags.contains("--ui-testing-outlook-empty-account")
        let empty = flags.contains("--ui-testing-outlook-empty")
        let partial = flags.contains("--ui-testing-outlook-partial")
        let unavailable = flags.contains("--ui-testing-outlook-unavailable")
        let missingBody = flags.contains("--ui-testing-outlook-body-missing")
        let duplicateHeaders = flags.contains("--ui-testing-outlook-duplicate-headers")
        return ComposioService(baseURL: URL(string: "https://synthetic-outlook.invalid")!,
            tokenStore: Tokens("synthetic-outlook-installation-token"), executionStore: Tokens(nil)) { request in
            guard let url = request.url, url.scheme == "https", url.host == "synthetic-outlook.invalid", url.port == nil,
                  url.user == nil, url.password == nil, url.fragment == nil else { throw FixtureError.blocked }
            var payload: [String: Any]
            switch (request.httpMethod, url.path) {
            case ("GET", "/v1/services"):
                guard url.query == nil else { throw FixtureError.blocked }
                payload = ["services": [["id": "outlook", "name": "Outlook"]]]
            case ("GET", "/v1/connections"):
                guard url.query == nil else { throw FixtureError.blocked }
                payload = ["connections": emptyAccount ? [] : [["id": connectionID, "service": "outlook", "name": "Outlook", "status": "ACTIVE",
                    "accountLabel": "SYNTHETIC compte Outlook de préparation du matin"]]]
            case ("GET", "/v1/tools"):
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard query.count == 1, query[0].name == "service", query[0].value == "outlook" else { throw FixtureError.blocked }
                payload = ["tools": []]
            case ("POST", "/v1/execute"):
                guard url.query == nil, !emptyAccount, let body = request.httpBody, body.count <= 8_192,
                      let input = try JSONDecoder().decode(ComposioJSONValue.self, from: body).objectValue,
                      Set(input.keys) == Set(["connectionID", "tool", "requestID", "arguments"]),
                      input["connectionID"] == .string(connectionID), let requestID = input["requestID"]?.stringValue,
                      UUID(uuidString: requestID) != nil, let arguments = input["arguments"]?.objectValue else { throw FixtureError.blocked }
                let data: [String: Any]
                switch input["tool"]?.stringValue {
                case "OUTLOOK_GET_PROFILE":
                    guard arguments == ["user_id": .string("me"), "select": strings(["id", "displayName", "mail", "userPrincipalName"])] else { throw FixtureError.blocked }
                    data = ["id": accountID, "displayName": displayName, "mail": mailboxAddress, "userPrincipalName": mailboxAddress]
                case "OUTLOOK_LIST_MESSAGES":
                    let prefix = "receivedDateTime le ", suffix = " and isRead eq false"
                    guard let filter = arguments["filter"]?.stringValue, filter.hasPrefix(prefix), filter.hasSuffix(suffix),
                          let cutoff = ISO8601DateFormatter().date(from: String(filter.dropFirst(prefix.count).dropLast(suffix.count))),
                          (0...60).contains(Date().timeIntervalSince(cutoff)),
                          arguments == ["user_id": .string("me"), "folder": .string("inbox"), "top": .number(3),
                            "select": strings(previewFields), "orderby": strings(["receivedDateTime desc"]),
                            "filter": .string(prefix + cutoff.ISO8601Format() + suffix), "response_detail": .string("full")] else { throw FixtureError.blocked }
                    inboxReadCount += 1
                    if unavailable {
                        let error: [String: Any] = ["error": ["code": "provider_unavailable", "message": "SYNTHETIC Outlook reading unavailable. No account is used."]]
                        return (try JSONSerialization.data(withJSONObject: error), try response(url, status: 503))
                    }
                    observedMessages = empty ? [] : rows(cutoff: cutoff, duplicateHeaders: duplicateHeaders)
                    var result: [String: Any] = ["value": observedMessages]
                    if partial { result["@odata.nextLink"] = "https://synthetic-outlook.invalid/opaque-not-followed" }
                    data = result
                case "OUTLOOK_GET_MESSAGE":
                    guard let id = arguments["message_id"]?.stringValue,
                          arguments == ["user_id": .string("me"), "message_id": .string(id), "select": strings(previewFields + ["body"])],
                          let observed = observedMessages.first(where: { $0["id"] as? String == id }) else { throw FixtureError.blocked }
                    messageReadCount += 1
                    var result = observed
                    let ordinal = (observedMessages.firstIndex(where: { $0["id"] as? String == id }) ?? 0) + 1
                    if !missingBody { result["body"] = ["contentType": "text", "content": "SYNTHETIC corps du message \(ordinal) choisi. Préparons les trois priorités de la matinée. Aucun compte réel, aucune pièce jointe et aucune ressource distante ne sont utilisés."] }
                    data = result
                default: throw FixtureError.blocked
                }
                payload = ["requestID": requestID, "successful": true, "data": ["successful": true, "data": data]]
            default: throw FixtureError.blocked
            }
            return (try JSONSerialization.data(withJSONObject: payload), try response(url, status: 200))
        }
        #else
        return nil
        #endif
    }
    #if DEBUG
    private static let previewFields = ["id", "subject", "from", "receivedDateTime", "bodyPreview", "isRead", "isDraft", "hasAttachments", "changeKey", "parentFolderId"]
    private static func strings(_ values: [String]) -> ComposioJSONValue { .array(values.map(ComposioJSONValue.string)) }
    private static func rows(cutoff: Date, duplicateHeaders: Bool) -> [[String: Any]] {
        (0..<3).map { index -> [String: Any] in
            ["id": "synthetic-outlook-message-\(index)", "subject": duplicateHeaders ? "SYNTHETIC même objet reçu le même jour" : ["SYNTHETIC préparer les priorités du matin", "SYNTHETIC un message non lu plus ancien", "SYNTHETIC point de préparation de la journée"][index],
             "from": ["emailAddress": ["name": duplicateHeaders ? "SYNTHETIC Alex" : ["SYNTHETIC Alex", "SYNTHETIC Sam", "SYNTHETIC Camille"][index], "address": "sender\(duplicateHeaders ? 0 : index)@synthetic.invalid"]],
             "receivedDateTime": cutoff.addingTimeInterval(-3_600 - Double(index) * (duplicateHeaders ? 60 : 86_400)).ISO8601Format(),
             "bodyPreview": "SYNTHETIC aperçu \(index + 1), distinct du corps complet.", "isRead": false, "isDraft": false,
             "hasAttachments": index == 1, "changeKey": "synthetic-change-\(index)", "parentFolderId": "synthetic-inbox"]
        }
    }
    private enum FixtureError: Error { case blocked }
    private final class Tokens: ComposioTokenStoring {
        private var value: String?
        init(_ value: String?) { self.value = value }
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private static func response(_ url: URL, status: Int) throws -> HTTPURLResponse {
        guard let value = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { throw FixtureError.blocked }
        return value
    }
    #endif
}
