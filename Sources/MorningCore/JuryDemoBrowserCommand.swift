import Foundation

/// A narrow command parser: questions, refusals and session-level Next stay with
/// the conversation. Parsing never authorizes a page action by itself.
public enum JuryDemoBrowserCommand: Equatable, Sendable {
    case nextVideo, previousVideo, close

    public static func parse(_ text: String) -> Self? {
        guard text.count <= 256 else { return nil }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        var words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
        for prefix in ["s il te plait ", "please "] where words.hasPrefix(prefix) { words.removeFirst(prefix.count) }
        for suffix in [" s il te plait", " please", " stp"] where words.hasSuffix(suffix) { words.removeLast(suffix.count) }
        switch words {
        case "video suivante", "la suivante", "passe a la suivante", "passe a la video suivante",
             "scroll", "scroll un peu", "descends", "descends un peu", "fais defiler",
             "next video", "the next one", "scroll down", "go down":
            return .nextVideo
        case "reviens avant", "reviens a celle d avant", "video precedente", "la precedente",
             "previous video", "go back to the previous video":
            return .previousVideo
        case "ferme", "ferme la page", "ferme le navigateur", "retour a mon matin",
             "reviens a mon matin", "retour au matin", "close the browser", "back to my morning":
            return .close
        default:
            return nil
        }
    }
}
