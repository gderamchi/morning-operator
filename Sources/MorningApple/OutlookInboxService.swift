import Foundation
import MorningCore

public struct OutlookIdentity: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let target: OutlookInboxTarget
    public let receivedAt: Date
    public var connectionID: String { target.connectionID }
    public var accountID: String { target.accountID }
    public var displayName: String { target.displayName }
    public var mailboxAddress: String? { target.mailboxAddress }
    public init(target: OutlookInboxTarget, receivedAt: Date) throws {
        try target.validate()
        guard receivedAt.timeIntervalSinceReferenceDate.isFinite else { throw OutlookInboxError.invalidIdentity }
        self.target = target; self.receivedAt = receivedAt
    }
    public func isCurrent(at date: Date) -> Bool { (0...300).contains(date.timeIntervalSince(receivedAt)) }
    public var description: String { "OutlookIdentity(redacted)" }
    public var debugDescription: String { description }
}

/// Only the three fixed read operations in Outlook pin 20261014_00. Listing
/// never reads a body. A detailed read requires an exact ID in a fresh snapshot.
@MainActor public final class OutlookInboxService {
    private let service: ComposioService
    private let now: @MainActor () -> Date
    private let timeout: Duration
    public init(service: ComposioService, now: @escaping @MainActor () -> Date = { Date() }, readTimeout: Duration = .seconds(40)) {
        self.service = service; self.now = now
        timeout = min(.seconds(45), max(.milliseconds(1), readTimeout))
    }
    public func identity(connectionID: String) async throws -> OutlookIdentity {
        try await bounded { try await self.readIdentity(connectionID) }
    }
    public func read(target: OutlookInboxTarget) async throws -> OutlookInboxDocument {
        try target.validate()
        let start = now()
        guard start.timeIntervalSince1970.isFinite else { throw OutlookInboxError.staleSource }
        // The same whole-second cutoff is used in the provider filter and snapshot.
        let cutoff = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970))
        return try await bounded { try await self.readInbox(target, cutoff: cutoff) }
    }
    public func message(id: String, from source: OutlookInboxDocument) async throws -> OutlookMessageDocument {
        guard source.isCurrent(at: now()) else { throw OutlookInboxError.staleSource }
        guard let selected = source.messages.first(where: { $0.id == id }) else { throw OutlookInboxError.messageNotObserved }
        return try await bounded { try await self.readMessage(selected, source: source) }
    }
    private func bounded<T: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        do {
            try Task.checkCancellation()
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask { [timeout] in try await Task.sleep(for: timeout); throw OutlookInboxError.unavailable }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw OutlookInboxError.unavailable }
                try Task.checkCancellation(); return result
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as OutlookInboxError { throw error }
        catch { throw OutlookInboxError.unavailable } // Provider diagnostics can contain private mail.
    }
    private func readIdentity(_ connectionID: String) async throws -> OutlookIdentity {
        try await checkConnection(connectionID)
        let result = try await service.readOutlook(tool: OutlookInboxReadContract.identityTool,
            arguments: OutlookInboxReadContract.identityArguments, connectionID: connectionID)
        try Task.checkCancellation()
        let p = try Self.payload(result)
        guard let id = p["id"]?.stringValue, let name = p["displayName"]?.stringValue else { throw OutlookInboxError.invalidIdentity }
        let mail = try Self.optionalString(p["mail"]), principal = try Self.optionalString(p["userPrincipalName"])
        let address: String?
        if let mail, !mail.isEmpty {
            guard OutlookInboxTarget.validAddress(mail) else { throw OutlookInboxError.invalidIdentity }; address = mail
        } else if let principal, OutlookInboxTarget.validAddress(principal) { address = principal }
        else { address = nil } // A directory principal is not necessarily a mailbox address.
        let target = try OutlookInboxTarget(connectionID: connectionID, accountID: id, displayName: name, mailboxAddress: address)
        try await checkConnection(connectionID)
        return try .init(target: target, receivedAt: now())
    }
    private func readInbox(_ target: OutlookInboxTarget, cutoff: Date) async throws -> OutlookInboxDocument {
        let before = try await readIdentity(target.connectionID)
        guard before.target == target else { throw OutlookInboxError.identityChanged }
        try current(cutoff)
        let result = try await service.readOutlook(tool: OutlookInboxReadContract.listTool,
            arguments: OutlookInboxReadContract.listArguments(cutoff: cutoff), connectionID: target.connectionID)
        try Task.checkCancellation()
        let p = try Self.payload(result)
        guard let rows = p["value"]?.arrayValue, rows.count <= 3 else { throw OutlookInboxError.invalidResponse }
        let messages = try rows.map { try Self.preview($0, cutoff: cutoff) }
        let partial = try Self.hasContinuation(p)
        let after = try await readIdentity(target.connectionID)
        guard after.target == target else { throw OutlookInboxError.identityChanged }
        try current(cutoff)
        return try .init(target: target, cutoff: cutoff, receivedAt: now(), messages: messages, isPartial: partial)
    }
    private func readMessage(_ selected: OutlookMessagePreview, source: OutlookInboxDocument) async throws -> OutlookMessageDocument {
        let before = try await readIdentity(source.target.connectionID)
        guard before.target == source.target else { throw OutlookInboxError.identityChanged }
        try current(source.cutoff)
        let result = try await service.readOutlook(tool: OutlookInboxReadContract.messageTool,
            arguments: OutlookInboxReadContract.messageArguments(id: selected.id), connectionID: source.target.connectionID)
        try Task.checkCancellation()
        let p = try Self.payload(result)
        let observed = try Self.preview(.object(p), cutoff: source.cutoff)
        guard observed == selected else { throw OutlookInboxError.messageChanged }
        let body: String?, incomplete: Bool
        if let raw = p["body"], raw != .null {
            guard let object = raw.objectValue, let content = object["content"]?.stringValue,
                  let kind = object["contentType"]?.stringValue?.lowercased(), ["text", "html"].contains(kind) else { throw OutlookInboxError.invalidResponse }
            let limited = Self.bodyPrefix(content)
            if kind == "html" {
                let extracted = GmailHTMLText.extract(limited.value)
                body = extracted.value; incomplete = limited.truncated || extracted.isIncomplete
            } else { body = limited.value; incomplete = limited.truncated }
        } else { body = nil; incomplete = true }
        let after = try await readIdentity(source.target.connectionID)
        guard after.target == source.target else { throw OutlookInboxError.identityChanged }
        try current(source.cutoff)
        return try .init(target: source.target, message: observed, sourceCutoff: source.cutoff,
                         receivedAt: now(), bodyText: body, bodyIsIncomplete: incomplete)
    }
    private func checkConnection(_ id: String) async throws {
        try Task.checkCancellation()
        let matches = try await service.connections().filter { $0.id == id }
        try Task.checkCancellation()
        guard matches.count == 1, matches[0].service == "outlook", matches[0].isActive else { throw OutlookInboxError.unavailable }
    }
    private func current(_ cutoff: Date) throws {
        try Task.checkCancellation()
        guard (0...300).contains(now().timeIntervalSince(cutoff)) else { throw OutlookInboxError.staleSource }
    }
    private static func payload(_ result: ComposioExecutionResult) throws -> [String: ComposioJSONValue] {
        guard result.successful, result.error == nil, result.resultAvailable != false,
              let wrapper = result.data?.objectValue, wrapper["successful"] == .bool(true),
              wrapper["error"] == nil || wrapper["error"] == .null || wrapper["error"] == .string(""),
              let data = wrapper["data"]?.objectValue,
              data["error"] == nil || data["error"] == .null else { throw OutlookInboxError.invalidResponse }
        return data
    }
    private static func preview(_ raw: ComposioJSONValue, cutoff: Date) throws -> OutlookMessagePreview {
        guard let p = raw.objectValue, let id = p["id"]?.stringValue, let received = p["receivedDateTime"]?.stringValue,
              let date = OutlookInboxReadContract.timestamp(received), date <= cutoff,
              p["isRead"] == .bool(false), p["isDraft"] == .bool(false),
              let attachments = p["hasAttachments"]?.boolValue else { throw OutlookInboxError.invalidResponse }
        let name: String, address: String?
        if let raw = p["from"], raw != .null {
            guard let recipient = raw.objectValue, let email = recipient["emailAddress"]?.objectValue else { throw OutlookInboxError.invalidResponse }
            name = try optionalString(email["name"]) ?? ""; address = try optionalString(email["address"])
        } else { name = ""; address = nil }
        return try .init(id: id, subject: optionalString(p["subject"]) ?? "", senderName: name, senderAddress: address,
            receivedAt: date, previewText: optionalString(p["bodyPreview"]), changeKey: optionalString(p["changeKey"]),
            parentFolderID: optionalString(p["parentFolderId"]), hasAttachments: attachments)
    }
    private static func optionalString(_ value: ComposioJSONValue?) throws -> String? {
        guard let value, value != .null else { return nil }
        guard let text = value.stringValue else { throw OutlookInboxError.invalidResponse }; return text
    }
    private static func hasContinuation(_ p: [String: ComposioJSONValue]) throws -> Bool {
        var partial = false
        for key in ["next_page_token", "@odata.nextLink"] {
            guard let value = p[key], value != .null else { continue }
            guard let text = value.stringValue, text.utf8.count <= 8_192,
                  !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw OutlookInboxError.invalidResponse }
            partial = partial || !text.isEmpty // Informational only; never followed or exposed.
        }
        return partial
    }
    private static func bodyPrefix(_ text: String) -> (value: String, truncated: Bool) {
        guard text.utf8.count > 262_144 else { return (text, false) }
        var output = "", bytes = 0
        for scalar in text.unicodeScalars {
            if bytes + scalar.utf8.count > 262_144 { break }; output.unicodeScalars.append(scalar); bytes += scalar.utf8.count
        }
        return (output, true)
    }
}

enum OutlookInboxReadContract {
    static let identityTool = "OUTLOOK_GET_PROFILE", listTool = "OUTLOOK_LIST_MESSAGES", messageTool = "OUTLOOK_GET_MESSAGE"
    static let previewFields = ["id", "subject", "from", "receivedDateTime", "bodyPreview", "isRead", "isDraft", "hasAttachments", "changeKey", "parentFolderId"]
    static let identityArguments: [String: ComposioJSONValue] = ["user_id": .string("me"), "select": strings(["id", "displayName", "mail", "userPrincipalName"])]
    static func listArguments(cutoff: Date) -> [String: ComposioJSONValue] {
        ["user_id": .string("me"), "folder": .string("inbox"), "top": .number(3), "select": strings(previewFields),
         "orderby": strings(["receivedDateTime desc"]), "filter": .string("receivedDateTime le \(cutoff.ISO8601Format()) and isRead eq false"), "response_detail": .string("full")]
    }
    static func messageArguments(id: String) -> [String: ComposioJSONValue] {
        ["user_id": .string("me"), "message_id": .string(id), "select": strings(previewFields + ["body"])]
    }
    static func validRead(_ tool: String, _ args: [String: ComposioJSONValue]) -> Bool {
        if tool == identityTool { return args == identityArguments }
        if tool == messageTool, let id = args["message_id"]?.stringValue, OutlookInboxTarget.validOpaqueID(id) { return args == messageArguments(id: id) }
        if tool == listTool, let filter = args["filter"]?.stringValue {
            let prefix = "receivedDateTime le ", suffix = " and isRead eq false"
            guard filter.hasPrefix(prefix), filter.hasSuffix(suffix), filter.count > prefix.count + suffix.count,
                  let cutoff = timestamp(String(filter.dropFirst(prefix.count).dropLast(suffix.count))) else { return false }
            return args == listArguments(cutoff: cutoff)
        }
        return false
    }
    static func timestamp(_ value: String) -> Date? {
        guard value.utf8.count <= 100, value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: value) { return date }; f.formatOptions = [.withInternetDateTime]; return f.date(from: value)
    }
    private static func strings(_ values: [String]) -> ComposioJSONValue { .array(values.map(ComposioJSONValue.string)) }
}
