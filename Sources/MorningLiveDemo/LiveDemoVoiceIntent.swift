import Foundation

/// Spoken navigation commands for the live demo, English and French. A strict grammar
/// decides first; the on-device model may only pick one of `modelTokens`, and its answer
/// is accepted only if it is exactly one of them. Nothing here can send, like, follow or
/// comment: those are not intents. A reply is only ever typed as a draft by the runner.
public enum LiveDemoVoiceIntent: Codable, Equatable, Sendable {
    case more(Int)
    case hold
    case next
    case skip
    case stop
    case goTo(Destination)
    case repeatLast
    case reply(String)

    public enum Destination: String, Codable, Sendable { case messages, mail, calendar }

    /// The only answers the on-device model may give. Never a "go to": leaving for private
    /// content needs the owner's wake word, which only the strict grammar can see.
    public static let modelTokens: [String: LiveDemoVoiceIntent] = [
        "hold": .hold, "next": .next, "skip": .skip, "stop": .stop, "repeat": .repeatLast
    ]

    public static let maximumMore = 50

    /// Strict grammar. `requireWakeWord` means the phrase must start with "MORE" (used if
    /// echo cancellation is not enough). Unknown phrases return nil.
    public static func parse(_ transcript: String, requireWakeWord: Bool = false) -> LiveDemoVoiceIntent? {
        var words = LiveDemoReplyIntent.normalizedWords(transcript)
        let hadWake = words.first == "more" && words.count > 1 && !isMoreCount(words)
        if hadWake { words.removeFirst() }
        if requireWakeWord && !hadWake { return nil }
        if words.first == "hey" || words.first == "ok" || words.first == "please" { words.removeFirst() }
        if words.last == "please" { words.removeLast() }
        guard !words.isEmpty else { return nil }
        let phrase = words.joined(separator: " ")

        // Replies: the words after the verb, in the original wording.
        let replyPrefixes = ["reply", "reply with", "reply saying", "answer", "reponds", "repondre", "reponds lui"]
        for prefix in replyPrefixes.sorted(by: { $0.count > $1.count }) {
            let prefixWords = prefix.split(separator: " ").map(String.init)
            if words.count > prefixWords.count, Array(words.prefix(prefixWords.count)) == prefixWords {
                let offset = prefixWords.count + (hadWake ? 1 : 0) + (wordsBeforeCommand(transcript, hadWake: hadWake))
                guard let text = LiveDemoReplyIntent.originalText(after: offset, in: transcript),
                      let draft = LiveDemoDraft.sanitize(text) else { return nil }
                return .reply(draft)
            }
        }

        // "8 more", "add eight more", "eight more reels", "huit de plus", "encore huit".
        if let count = moreCount(words) { return .more(min(count, maximumMore)) }

        switch phrase {
        case "next", "next one", "next reel", "suivant", "la suivante", "le suivant", "suivante":
            return .next
        case "skip", "skip it", "skip this", "skip this one", "passe", "passe la", "passer", "zappe":
            return .skip
        case "stop", "stop it", "stop the demo", "that's enough", "thats enough", "enough", "arrete", "stop la demo", "ca suffit":
            return .stop
        case "let me finish this one", "let me finish", "wait", "hold on", "keep this one", "wait for this one",
             "attends", "laisse moi finir", "laisse moi finir celle ci", "attends un peu":
            return .hold
        case "read it again", "repeat", "repeat that", "say it again", "again", "repete", "relis", "relis le", "redis le":
            return .repeatLast
        default:
            break
        }
        // Leaving for private content needs the wake word ("MORE, go to my messages"), so a
        // reel or a podcast saying "go to my messages" can never start it.
        let goVerbs: Set<String> = ["go", "open", "show", "va", "ouvre", "montre"]
        if hadWake, let first = words.first, goVerbs.contains(first) {
            let rest = Set(words.dropFirst())
            if !rest.isDisjoint(with: ["messages", "texts", "sms", "imessage"]) { return .goTo(.messages) }
            if !rest.isDisjoint(with: ["mail", "email", "emails", "mails", "inbox", "courrier"]) { return .goTo(.mail) }
            if !rest.isDisjoint(with: ["calendar", "agenda", "calendrier", "schedule"]) { return .goTo(.calendar) }
        }
        return nil
    }

    /// Accepts the model's answer only if, trimmed and lowercased, it is one allowed token.
    public static func fromModelAnswer(_ answer: String) -> LiveDemoVoiceIntent? {
        let token = answer.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        return modelTokens[token]
    }

    /// The model is only asked about short phrases that the grammar did not understand.
    public static func worthAskingModel(_ transcript: String) -> Bool {
        let count = LiveDemoReplyIntent.normalizedWords(transcript).count
        return count >= 1 && count <= 10
    }

    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "sept": 7, "huit": 8,
        "neuf": 9, "dix": 10, "onze": 11, "douze": 12, "quinze": 15, "vingt": 20
    ]
    // "six" is the same word in English and French.

    static func number(_ word: String) -> Int? { Int(word) ?? numberWords[word] }

    static func isMoreCount(_ words: [String]) -> Bool { moreCount(words) != nil }

    static func moreCount(_ words: [String]) -> Int? {
        var rest = words
        if rest.first == "add" || rest.first == "play" || rest.first == "give" { rest.removeFirst() }
        if rest.last == "reels" || rest.last == "videos" || rest.last == "please" { rest.removeLast() }
        // EN: "<n> more"; FR: "<n> de plus", "encore <n>", "<n> autres".
        if rest.count == 2, let n = number(rest[0]), rest[1] == "more" || rest[1] == "autres" { return n > 0 ? n : nil }
        if rest.count == 3, let n = number(rest[0]), rest[1] == "de", rest[2] == "plus" { return n > 0 ? n : nil }
        if rest.count == 2, rest[0] == "encore", let n = number(rest[1]) { return n > 0 ? n : nil }
        return nil
    }

    /// Filler words ("hey", "ok", "please") before the command, to locate the reply text.
    static func wordsBeforeCommand(_ transcript: String, hadWake: Bool) -> Int {
        let words = LiveDemoReplyIntent.normalizedWords(transcript)
        let index = hadWake ? 1 : 0
        guard words.count > index else { return 0 }
        return ["hey", "ok", "please"].contains(words[index]) ? 1 : 0
    }
}

/// How the reels loop reacts to a command. Pure, so the decision is tested.
public enum LiveDemoReelAction: Equatable, Sendable {
    case advanceNow
    case extend(by: Int)
    case holdUntilNext
    case endReels
    case leave(LiveDemoVoiceIntent.Destination)
    case ignore

    public static func decide(_ intent: LiveDemoVoiceIntent) -> LiveDemoReelAction {
        switch intent {
        case .next, .skip: .advanceNow
        case .more(let count): .extend(by: count)
        case .hold: .holdUntilNext
        case .stop: .endReels
        case .goTo(let destination): .leave(destination)
        case .repeatLast, .reply: .ignore
        }
    }

    /// The reel target after `extend`, bounded so a misheard number cannot run for long.
    public static func extendedTarget(current: Int, by count: Int) -> Int {
        min(current + count, LiveDemoVoiceIntent.maximumMore)
    }
}

/// Did a flick move to another reel? Compares the hashed texts and controls on screen
/// before and after: most of them must be new. One changed counter is not a new reel, and
/// an empty reading is never counted as an advance.
public enum LiveDemoReelChange {
    public static func advanced(before: Set<Int>, after: Set<Int>) -> Bool {
        guard !before.isEmpty, !after.isEmpty else { return false }
        let shared = Double(before.intersection(after).count)
        let union = Double(before.union(after).count)
        return shared / union < 0.6
    }
}
