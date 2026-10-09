import Foundation

public enum PersistenceError: Error, LocalizedError, Sendable, Equatable {
    case fileURLRequired
    case unsupportedSchema(Int)
    public var errorDescription: String? {
        switch self {
        case .fileURLRequired: "Choose a local file for this workspace."
        case .unsupportedSchema(let version): "This file uses an unsupported schema version (\(version))."
        }
    }
}

private struct JSONEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let value: Value
}

/// Small local documents, atomically replaced after complete encoding.
/// Use one authoritative writer; this does not coordinate multiple processes.
/// Store secrets in Keychain, never in these exported documents.
public struct AtomicJSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> Value {
        guard url.isFileURL else { throw PersistenceError.fileURLRequired }
        let data = try Data(contentsOf: url)
        // Read the schema independently so a future envelope is rejected before decoding its payload.
        let header = try JSONDecoder().decode(SchemaHeader.self, from: data)
        guard header.schemaVersion == 1 else { throw PersistenceError.unsupportedSchema(header.schemaVersion) }
        return try JSONDecoder().decode(JSONEnvelope<Value>.self, from: data).value
    }

    public func save(_ value: Value) throws {
        guard url.isFileURL else { throw PersistenceError.fileURLRequired }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(JSONEnvelope(schemaVersion: 1, value: value))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private struct SchemaHeader: Decodable { let schemaVersion: Int }

public actor RoutineRepository {
    private let file: AtomicJSONFile<RoutineVersion>
    public init(fileURL: URL) { file = AtomicJSONFile(url: fileURL) }
    public func load() throws -> RoutineVersion { try file.load() }
    public func save(_ routine: RoutineVersion) throws { try file.save(routine) }
    public func export(_ routine: RoutineVersion, to fileURL: URL) throws {
        try AtomicJSONFile<RoutineVersion>(url: fileURL).save(routine)
    }
}
