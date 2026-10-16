import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Synthetic byte-level attacks. Expected slices are authored independently of
/// RawJSONText; never use the scanner under test to prepare its own oracle.
@Suite("Raw JSON text attacks")
struct RawJSONTextAttackTests {
    private struct Key: CodingKey, Sendable {
        let stringValue: String
        let intValue: Int?
        init(_ name: String) { stringValue = name; intValue = nil }
        init(_ index: Int) { stringValue = "Index \(index)"; intValue = index }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { self.init(intValue) }
    }

    private struct NeverReadable: Decodable, Sendable {
        init(from decoder: any Decoder) throws {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Synthetic damaged element"))
        }
    }

    private struct Probe: Decodable {
        let captures: [RecoverableElement<NeverReadable>]
    }

    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/workspace-1952d9f.json")
    private static let whitespace = " \t\r\n"
    private static let captureMarker = "RAW_ATTACK_CAPTURE_SENTINEL"
    private static let runMarker = "RAW_ATTACK_RUN_SENTINEL"

    private func find(_ source: String, _ path: [Key]) -> String? {
        RawJSONText.find(in: Data(source.utf8), at: path)
    }

    /// Swift String equality allows canonical equivalence. Compare UTF-8 bytes,
    /// so normalization, escape rewriting and whitespace changes cannot pass.
    private func exact(_ actual: String?, _ expected: String,
                       sourceLocation: SourceLocation = #_sourceLocation) throws {
        let actual = try #require(actual, sourceLocation: sourceLocation)
        #expect(Array(actual.utf8) == Array(expected.utf8), sourceLocation: sourceLocation)
    }

    private func validateJSON(_ source: String) throws {
        _ = try JSONSerialization.jsonObject(with: Data(source.utf8), options: .fragmentsAllowed)
    }

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func fixtureValue() throws -> [String: Any] {
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixture)) as? [String: Any])
        return try #require(root["value"] as? [String: Any])
    }

    private func json(_ value: Any, pretty: Bool = false) throws -> String {
        let options: JSONSerialization.WritingOptions = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: options), as: UTF8.self)
    }

    private func replaceMarker(_ marker: String, with raw: String, in source: String) throws -> String {
        let quoted = try encoded(marker)
        #expect(source.components(separatedBy: quoted).count == 2, "Sentinel must occur exactly once")
        return source.replacingOccurrences(of: quoted, with: raw)
    }

    private func workspace(_ value: [String: Any], pretty: Bool = false,
                           replacements: [(String, String)] = []) throws -> String {
        var source = try json(["schemaVersion": 1, "value": value], pretty: pretty)
        for (marker, raw) in replacements { source = try replaceMarker(marker, with: raw, in: source) }
        return source
    }

    private func withFile<T>(_ source: String, _ body: (AtomicJSONFile<WorkspaceSnapshot>) throws -> T) throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("raw-json-attack-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = AtomicJSONFile<WorkspaceSnapshot>(url: folder.appendingPathComponent("workspace.json"))
        try Data(source.utf8).write(to: file.url)
        return try body(file)
    }

    private func rawEntries(_ saved: WorkspaceSnapshot, part: String) throws -> [String] {
        (saved.setAside ?? []).compactMap { entry in
            guard case .object(let fields) = entry else {
                Issue.record("A set-aside entry is not an object"); return nil
            }
            guard fields["part"] == .string(part) else { return nil }
            guard case .string(let raw)? = fields["raw"] else {
                Issue.record("A set-aside entry has no text"); return nil
            }
            return raw
        }
    }

    private func assertRestOfWorkspace(_ saved: WorkspaceSnapshot, matches clean: WorkspaceSnapshot) {
        #expect(saved.routine == clean.routine)
        #expect(saved.receipts == clean.receipts)
        #expect(saved.pendingCaptures == clean.pendingCaptures)
        #expect(saved.observationArchive == clean.observationArchive)
        #expect(saved.selectedObservationID == clean.selectedObservationID)
        #expect(saved.consumedMorningEntryIDs == clean.consumedMorningEntryIDs)
        #expect(saved.automatic == clean.automatic && saved.readAloud == clean.readAloud)
        #expect(saved.sessionTimeZone == clean.sessionTimeZone)
        #expect(saved.routinePreferences?.value == clean.routinePreferences?.value)
        #expect(saved.pendingRoutineProposal?.value == clean.pendingRoutineProposal?.value)
    }

    @Test("Backslash parity before escaped and closing quotes never moves a boundary")
    func quoteAndBackslashParity() throws {
        for count in 0...12 {
            let slashes = String(repeating: "\\", count: count * 2)
            let closing = "\"ends" + slashes + "\""
            let embedded = "\"before" + slashes + "\\\"[,]{}after\""
            for target in [closing, embedded] {
                let source = "{\"captures\":[" + target + "," + target + ",17]}"
                try validateJSON(source)
                try exact(find(source, [Key("captures"), Key(0)]), target)
                try exact(find(source, [Key("captures"), Key(1)]), target)
                try exact(find(source, [Key("captures"), Key(2)]), "17")
            }
        }
    }

    @Test("Brackets, commas, escaped quotes and backslashes in keys and string values")
    func delimitersInsideStringsAndKeys() throws {
        let target = #"{"s":"[,]}{,\"quoted\"\\","nested":["\\",{"x":"\""}]}"#
        let key = "ca\"pt\\ures[,]{}"
        let source = "{\"decoy\":\"]},,\\\"[\"," + (try encoded(key)) + ":[" + target + ",false]}"
        try validateJSON(source)
        try exact(find(source, [Key(key), Key(0)]), target)
        try exact(find(source, [Key(key), Key(1)]), "false")
    }

    @Test("Unicode escapes in path keys match decoded names without matching prefixes")
    func escapedAndPrefixKeys() throws {
        let source = #"{"capture":1,"capturesExtra":2,"captur":3,"\u0063apt\u0075res":[{"\u0072aw":"target"}],"capturesSuffix":4}"#
        try validateJSON(source)
        try exact(find(source, [Key("captures"), Key(0), Key("raw")]), #""target""#)
        for (key, expected) in [("capture", "1"), ("capturesExtra", "2"), ("captur", "3"), ("capturesSuffix", "4")] {
            try exact(find(source, [Key(key)]), expected)
        }
        #expect(find(source, [Key("cap")]) == nil)
        let unicode = #"{"\uD83D\uDE80":{"caf\u00e9":true},"caféMore":false}"#
        try exact(find(unicode, [Key("🚀"), Key("café")]), "true")
    }

    @Test("All four JSON whitespace bytes at every token boundary, compact and pretty")
    func everyWhitespaceKind() throws {
        for space in ["", " ", "\t", "\n", "\r", "\r\n", Self.whitespace] {
            let target = "{" + space + "\"x\"" + space + ":" + space + "[" + space
                + "1" + space + "," + space + "true" + space + "," + space + "null" + space + "]" + space + "}"
            let source = space + "{" + space + "\"captures\"" + space + ":" + space + "[" + space
                + "false" + space + "," + space + target + space + "," + space + "0" + space + "]" + space + "}" + space
            try validateJSON(source)
            try exact(find(source, [Key("captures"), Key(1)]), target)
            try exact(find(source, [Key("captures"), Key(1), Key("x"), Key(2)]), "null")
            try exact(find(source, [Key("captures"), Key(2)]), "0")
        }
    }

    @Test("Numbers, booleans and null end exactly at commas, braces, brackets or EOF")
    func scalarBoundaries() throws {
        let scalars = ["0", "-0", "12", "-12.30", "1e+20", "-9.5E-7", "18446744073709551617",
                       "0.100000000000000000000001", "true", "false", "null"]
        for scalar in scalars {
            for source in ["[" + scalar + "]", "[false," + scalar + "]", "[{}," + scalar + ",null]"] {
                try validateJSON(source)
                let index = source.hasPrefix("[false,") || source.hasPrefix("[{},") ? 1 : 0
                try exact(find(source, [Key(index)]), scalar)
            }
            try exact(find("{\"x\":" + scalar + "}", [Key("x")]), scalar)
            try exact(find(Self.whitespace + scalar + Self.whitespace, []), scalar)
        }
    }

    @Test("Deep nesting can be skipped, retained whole, and traversed by a long path")
    func deepNesting() throws {
        var target = #"{"leaf":"東京 🚀 [,] \\"}"#
        var path: [Key] = []
        for level in 0..<128 {
            if level.isMultiple(of: 2) { target = "[null," + target + "]"; path.insert(Key(1), at: 0) }
            else { target = "{\"n\":" + target + ",\"tail\":false}"; path.insert(Key("n"), at: 0) }
        }
        let source = "{\"before\":" + target + ",\"captures\":[" + target + ",true],\"after\":" + target + "}"
        try validateJSON(source)
        try exact(find(source, [Key("captures"), Key(0)]), target)
        try exact(find(source, [Key("captures"), Key(0)] + path + [Key("leaf")]), #""東京 🚀 [,] \\""#)
        try exact(find(source, [Key("captures"), Key(1)]), "true")
    }

    @Test("UTF-8, combining marks, non-BMP characters and literal versus escaped text stay byte exact")
    func multibyteUTF8() throws {
        let target = "{\"é\":\"e\u{301} / café / 東京 / 👩🏽‍💻 / 🚀\",\"escape\":\"\\u00e9\\uD83D\\uDE80\"}"
        let source = "{\"前🚀\":false,\"captures\":[\"é\"," + target + ",\"後\"]}"
        try validateJSON(source)
        try exact(find(source, [Key("captures"), Key(1)]), target)
        try exact(find(source, [Key("captures"), Key(2)]), "\"後\"")
    }

    @Test("Empty collections have exact spans and no element zero")
    func emptyContainers() throws {
        for target in ["[]", "{}", "[ \t\r\n]", "{ \t\r\n}"] {
            let source = "{\"captures\":[" + target + ",42]}"
            try exact(find(source, [Key("captures"), Key(0)]), target)
            #expect(find(source, [Key("captures"), Key(0), Key(0)]) == nil)
            #expect(find(source, [Key("captures"), Key(0), Key("missing")]) == nil)
            try exact(find(source, [Key("captures"), Key(1)]), "42")
        }
    }

    @Test("Missing, past-the-end, enormous and wrong-container paths return nil")
    func invalidIndicesAndPaths() {
        for index in [1, 2, 10, Int.max] {
            #expect(find("[0]", [Key(index)]) == nil)
            #expect(find("[]", [Key(index)]) == nil)
        }
        #expect(find("[]", [Key(0)]) == nil)
        #expect(find("{}", [Key("missing")]) == nil)
        #expect(find("[1]", [Key("0")]) == nil)
        #expect(find("{\"0\":1}", [Key(0)]) == nil)
        #expect(find("[true]", [Key(0), Key(0)]) == nil)
        #expect(find("{\"x\":null}", [Key("x"), Key("y")]) == nil)
        #expect(find("", []) == nil)
        #expect(find(Self.whitespace, []) == nil)
    }

    @Test("A negative array index is refused without trapping the caller")
    func negativeIndexDoesNotCrash() async {
        // Run in Swift Testing's child process: a scanner trap must fail this test,
        // not prevent all the other attacks from reporting their outcomes.
        await #expect(processExitsWith: .success) {
            let result = RawJSONText.find(in: Data("[1]".utf8), at: [Key(-1)])
            #expect(result == nil)
        }
    }

    @Test("Duplicate requested keys at each path depth, including escaped spellings, are ambiguous")
    func duplicateKeysAlongPath() {
        let documents = [
            #"{"value":{"captures":[11]},"value":{"captures":[22]}}"#,
            #"{"value":{"captures":[11]},"\u0076alue":{"captures":[22]}}"#,
            #"{"value":{"captures":[11],"captures":[22]}}"#,
            #"{"value":{"captures":[11],"\u0063aptures":[22]}}"#,
            #"{"value":{"captures":[{"leaf":11,"leaf":22}]}}"#,
            #"{"value":{"captures":[{"leaf":11,"\u006ceaf":22}]}}"#,
            #"{"value":{"captures":[{"leaf":11}]},"value":{"captures":[{"leaf":11}]}}"#
        ]
        for (index, source) in documents.enumerated() {
            let path = [Key("value"), Key("captures"), Key(0)] + (index >= 4 ? [Key("leaf")] : [])
            #expect(find(source, path) == nil, "Ambiguous path in \(source)")
        }
    }

    @Test("Duplicates outside the path and within a retained whole object do not change its bytes")
    func duplicatesOutsideSelectedPath() throws {
        let target = #"{"text":1,"text":2,"\u0074ext":3}"#
        let source = "{\"other\":1,\"other\":2,\"captures\":[" + target + ",9],\"tail\":{\"x\":0,\"x\":1}}"
        try exact(find(source, [Key("captures"), Key(0)]), target)
        try exact(find(source, [Key("captures"), Key(1)]), "9")
    }

    @Test("RecoverableElement retains every kind of damaged element from decoder-supplied bytes")
    func recoverableElementMatrix() throws {
        let targets = [#""a\"[,]}\\""#, "true", "false", "null", "-1.25e-12", "[]", "{}",
                       "{ \t\r\n\"x\" : [1, 2] }", #"{"é":"e\u0301 🚀"}"#]
        let source = "{\"\\u0063aptures\" : [" + targets.joined(separator: ", \r\n\t") + "]}"
        try validateJSON(source)
        let data = Data(source.utf8)
        let decoder = JSONDecoder()
        decoder.userInfo[.atomicJSONFileData] = data
        let probe = try decoder.decode(Probe.self, from: data)
        #expect(probe.captures.count == targets.count)
        for (recovered, target) in zip(probe.captures, targets) {
            #expect(recovered.value == nil)
            try exact(recovered.raw, target)
        }
    }

    @Test("RecoverableElement refuses failures without the original bytes")
    func missingSourceBytesRefuses() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Probe.self, from: Data(#"{"captures":[{}]}"#.utf8))
        }
    }

    @Test("A BOM at root yields either the complete JSON value or a safe refusal")
    func bomRootCannotReturnTruncatedText() throws {
        let target = "[1,2]"
        let source = "\u{FEFF}" + target
        // Foundation accepts these bytes. The BOM is not part of the JSON value.
        #expect(try JSONDecoder().decode([Int].self, from: Data(source.utf8)) == [1, 2])
        if let raw = find(source, []) { try exact(raw, target) }
    }

    @Test("A root RecoverableElement must not preserve a partial BOM-prefixed document")
    func bomRootRecoveryNeverKeepsWrongText() throws {
        let target = "[1,2]"
        let data = Data(("\u{FEFF}" + target).utf8)
        let decoder = JSONDecoder()
        decoder.userInfo[.atomicJSONFileData] = data
        let result: RecoverableElement<NeverReadable>
        do { result = try decoder.decode(RecoverableElement<NeverReadable>.self, from: data) }
        catch { return } // Refusal is permitted; silently keeping the wrong bytes is not.
        try exact(result.raw, target)
    }

    @Test("Fixture captures: exact damaged text, healthy siblings, and two later saves", arguments: [false, true])
    func workspaceCaptures(pretty: Bool) throws {
        let clean = try AtomicJSONFile<WorkspaceSnapshot>(url: Self.fixture).load()
        let good = try QuickCapture(kind: .thought, text: "Invented healthy capture 🚀",
                                    createdAt: Date(timeIntervalSinceReferenceDate: 781_000_000),
                                    timeZoneIdentifier: "Europe/Paris")
        let targets = [
            #"{"kind":"impossible", "text":"end\\", "quoted":"\"[,]{}", "n":1.0000000000000001}"#,
            "{\r\n\t\"kind\" : false,\r\n \"text\" : \"é e\u{301} 東京 🚀\", \"nested\" : [ {}, [true,null,3] ]\r\n}",
            "true", "false", "null", "42", "[]", "{}",
            String(repeating: "[", count: 160) + #""deep \\""# + String(repeating: "]", count: 160)
        ]
        let healthy = try encoded(good)
        let array = "[" + healthy + ",\r\n\t" + targets.joined(separator: ", \t\r\n") + "," + healthy + "]"
        var value = try fixtureValue()
        value["captures"] = Self.captureMarker
        var source = try workspace(value, pretty: pretty, replacements: [(Self.captureMarker, array)])
        source = source.replacingOccurrences(of: "\"captures\"", with: #""\u0063apt\u0075res""#)
        try validateJSON(source)
        try withFile(source) { file in
            let saved = try file.load()
            #expect(saved.captures == [good, good])
            #expect(saved.newlySetAside == Array(repeating: .capture, count: targets.count))
            let raws = try rawEntries(saved, part: "capture")
            #expect(raws.count == targets.count)
            for (raw, target) in zip(raws, targets) {
                #expect(source.range(of: target) != nil)
                try exact(raw, target)
            }
            assertRestOfWorkspace(saved, matches: clean)
            #expect(saved.history == clean.history && saved.session == clean.session)
            #expect(saved.previousRoutine == clean.previousRoutine)
            for _ in 0..<2 {
                try file.save(saved)
                let again = try file.load()
                #expect(again.newlySetAside.isEmpty)
                let reloaded = try rawEntries(again, part: "capture")
                #expect(reloaded.count == targets.count)
                for (raw, target) in zip(reloaded, targets) { try exact(raw, target) }
            }
        }
    }

    @Test("Fixture history: an unreadable middle run keeps its full original substring", arguments: [false, true])
    func workspaceRuns(pretty: Bool) throws {
        let clean = try AtomicJSONFile<WorkspaceSnapshot>(url: Self.fixture).load()
        var value = try fixtureValue()
        var history = try #require(value["history"] as? [String: Any])
        let runs = try #require(history["runs"] as? [[String: Any]])
        try #require(runs.count == 3)
        var damaged = runs[1]
        damaged["timeZoneIdentifier"] = ["invalid": "Invented [,] \\\" 東京 🚀"]
        var target = try json(damaged, pretty: pretty)
        target = target.replacingOccurrences(of: "\"timeZoneIdentifier\"", with: #""timeZone\u0049dentifier""#)
        let replacement: [Any] = [runs[0], Self.runMarker, runs[2]]
        history["runs"] = replacement
        value["history"] = history
        var source = try workspace(value, pretty: pretty, replacements: [(Self.runMarker, target)])
        source = source.replacingOccurrences(of: "\"history\"", with: #""\u0068istory""#)
            .replacingOccurrences(of: "\"runs\"", with: #""r\u0075ns""#)
        try validateJSON(source)
        try withFile(source) { file in
            let saved = try file.load()
            #expect(saved.newlySetAside == [.historyRun])
            let raws = try rawEntries(saved, part: "historyRun")
            #expect(raws.count == 1)
            try exact(raws.first, target)
            #expect(source.range(of: target) != nil)
            let cleanRuns = try #require(clean.history?.runs)
            #expect(saved.history?.runs == [cleanRuns[0], cleanRuns[2]])
            #expect(saved.history?.appObservations == clean.history?.appObservations)
            #expect(saved.session == clean.session && saved.previousRoutine == clean.previousRoutine)
            #expect(saved.captures == clean.captures)
            assertRestOfWorkspace(saved, matches: clean)
        }
    }

    @Test("Session, previous routine, app day and foreign earlier set-aside items retain exact text")
    func workspaceOtherRecoveryPaths() throws {
        let clean = try AtomicJSONFile<WorkspaceSnapshot>(url: Self.fixture).load()
        var value = try fixtureValue()
        var history = try #require(value["history"] as? [String: Any])
        let goodDay = try DailyAppObservation(date: Date(timeIntervalSinceReferenceDate: 781_000_000),
            timeZoneIdentifier: "Europe/Paris", appName: "Synthetic app", provenance: .syntheticDemo,
            evidenceReferences: ["Invented fixture evidence"], updatedAt: Date(timeIntervalSinceReferenceDate: 781_000_000))
        let session = #"{"status":"broken", "s":"quotes\" and \\"}"#
        let previous = "[ \t\r\nfalse, {\"🚀\":123} ]"
        let day = #"{"date":false,"text":"[],{}","n":-1.234567890123456789e-25}"#
        let foreign = ["false", "null", "42", "{ \r\n\"x\" : [true, 2] }"]
        value["session"] = "RAW_ATTACK_SESSION"
        value["previousRoutine"] = "RAW_ATTACK_PREVIOUS"
        history["appObservations"] = "RAW_ATTACK_DAYS"
        value["history"] = history
        value["setAside"] = "RAW_ATTACK_EARLIER"
        let priorRaw = #"{"original":"é \\"}"#
        let own = "{\"part\":\"capture\",\"raw\":" + (try encoded(priorRaw)) + "}"
        let source = try workspace(value, pretty: true, replacements: [
            ("RAW_ATTACK_SESSION", session), ("RAW_ATTACK_PREVIOUS", previous),
            ("RAW_ATTACK_DAYS", "[" + (try encoded(goodDay)) + "," + day + "]"),
            ("RAW_ATTACK_EARLIER", "[" + own + "," + foreign.joined(separator: ",\t\r\n") + "]")
        ])
        try validateJSON(source)
        try withFile(source) { file in
            let saved = try file.load()
            #expect(saved.newlySetAside == [.session, .previousRoutine, .appObservation])
            #expect(saved.session == nil && saved.previousRoutine == nil)
            #expect(saved.history?.runs == clean.history?.runs)
            #expect(saved.history?.appObservations == [goodDay])
            for (part, target) in [("session", session), ("previousRoutine", previous), ("appObservation", day)] {
                let raws = try rawEntries(saved, part: part)
                #expect(raws.count == 1)
                try exact(raws.first, target)
            }
            let earlier = try rawEntries(saved, part: "unrecognized")
            #expect(earlier.count == foreign.count)
            for (raw, target) in zip(earlier, foreign) { try exact(raw, target) }
            try exact(try rawEntries(saved, part: "capture").first, priorRaw)
            assertRestOfWorkspace(saved, matches: clean)
        }
    }

    @Test("A non-list earlier setAside value is retained as an exact whole value")
    func workspaceNonListSetAside() throws {
        for target in [#""quoted \" [,] \\""#, "false", "42", "{\r\n \"unknown\" : []\r\n}"] {
            var value = try fixtureValue()
            value["setAside"] = "RAW_ATTACK_EARLIER"
            let source = try workspace(value, replacements: [("RAW_ATTACK_EARLIER", target)])
            try withFile(source) { file in
                let saved = try file.load()
                #expect(saved.newlySetAside.isEmpty && saved.routine != nil)
                let raws = try rawEntries(saved, part: "unrecognized")
                #expect(raws.count == 1)
                try exact(raws.first, target)
            }
        }
    }

    @Test("Fixture duplicate envelope, collection, history and run keys refuse ambiguous recovery")
    func workspaceDuplicatePathKeysRefuse() throws {
        var value = try fixtureValue()
        value["captures"] = [false]
        let base = try json(value)
        let duplicateCapture = String(base.dropLast()) + #", "\u0063aptures":[true]}"#
        let badHistory = #"{"runs":[false],"runs":[true],"appObservations":[]}"#
        var historyValue = value
        historyValue["captures"] = []
        historyValue["history"] = "RAW_ATTACK_HISTORY"
        let runsDuplicate = try replaceMarker("RAW_ATTACK_HISTORY", with: badHistory, in: json(historyValue))
        let historyFirst = try replaceMarker("RAW_ATTACK_HISTORY", with: #"{"runs":[false]}"#, in: json(historyValue))
        let duplicateHistory = String(historyFirst.dropLast()) + #", "\u0068istory":{"runs":[true]}}"#
        let documents = [
            "{\"schemaVersion\":1,\"value\":" + base + ",\"value\":" + base + "}",
            "{\"schemaVersion\":1,\"value\":" + base + ",\"\\u0076alue\":" + base + "}",
            "{\"schemaVersion\":1,\"value\":" + duplicateCapture + "}",
            "{\"schemaVersion\":1,\"value\":" + runsDuplicate + "}",
            "{\"schemaVersion\":1,\"value\":" + duplicateHistory + "}"
        ]
        for source in documents {
            try validateJSON(source)
            try withFile(source) { file in
                #expect(throws: DecodingError.self) { try file.load() }
                let unchanged = try Data(contentsOf: file.url)
                #expect(unchanged == Data(source.utf8))
            }
        }
    }

    @Test("Duplicates inside a damaged capture stay intact when the entire object is set aside")
    func workspaceDuplicateInsideDamagedElement() throws {
        let target = #"{"kind":"unknown","kind":"also unknown","text":"first","\u0074ext":"second"}"#
        var value = try fixtureValue()
        value["captures"] = [Self.captureMarker]
        let source = try workspace(value, replacements: [(Self.captureMarker, target)])
        try withFile(source) { file in
            let saved = try file.load()
            #expect(saved.newlySetAside == [.capture])
            #expect(saved.captures?.isEmpty == true && saved.history?.runs.count == 3)
            try exact(try rawEntries(saved, part: "capture").first, target)
        }
    }

    @Test("BOM-prefixed full workspace either recovers exact text or refuses without changing the file")
    func workspaceBOMRefusesSafelyOrKeepsExact() throws {
        var value = try fixtureValue()
        let target = #"{"kind":"unknown","text":"é [,] \\"}"#
        value["captures"] = [Self.captureMarker]
        let source = "\u{FEFF}" + (try workspace(value, replacements: [(Self.captureMarker, target)]))
        try withFile(source) { file in
            let saved: WorkspaceSnapshot
            do { saved = try file.load() }
            catch {
                #expect(error is DecodingError)
                #expect(try Data(contentsOf: file.url) == Data(source.utf8))
                return
            }
            #expect(saved.newlySetAside == [.capture])
            try exact(try rawEntries(saved, part: "capture").first, target)
            #expect(saved.routine != nil && saved.history?.runs.count == 3)
        }
    }
}
