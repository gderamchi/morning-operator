import Foundation

// MARK: - Honest run report

/// What happened to each step, printed at the end as `MO-DEMO ...` status lines that
/// scripts/live-demo.sh lets through. Lines hold step names, fixed reason codes and short
/// technical tokens only, never message, mail or transcript text.
public enum LiveDemoStep: String, CaseIterable, Sendable {
    case soundCheck = "sound-check"
    case listening
    case summary
    case messages
    case mail
    case weather
    case calendar
    case reels

    /// The steps that open another app. If all of them were skipped, the run fails.
    public static let appSteps: [LiveDemoStep] = [.messages, .mail, .weather, .calendar, .reels]
}

public enum LiveDemoSkip: String, Sendable, Equatable {
    case notInstalled = "not-installed"
    case notFound = "screen-not-found"
    case promptVisible = "prompt-visible"
    case ownerDeclined = "owner-declined"
    case disabled = "disabled"
    case permissionDenied = "permission-denied"
    case onDeviceUnavailable = "on-device-unavailable"
    case audioInputFailed = "audio-input-failed"
    case voiceFailed = "voice-failed"
    case notReached = "not-reached"
    case stoppedEarly = "stopped-early"
}

/// Why the run fails. Fixed codes only, so a failure message cannot carry content.
public enum LiveDemoFailure: String, Sendable, Equatable {
    case audioSessionFailed = "audio-session-failed"
    case audioEngineFailed = "audio-engine-failed"
    case voiceNoRender = "voice-no-render"
    case voiceNoPlayback = "voice-no-playback"
    case audioInterrupted = "audio-interrupted"
    case voiceFormat = "voice-format"
    case routeEarpiece = "route-earpiece"
    case routeMissing = "route-missing"
    case volumeZero = "volume-zero"
    case allAppStepsSkipped = "all-app-steps-skipped"
    case voiceChannelFailed = "voice-channel-failed"
    case moreNotReady = "more-not-ready"
}

public enum LiveDemoOutcome: Equatable, Sendable {
    case ran
    case skipped(LiveDemoSkip)
}

public struct LiveDemoReport: Sendable {
    public private(set) var outcomes: [LiveDemoStep: LiveDemoOutcome] = [:]

    public init() {}

    /// The first outcome recorded for a step wins, so a later "ran" cannot hide a skip.
    public mutating func record(_ step: LiveDemoStep, _ outcome: LiveDemoOutcome) {
        if outcomes[step] == nil { outcomes[step] = outcome }
    }

    public var allAppStepsSkipped: Bool {
        LiveDemoStep.appSteps.allSatisfy { step in
            if case .ran = outcomes[step] ?? .skipped(.notReached) { return false }
            return true
        }
    }

    /// One line per step in a fixed order; a step never recorded is "skipped not-reached".
    public func lines() -> [String] {
        LiveDemoStep.allCases.map { step in
            switch outcomes[step] ?? .skipped(.notReached) {
            case .ran: return Self.line(["step", step.rawValue, "ran"])
            case .skipped(let reason): return Self.line(["step", step.rawValue, "skipped", reason.rawValue])
            }
        }
    }

    public static func failureMessage(_ failure: LiveDemoFailure, detail: [String] = []) -> String {
        (["MO-DEMO-FAIL", failure.rawValue] + detail.map(token)).joined(separator: " ")
    }

    /// `MO-DEMO` plus tokens. Every token is reduced to `[a-z0-9=._-]`, so whatever the
    /// caller passes, the line matches the script's strict filter and holds no prose.
    public static func line(_ parts: [String]) -> String {
        (["MO-DEMO"] + parts.map(token)).joined(separator: " ")
    }

    public static func token(_ text: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789=._-")
        let mapped = String(text.lowercased().map { allowed.contains($0) ? $0 : "-" }.prefix(40))
        return mapped.isEmpty ? "-" : mapped
    }
}

// MARK: - Voice choice

public struct LiveDemoVoiceCandidate: Equatable, Sendable {
    public enum Quality: Int, Sendable, Comparable {
        case standard = 1, enhanced = 2, premium = 3
        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }
        public var name: String { self == .premium ? "premium" : self == .enhanced ? "enhanced" : "default" }
    }

    public let identifier: String
    public let language: String
    public let quality: Quality
    public let isPersonalVoice: Bool
    public let isNoveltyVoice: Bool

    public init(identifier: String, language: String, quality: Quality, isPersonalVoice: Bool, isNoveltyVoice: Bool) {
        self.identifier = identifier; self.language = language; self.quality = quality
        self.isPersonalVoice = isPersonalVoice; self.isNoveltyVoice = isNoveltyVoice
    }
}

public enum LiveDemoVoicePick {
    /// Highest quality first (premium > enhanced > default), then the exact language over
    /// another region of it, then identifier for a stable choice. Personal Voice is excluded
    /// by the owner; novelty voices are excluded too.
    public static func best(from voices: [LiveDemoVoiceCandidate], language: String = "en-US") -> LiveDemoVoiceCandidate? {
        let base = language.split(separator: "-").first.map(String.init) ?? language
        return voices
            .filter { !$0.isPersonalVoice && !$0.isNoveltyVoice }
            .filter { $0.language == language || $0.language.hasPrefix(base + "-") }
            .max { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality < rhs.quality }
                if (lhs.language == language) != (rhs.language == language) { return rhs.language == language }
                return lhs.identifier > rhs.identifier
            }
    }

    /// Say the download hint once when no enhanced or premium voice is installed.
    public static func needsPremiumHint(_ chosen: LiveDemoVoiceCandidate?) -> Bool {
        (chosen?.quality ?? .standard) == .standard
    }
}

// MARK: - Opening summary

public enum LiveDemoSummary {
    /// Short, plain sentences. Counts are what was visible on screen; nil means unknown.
    public static func sentences(unreadConversations: Int?, unreadEmails: Int?,
                                 weather: (temperature: String, condition: String?)?) -> [String] {
        var result = ["Good morning."]
        if let count = unreadConversations {
            result.append(count == 0 ? "You have no unread messages."
                : count == 1 ? "You have one unread conversation." : "You have \(count) unread conversations.")
        }
        if let count = unreadEmails {
            result.append(count == 0 ? "You have no unread emails."
                : count == 1 ? "You have one unread email." : "You have \(count) unread emails.")
        }
        if let weather {
            let degrees = spokenTemperature(weather.temperature)
            if let condition = weather.condition {
                result.append("It's \(degrees) and \(condition.lowercased()).")
            } else {
                result.append("It's \(degrees).")
            }
        }
        return result
    }

    /// "11°" -> "11 degrees", "-3°C" -> "minus 3 degrees", "1°" -> "1 degree".
    public static func spokenTemperature(_ text: String) -> String {
        let digits = text.filter { $0.isNumber }
        guard let value = Int(digits) else { return text }
        let sign = text.trimmingCharacters(in: .whitespaces).hasPrefix("-") || text.hasPrefix("\u{2212}") ? "minus " : ""
        return "\(sign)\(value) \(value == 1 ? "degree" : "degrees")"
    }
}

// MARK: - Yes or no

public enum LiveDemoYesNo: Equatable, Sendable {
    case yes, no, unclear

    public static func parse(_ transcript: String) -> LiveDemoYesNo {
        switch LiveDemoReplyIntent.parse(transcript) {
        case .affirm: return .yes
        case .decline: return .no
        case .silence, .unclear, .draft: return transcript.isEmpty ? .unclear : yesPhrase(transcript) ? .yes : .unclear
        }
    }

    static func yesPhrase(_ transcript: String) -> Bool {
        let phrase = LiveDemoReplyIntent.normalizedWords(transcript).joined(separator: " ")
        return ["lets go", "lets start", "start", "go", "yes lets start", "yes lets go", "sure lets go",
                "yes start", "absolutely", "of course"].contains(phrase)
    }
}
