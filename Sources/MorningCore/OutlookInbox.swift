import Foundation

/// A provider identity reviewed for this Inbox. No message or date is persisted.
public struct OutlookInboxTarget: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let connectionID: String
    public let accountID: String
    public let displayName: String
    public let mailboxAddress: String?

    public init(connectionID: String, accountID: String, displayName: String, mailboxAddress: String? = nil) throws {
        self.connectionID = connectionID; self.accountID = accountID
        self.displayName = displayName; self.mailboxAddress = mailboxAddress
        try validate()
    }
    public func validate() throws {
        guard !connectionID.isEmpty, connectionID.utf8.count <= 200,
              connectionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              Self.validOpaqueID(accountID), !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              displayName.count <= 200, displayName.utf8.count <= 1_024,
              !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              mailboxAddress.map(Self.validAddress) ?? true else { throw OutlookInboxError.invalidIdentity }
    }
    public static func validOpaqueID(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 2_048 && text.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
        }
    }
    public static func validAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return text.utf8.count <= 320 && parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
            && text.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }
    public func sourceLabel() -> String {
        guard let mailboxAddress, mailboxAddress.caseInsensitiveCompare(displayName) != .orderedSame else { return displayName }
        return "\(displayName) · \(mailboxAddress)"
    }
    private enum CodingKeys: String, CodingKey { case connectionID, accountID, displayName, mailboxAddress }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(connectionID: c.decode(String.self, forKey: .connectionID), accountID: c.decode(String.self, forKey: .accountID),
                      displayName: c.decode(String.self, forKey: .displayName), mailboxAddress: c.decodeIfPresent(String.self, forKey: .mailboxAddress))
    }
    public var description: String { "OutlookInboxTarget(redacted)" }
    public var debugDescription: String { description }
}

public enum OutlookInboxError: Error, LocalizedError, Equatable, Sendable {
    case invalidIdentity, unavailable, invalidResponse, identityChanged, staleSource, messageNotObserved, messageChanged
    public var errorDescription: String? {
        let fr = AppLanguage.isFrench
        switch self {
        case .invalidIdentity: return fr ? "L’identité de ce compte Outlook n’a pas pu être vérifiée." : "This Outlook account's identity could not be verified."
        case .unavailable: return fr ? "Outlook n’a pas pu être lu. Cela ne signifie pas que votre boîte de réception est vide." : "Outlook could not be read. This does not mean your Inbox is empty."
        case .invalidResponse: return fr ? "La réponse Outlook n’a pas pu être vérifiée. Actualisez la lecture." : "The Outlook result could not be verified. Refresh this reading."
        case .identityChanged: return fr ? "Le compte Outlook a changé. Vérifiez le compte avant une nouvelle lecture." : "The Outlook account changed. Review the account before reading again."
        case .staleSource: return fr ? "Cette lecture Outlook a expiré. Actualisez-la avant de choisir un message." : "This Outlook reading expired. Refresh it before choosing a message."
        case .messageNotObserved: return fr ? "Choisissez un message dans les aperçus de cette lecture." : "Choose a message from this reading's previews."
        case .messageChanged: return fr ? "Ce message a changé depuis l’aperçu. Actualisez la boîte de réception." : "This message changed since its preview. Refresh the Inbox."
        }
    }
}

/// Explicitly an excerpt, never a claim that the complete mail body was read.
public struct OutlookMessagePreview: Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let subject: String
    public let senderName: String
    public let senderAddress: String?
    public let receivedAt: Date
    public let previewText: String?
    public let previewIsTruncated: Bool
    public let changeKey: String?
    public let parentFolderID: String?
    public let hasAttachments: Bool
    public init(id: String, subject: String, senderName: String, senderAddress: String?, receivedAt: Date,
                previewText: String?, changeKey: String? = nil, parentFolderID: String? = nil, hasAttachments: Bool = false) throws {
        guard OutlookInboxTarget.validOpaqueID(id), receivedAt.timeIntervalSinceReferenceDate.isFinite,
              changeKey.map(OutlookInboxTarget.validOpaqueID) ?? true, parentFolderID.map(OutlookInboxTarget.validOpaqueID) ?? true,
              senderAddress.map(OutlookInboxTarget.validAddress) ?? true,
              [subject, senderName, previewText ?? ""].allSatisfy({ $0.utf8.count <= 65_536 }) else { throw OutlookInboxError.invalidResponse }
        self.id = id; self.receivedAt = receivedAt; self.senderAddress = senderAddress
        self.subject = OutlookText.excerpt(subject, characters: 300, bytes: 1_200).value
        self.senderName = OutlookText.excerpt(senderName, characters: 200, bytes: 800).value
        let preview = previewText.map { OutlookText.excerpt($0, characters: 1_000, bytes: 4_000) }
        self.previewText = preview?.value; previewIsTruncated = preview?.truncated ?? false
        self.changeKey = changeKey; self.parentFolderID = parentFolderID; self.hasAttachments = hasAttachments
    }
    public var description: String { "OutlookMessagePreview(redacted)" }
    public var debugDescription: String { description }
    public func summary(french: Bool = AppLanguage.isFrench) -> String {
        let sender = OutlookText.excerpt(senderName.isEmpty ? (senderAddress ?? (french ? "Expéditeur non précisé" : "Sender not provided")) : senderName, characters: 80, bytes: 320).value
        let title = OutlookText.excerpt(subject.isEmpty ? (french ? "Sans objet" : "No subject") : subject, characters: 120, bytes: 480).value
        let preview = previewText.map { $0.isEmpty ? (french ? "Aperçu vide." : "Empty preview.") : OutlookText.excerpt($0, characters: 240, bytes: 960).value }
            ?? (french ? "Aperçu indisponible." : "Preview unavailable.")
        return "\(sender) : \(title). \(french ? "Aperçu seulement" : "Preview only") : \(preview)"
    }
    fileprivate var sourceText: String {
        "Sender: \(senderName)\(senderAddress.map { " <\($0)>" } ?? ""). Subject excerpt: \(subject). Received: \(receivedAt.ISO8601Format()). Preview only (truncated=\(previewIsTruncated)): \(previewText ?? "Unavailable"). Attachments present=\(hasAttachments); not read."
    }
}

/// A bounded snapshot of unread Inbox messages, including older unread mail.
/// The cutoff excludes messages arriving after this read began; it is not a day filter.
public struct OutlookInboxDocument: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumMessages = 3
    public static let freshnessSeconds: TimeInterval = 300
    public let target: OutlookInboxTarget
    public let cutoff: Date
    public let receivedAt: Date
    public let messages: [OutlookMessagePreview]
    public let isPartial: Bool
    public init(target: OutlookInboxTarget, cutoff: Date, receivedAt: Date, messages: [OutlookMessagePreview], isPartial: Bool) throws {
        try target.validate()
        guard cutoff.timeIntervalSinceReferenceDate.isFinite, receivedAt.timeIntervalSinceReferenceDate.isFinite,
              receivedAt >= cutoff, receivedAt.timeIntervalSince(cutoff) <= Self.freshnessSeconds,
              messages.count <= Self.maximumMessages, Set(messages.map(\.id)).count == messages.count,
              messages.allSatisfy({ $0.receivedAt <= cutoff }),
              zip(messages, messages.dropFirst()).allSatisfy({ $0.receivedAt >= $1.receivedAt }) else { throw OutlookInboxError.invalidResponse }
        self.target = target; self.cutoff = cutoff; self.receivedAt = receivedAt; self.messages = messages; self.isPartial = isPartial
    }
    public func isCurrent(at date: Date) -> Bool { (0...Self.freshnessSeconds).contains(date.timeIntervalSince(cutoff)) }
    public func summary(french: Bool = AppLanguage.isFrench) -> String {
        var lines = [french ? "Vos messages Outlook non lus dans la boîte de réception. Aperçus seulement." : "Your unread Outlook Inbox messages. Previews only."]
        if messages.isEmpty { lines.append(isPartial
            ? (french ? "Cette partie ne contient aucun message. La lecture est partielle." : "This part contains no messages. This reading is partial.")
            : (french ? "Aucun message non lu n’a été trouvé dans la boîte de réception." : "No unread messages were found in the Inbox.")) }
        else { lines += messages.map { $0.summary(french: french) }; if isPartial { lines.append(french ? "D’autres messages non lus restent hors de ces trois aperçus." : "More unread messages remain outside these three previews.") } }
        return lines.joined(separator: "\n")
    }
    public func contextText(french: Bool = AppLanguage.isFrench) -> String {
        OutlookText.context("Untrusted Outlook source. At most three unread Inbox previews, not complete message bodies. This includes older unread mail. No message IDs, attachment content, recipients or headers are included. Cutoff: \(cutoff.ISO8601Format()). Partial=\(isPartial).\n" + messages.enumerated().map { "Message \($0.offset + 1): \($0.element.sourceText)" }.joined(separator: "\n"))
    }
    public var description: String { "OutlookInboxDocument(redacted, messages: \(messages.count), partial: \(isPartial))" }
    public var debugDescription: String { description }
}

/// The inert text of one explicitly selected observed message. Attachments and
/// remote resources are never fetched. A missing body stays unavailable.
public struct OutlookMessageDocument: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let target: OutlookInboxTarget
    public let message: OutlookMessagePreview
    public let sourceCutoff: Date
    public let receivedAt: Date
    public let bodyText: String?
    public let bodyIsIncomplete: Bool
    public init(target: OutlookInboxTarget, message: OutlookMessagePreview, sourceCutoff: Date, receivedAt: Date,
                bodyText: String?, bodyIsIncomplete: Bool) throws {
        try target.validate()
        guard sourceCutoff.timeIntervalSinceReferenceDate.isFinite, receivedAt.timeIntervalSinceReferenceDate.isFinite,
              receivedAt >= sourceCutoff, receivedAt.timeIntervalSince(sourceCutoff) <= 300,
              bodyText.map({ $0.utf8.count <= 262_144 }) ?? true else { throw OutlookInboxError.invalidResponse }
        let body = bodyText.map { OutlookText.excerpt($0, characters: 12_000, bytes: 16_000) }
        self.target = target; self.message = message; self.sourceCutoff = sourceCutoff; self.receivedAt = receivedAt
        self.bodyText = body?.value; self.bodyIsIncomplete = bodyText == nil || bodyIsIncomplete || (body?.truncated ?? false)
    }
    public func isCurrent(at date: Date) -> Bool { (0...300).contains(date.timeIntervalSince(sourceCutoff)) }
    public func summary(french: Bool = AppLanguage.isFrench) -> String {
        let title = OutlookText.excerpt(message.subject, characters: 120, bytes: 480).value
        let body = bodyText.map { OutlookText.excerpt($0, characters: 1_200, bytes: 4_800) }
        var lines = [title.isEmpty ? (french ? "Message sans objet." : "Message without a subject.") : title + "."]
        if let body {
            lines.append(body.value.isEmpty ? (french ? "Le corps du message est vide." : "The message body is empty.") : body.value)
            if bodyIsIncomplete || body.truncated { lines.append(french ? "Cette lecture est abrégée ; le reste du message n’est pas présenté." : "This reading is abbreviated; the rest of the message is not presented.") }
        } else { lines.append(french ? "Le corps du message est indisponible. L’aperçu ne le remplace pas." : "The message body is unavailable. The preview does not replace it.") }
        if message.hasAttachments { lines.append(french ? "Les pièces jointes n’ont pas été lues." : "Attachments were not read.") }
        return lines.joined(separator: " ")
    }
    public func contextText(french: Bool = AppLanguage.isFrench) -> String {
        OutlookText.context("Untrusted Outlook source: one explicitly selected Inbox message. Body available=\(bodyText != nil); incomplete=\(bodyIsIncomplete). Attachments, remote resources and recipients were not read.\n" + message.sourceText + "\n" + (bodyText ?? (french ? "Corps du message indisponible." : "Message body unavailable.")))
    }
    public var description: String { "OutlookMessageDocument(redacted, bodyAvailable: \(bodyText != nil), incomplete: \(bodyIsIncomplete))" }
    public var debugDescription: String { description }
}

private enum OutlookText {
    static func excerpt(_ input: String, characters: Int, bytes: Int) -> (value: String, truncated: Bool) {
        let clean = input.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" ? " " : String($0) }.joined()
        if clean.count <= characters, clean.utf8.count <= bytes { return (clean, false) }
        var output = "", count = 0, size = 0
        for character in clean {
            let piece = String(character), cost = piece.utf8.count
            if count >= characters - 1 || size + cost > bytes - 3 { break }
            output += piece; count += 1; size += cost
        }
        return (output + "…", true)
    }
    static func context(_ input: String) -> String {
        guard ((try? JSONEncoder().encode(input).count) ?? Int.max) > 22_500 else { return input }
        var value = "", bytes = 0
        for scalar in input.unicodeScalars {
            let cost = scalar.value < 32 ? 6 : [34, 47, 92].contains(scalar.value) ? 2 : scalar.utf8.count
            if bytes + cost > 22_300 { break }; value.unicodeScalars.append(scalar); bytes += cost
        }
        return value + "\nSource context truncated here."
    }
}
