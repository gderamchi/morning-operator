import Foundation

/// The loopback channel between the UI-test runner (the hands) and MORE in its DEBUG
/// live-demo mode (the voice and the ears). One JSON object per line. JSON escapes any
/// newline inside a string, so a sentence can never break the framing.
///
/// Text travels only in memory over 127.0.0.1. Neither side logs or stores it.
public enum LiveDemoWire {
    public static let tokenLength = 32
    /// A line longer than this is refused and the connection closed.
    public static let maxLineBytes = 16_384
    public static let tokenEnvironmentKey = "MO_LIVE_DEMO_TOKEN"
    public static let portEnvironmentKey = "MO_LIVE_DEMO_PORT"
    public static let launchArgument = "--live-demo-voice"
    public static let portRange: ClosedRange<UInt16> = 49_152...65_535

    public enum Command: String, Codable, Sendable {
        /// Prepare audio and listening while MORE is in front, play the sound check, report.
        case hello
        case say
        case listen
        /// Stop audio and close the listener.
        case stop
    }

    public struct Request: Codable, Equatable, Sendable {
        public let token: String
        public let id: Int
        public let command: Command
        public let text: String?
        public let seconds: Double?

        public init(token: String, id: Int, command: Command, text: String? = nil, seconds: Double? = nil) {
            self.token = token; self.id = id; self.command = command; self.text = text; self.seconds = seconds
        }
    }

    public struct Response: Codable, Equatable, Sendable {
        public let id: Int
        public let ok: Bool
        /// A LiveDemoFailure or LiveDemoSkip raw value when something did not work.
        public let code: String?
        /// Only for `listen`. Never logged by either side.
        public let transcript: String?
        /// Short technical tokens (route, volume, voice quality), never content.
        public let detail: [String]?

        public init(id: Int, ok: Bool, code: String? = nil, transcript: String? = nil, detail: [String]? = nil) {
            self.id = id; self.ok = ok; self.code = code; self.transcript = transcript; self.detail = detail
        }
    }

    public enum FramingError: Error, Equatable { case lineTooLong }

    public static func encode<Value: Encodable>(_ value: Value) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    /// Removes and returns every complete line from `buffer`. Throws when the pending,
    /// incomplete part is already longer than `maxLineBytes`.
    public static func takeLines(from buffer: inout Data) throws -> [Data] {
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            guard line.count <= maxLineBytes else { throw FramingError.lineTooLong }
            lines.append(Data(line))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        guard buffer.count <= maxLineBytes else { throw FramingError.lineTooLong }
        return lines
    }

    public static func decodeRequest(_ line: Data) -> Request? { try? JSONDecoder().decode(Request.self, from: line) }
    public static func decodeResponse(_ line: Data) -> Response? { try? JSONDecoder().decode(Response.self, from: line) }

    /// Constant-time comparison so a wrong token reveals nothing through timing.
    public static func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count, a.count == tokenLength else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    public static func isWellFormedToken(_ token: String) -> Bool {
        token.utf8.count == tokenLength && token.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<tokenLength).map { _ in String(UInt8.random(in: 0...15, using: &generator), radix: 16) }.joined()
    }

    public static func makePort() -> UInt16 {
        var generator = SystemRandomNumberGenerator()
        return UInt16.random(in: portRange, using: &generator)
    }

    public static func port(from text: String?) -> UInt16? {
        guard let text, let value = UInt16(text), portRange.contains(value) else { return nil }
        return value
    }

    /// The listener accepts only these remote hosts.
    public static func isLoopback(host: String) -> Bool {
        let bare = host.split(separator: "%").first.map(String.init) ?? host
        return bare == "127.0.0.1" || bare == "::1" || bare == "::ffff:127.0.0.1"
    }

    /// A reply timeout for `say`: generous for long sentences, bounded.
    public static func sayTimeout(characters: Int) -> TimeInterval {
        min(120, 15 + Double(max(characters, 0)) / 8)
    }
}

/// When to stop the demo early (owner-present checks on the phone).
public enum LiveDemoStopAfter: String, Sendable {
    case summary

    public static func from(environment: [String: String]) -> LiveDemoStopAfter? {
        environment["MO_LIVE_DEMO_STOP_AFTER"].flatMap { LiveDemoStopAfter(rawValue: $0) }
    }
}
