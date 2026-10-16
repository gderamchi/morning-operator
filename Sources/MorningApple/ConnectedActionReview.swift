import Foundation
import MorningCore

public enum ConnectedActionReviewError: LocalizedError, Sendable, Equatable {
    case unreadable, tooLarge
    public var errorDescription: String? {
        switch self {
        case .unreadable:
            AppLanguage.isFrench ? "Les détails de cette action ne peuvent pas être présentés entièrement. Préparez-la à nouveau avant de la confier à MORE." : "This action's details cannot be shown in full. Prepare it again before entrusting it to MORE."
        case .tooLarge:
            AppLanguage.isFrench ? "Cette action contient trop de détails pour une vérification complète dans la routine. Choisissez une action plus courte ; rien n’a été ajouté." : "This action contains too much detail for a complete routine review. Choose a shorter action; nothing was added."
        }
    }
}

/// The same lossless human review is used before execution and in the saved
/// routine. Over-limit/unreadable input is refused rather than silently shortened.
public enum ConnectedActionReview {
    public static let maximumSummaryCharacters = 32_000

    public static func summary(argumentsJSON: String, schema: ComposioJSONValue? = nil,
                               account: String? = nil, french: Bool = AppLanguage.isFrench) throws -> String {
        let arguments: [String: ComposioJSONValue]
        do { arguments = try ComposioJSONValue.parseObject(argumentsJSON) }
        catch { throw ConnectedActionReviewError.unreadable }
        var parts: [String] = []
        if let account, !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append((french ? "Compte : " : "Account: ") + (try checked(account)))
        }
        if arguments.isEmpty {
            parts.append(french ? "Aucun détail supplémentaire à transmettre." : "No extra details to send.")
        } else {
            parts.append(try valueText(.object(arguments), schema: schema, french: french))
        }
        return try bounded(parts.joined(separator: "\n\n"))
    }

    public static func valueText(_ value: ComposioJSONValue, schema: ComposioJSONValue? = nil,
                                 french: Bool = AppLanguage.isFrench) throws -> String {
        try render(value, schema: schema, french: french, depth: 0)
    }

    public static func label(for key: String, definition: ComposioJSONValue? = nil) -> String {
        if let title = definition?.objectValue?["title"]?.stringValue,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !title.contains(where: { $0.isNewline }), !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return title
        }
        let spaced = key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.capitalized
    }

    private static func render(_ value: ComposioJSONValue, schema: ComposioJSONValue?, french: Bool, depth: Int) throws -> String {
        guard depth <= 12 else { throw ConnectedActionReviewError.tooLarge }
        let text: String
        switch value {
        case .string(let string): text = string.isEmpty ? (french ? "Texte vide" : "Empty text") : try checked(string)
        case .number(let number): text = NSDecimalNumber(decimal: number).stringValue
        case .bool(let flag): text = french ? (flag ? "Oui" : "Non") : (flag ? "Yes" : "No")
        case .null: text = french ? "Aucune valeur" : "No value"
        case .array(let values):
            if values.isEmpty { text = french ? "Aucun élément" : "No items" }
            else {
                let itemSchema = schema?.objectValue?["items"]
                text = try values.enumerated().map { index, child in
                    "\(index + 1). " + (try render(child, schema: itemSchema, french: french, depth: depth + 1))
                        .replacingOccurrences(of: "\n", with: "\n   ")
                }.joined(separator: "\n")
            }
        case .object(let values):
            if values.isEmpty { text = french ? "Aucun détail" : "No details" }
            else {
                let properties = schema?.objectValue?["properties"]?.objectValue ?? [:]
                text = try values.keys.sorted().map { key in
                    let childSchema = properties[key]
                    let title = try checked(label(for: key, definition: childSchema))
                    guard !title.isEmpty else { throw ConnectedActionReviewError.unreadable }
                    let rendered = try render(values[key]!, schema: childSchema, french: french, depth: depth + 1)
                    return title + (french ? " : " : ": ") + rendered.replacingOccurrences(of: "\n", with: "\n  ")
                }.joined(separator: "\n")
            }
        }
        return try bounded(text)
    }

    private static func checked(_ text: String) throws -> String {
        guard !text.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
        }) else { throw ConnectedActionReviewError.unreadable }
        return try bounded(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
    }

    private static func bounded(_ value: String) throws -> String {
        guard value.count <= maximumSummaryCharacters else { throw ConnectedActionReviewError.tooLarge }
        return value
    }
}
