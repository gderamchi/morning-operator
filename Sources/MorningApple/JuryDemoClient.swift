import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// These credentials belong to the separately installed demo, never the ordinary app.
public struct JuryDemoConfiguration: Sendable {
    public let baseURL: URL
    public let token: String

    public init(baseURL: URL, token: String) throws {
        guard Self.isAllowed(baseURL), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !token.contains("\n"), !token.contains("\r") else { throw JuryDemoError.configuration }
        self.baseURL = baseURL; self.token = token
    }

    public static func fromBundle(_ bundle: Bundle = .main) throws -> Self {
        guard let value = bundle.object(forInfoDictionaryKey: "MorningJuryDemoBaseURL") as? String,
              let url = URL(string: value),
              let token = bundle.object(forInfoDictionaryKey: "MorningJuryDemoToken") as? String else {
            throw JuryDemoError.configuration
        }
        return try .init(baseURL: url, token: token)
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        if url.scheme == "https" { return true }
        guard url.scheme == "http" else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "[::1]" || host == "::1" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && (16...31).contains(octets[1]))
    }
}

public enum JuryDemoError: Error, LocalizedError, Equatable {
    case configuration, invalidResponse, unauthorized, serviceUnavailable, sessionUnavailable, speechUnavailable, localVoiceUnavailable
    public var errorDescription: String? {
        switch self {
        case .configuration: "La connexion de cette version de MORE n’est pas configurée."
        case .invalidResponse: "MORE a reçu une réponse incomplète. L’action ne sera pas répétée automatiquement."
        case .unauthorized: "La connexion à MORE a expiré."
        case .serviceUnavailable: "La connexion à MORE est indisponible. L’action ne sera pas répétée automatiquement."
        case .sessionUnavailable: "Ce matin ne peut pas être repris. Vérifiez les actions déjà réalisées, puis arrêtez-le avant d’en commencer un nouveau."
        case .speechUnavailable: "La voix de MORE est momentanément indisponible."
        case .localVoiceUnavailable: "Le microphone ou la reconnaissance vocale locale est indisponible. Préparez la voix dans les réglages de MORE."
        }
    }
}

public struct JuryDemoResponse: Decodable, Sendable, Equatable {
    public struct Receipt: Decodable, Sendable, Equatable {
        public let type: String
        public let id: String
        public let status: String
    }
    public struct Action: Decodable, Sendable, Equatable {
        public let type: String
        public let url: String?
        public let requestID: String?
        public let title: String?
        public let minutesBefore: Int?
        public let meetingHour: Int?
        public let meetingMinute: Int?
    }
    public let sessionID: String
    public let stage: String
    public let text: String
    public let completed: Bool
    public let receipt: Receipt?
    public let action: Action?

    func validated() throws -> Self {
        guard !sessionID.isEmpty, sessionID.count <= 128,
              sessionID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-" )).contains($0) }),
              ["morning", "mail", "draft", "social", "complete", "stopped"].contains(stage),
              !text.isEmpty, text.count <= 8_000,
              completed == (stage == "complete" || stage == "stopped") else { throw JuryDemoError.invalidResponse }
        if let action {
            guard !completed else { throw JuryDemoError.invalidResponse }
            switch action.type {
            case "openURL":
                guard let value = action.url, let url = URL(string: value), url.scheme == "https",
                      url.host != nil, url.user == nil, url.password == nil else { throw JuryDemoError.invalidResponse }
            case "createReminder":
                guard let requestID = action.requestID, UUID(uuidString: requestID) != nil,
                      let title = action.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 160,
                      let minutes = action.minutesBefore, (0...1_440).contains(minutes),
                      let hour = action.meetingHour, (0...23).contains(hour),
                      let minute = action.meetingMinute, (0...59).contains(minute) else { throw JuryDemoError.invalidResponse }
            default: throw JuryDemoError.invalidResponse
            }
        }
        return self
    }
}

public struct JuryDemoClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let configuration: JuryDemoConfiguration
    private let transport: Transport
    private static let session = URLSession(configuration: .ephemeral, delegate: JuryDemoNoRedirects(), delegateQueue: nil)

    public init(configuration: JuryDemoConfiguration) {
        self.init(configuration: configuration, transport: { request in
            let (data, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw JuryDemoError.invalidResponse }
            return (data, response)
        })
    }

    init(configuration: JuryDemoConfiguration, transport: @escaping Transport) {
        self.configuration = configuration; self.transport = transport
    }

    public func start() async throws -> JuryDemoResponse {
        try await response(path: "v1/jury/session", body: [:])
    }

    /// Read-only reconciliation must precede any continuation after a relaunch.
    public func resume(sessionID: String) async throws -> JuryDemoResponse {
        let (data, _) = try await request(path: "v1/jury/session/\(sessionID)", method: "GET", body: nil)
        let value = try decodeResponse(data)
        guard value.sessionID == sessionID else { throw JuryDemoError.invalidResponse }
        return value
    }

    public func turn(sessionID: String, requestID: UUID, text: String) async throws -> JuryDemoResponse {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4_000 else {
            throw JuryDemoError.invalidResponse
        }
        let value = try await response(path: "v1/jury/turn", body: [
            "sessionID": sessionID, "requestID": requestID.uuidString, "text": text
        ])
        guard value.sessionID == sessionID else { throw JuryDemoError.invalidResponse }
        return value
    }

    public func speech(text: String) async throws -> Data {
        let (data, response) = try await request(path: "v1/jury/speech", body: ["text": text])
        guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("audio/") == true,
              !data.isEmpty, data.count <= 8 * 1_024 * 1_024 else { throw JuryDemoError.speechUnavailable }
        return data
    }

    public func actionResult(sessionID: String, requestID: String, status: String, receiptID: String? = nil) async throws -> JuryDemoResponse {
        guard UUID(uuidString: requestID) != nil, ["confirmed", "unavailable", "uncertain"].contains(status),
              status != "confirmed" || receiptID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw JuryDemoError.invalidResponse
        }
        var body = ["sessionID": sessionID, "requestID": requestID, "status": status]
        if let receiptID { body["receiptID"] = receiptID }
        let value = try await response(path: "v1/jury/action-result", body: body)
        guard value.sessionID == sessionID else { throw JuryDemoError.invalidResponse }
        return value
    }

    public func stop(sessionID: String) async throws {
        _ = try await request(path: "v1/jury/session/\(sessionID)", method: "DELETE", body: nil)
    }

    private func response(path: String, body: [String: String]) async throws -> JuryDemoResponse {
        let (data, _) = try await request(path: path, body: body)
        return try decodeResponse(data)
    }

    private func decodeResponse(_ data: Data) throws -> JuryDemoResponse {
        guard data.count <= 64 * 1_024 else { throw JuryDemoError.invalidResponse }
        do { return try JSONDecoder().decode(JuryDemoResponse.self, from: data).validated() }
        catch let error as JuryDemoError { throw error }
        catch { throw JuryDemoError.invalidResponse }
    }

    private func request(path: String, method: String = "POST", body: [String: String]?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 { throw JuryDemoError.unauthorized }
            if method == "GET", response.statusCode == 404 { throw JuryDemoError.sessionUnavailable }
            throw JuryDemoError.serviceUnavailable
        }
        return (data, response)
    }
}

/// A configured LAN endpoint cannot redirect credentials or conversation text to
/// a different service. Redirects surface as errors instead of being followed.
private final class JuryDemoNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
