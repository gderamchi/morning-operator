import CryptoKit
import Foundation
import MorningCore

/// Content-free durable claims. A pending claim may only be reconciled, never sent again.
/// This deliberately trades a possible missed send for protection against duplicate mail.
@MainActor
struct GmailSendJournal {
    struct Entry: Codable, Sendable, Equatable {
        enum Status: String, Codable, Sendable { case pending, sent, rejected }
        let key: String
        let messageID: String
        /// Older claims have no fingerprint and can never certify a newly prepared reply.
        let payloadFingerprint: String?
        var status: Status
    }

    private let control: LocalDataControl
    init(control: LocalDataControl) { self.control = control }

    func claim(operationID: String, account: String, payloadFingerprint: String, generation: UUID?) throws -> (Entry, isNew: Bool) {
        try access(generation: generation) { file, entries in
            let key = Self.digest(account.lowercased() + "\n" + operationID)
            if let entry = entries.first(where: { $0.key == key }) { return (entry, false) }
            guard entries.count < 1_000 else { throw GmailConnectionError.sendJournalUnavailable }
            let entry = Entry(key: key, messageID: "<more.\(UUID().uuidString.lowercased())@morning.local>",
                payloadFingerprint: payloadFingerprint, status: .pending)
            try file.save(entries + [entry])
            return (entry, true)
        }
    }

    func set(_ entry: Entry, status: Entry.Status, generation: UUID?) throws {
        try access(generation: generation) { file, entries in
            guard let index = entries.firstIndex(where: { $0.key == entry.key && $0.messageID == entry.messageID }) else {
                throw GmailConnectionError.sendJournalUnavailable
            }
            var updated = entries
            updated[index].status = status
            try file.save(updated)
        }
    }

    private func access<T>(generation: UUID?, body: (AtomicJSONFile<[Entry]>, [Entry]) throws -> T) throws -> T {
        do {
            return try control.withReadyAccess { state in
                guard state.generation == generation else { throw GmailConnectionError.connectionChanged }
                let url = control.directory.appendingPathComponent("gmail-send-journal.json")
                let file = AtomicJSONFile<[Entry]>(url: url, maximumBytes: 262_144)
                let entries: [Entry]
                if FileManager.default.fileExists(atPath: url.path) {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw GmailConnectionError.sendJournalUnavailable }
                    entries = try file.load()
                    guard entries.count <= 1_000, Set(entries.map(\.key)).count == entries.count,
                          entries.allSatisfy({ $0.key.count == 64 && GmailReplyAddress.messageID($0.messageID) != nil &&
                              ($0.payloadFingerprint.map { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } ?? true) }) else {
                        throw GmailConnectionError.sendJournalUnavailable
                    }
                } else { entries = [] }
                return try body(file, entries)
            }
        } catch let error as GmailConnectionError { throw error }
        catch { throw GmailConnectionError.sendJournalUnavailable }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func payloadFingerprint(message: GmailMessage, recipient: String, body: String) throws -> String {
        struct Payload: Encodable {
            let recipient: String; let messageID: String; let internetMessageID: String?
            let threadID: String?; let subject: String; let body: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(recipient: recipient, messageID: message.id,
            internetMessageID: message.internetMessageID, threadID: message.threadID, subject: message.subject, body: body))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
