import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Synthetic attacks on the actual workspace file loader, written by a Codex tester (#94). Numeric inputs are written
/// as JSON text so NSNumber/Double cannot round them before the code under test sees them.
@Suite("Workspace recovery attacks")
struct WorkspaceRecoveryAttackTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let fixture = repository.appendingPathComponent("Tests/Fixtures/workspace-1952d9f.json")

    private func withFile<T>(_ body: (AtomicJSONFile<WorkspaceSnapshot>) throws -> T) throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-attack-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try body(AtomicJSONFile(url: folder.appendingPathComponent("workspace.json")))
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
    }

    private func json(_ object: Any) throws -> PreservedJSONValue {
        try JSONDecoder().decode(PreservedJSONValue.self, from: jsonData(object))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    /// Enrich the old fixture with two valid days and captures: isolation must protect
    /// healthy siblings, including fields absent from the original fixture.
    private func fixtureValue() throws -> [String: Any] {
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixture)) as? [String: Any])
        var value = try #require(root["value"] as? [String: Any])
        var history = try #require(value["history"] as? [String: Any])
        history["appObservations"] = try (0..<2).map { index in
            try object(DailyAppObservation(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
                date: Date(timeIntervalSinceReferenceDate: 780_000_000 + Double(index) * 86_400),
                timeZoneIdentifier: "Europe/Paris", appName: "Synthetic test app",
                counts: .init(emailsRead: index), provenance: .syntheticDemo,
                evidenceReferences: ["Invented attack-test evidence"],
                updatedAt: Date(timeIntervalSinceReferenceDate: 781_000_000)))
        }
        value["history"] = history
        value["captures"] = try (0..<2).map { index in
            try object(QuickCapture(
                id: UUID(uuidString: "10000000-0000-0000-0000-00000000000\(index)")!,
                kind: .thought, text: "Invented thought \(index)",
                createdAt: Date(timeIntervalSinceReferenceDate: 781_000_000 + Double(index)),
                timeZoneIdentifier: "Europe/Paris"))
        }
        value["voiceIdentifier"] = "synthetic.voice"
        value["budgetAndFeedback"] = budgetObject()
        return value
    }

    /// A time target and two feedback records (#10), as JSONEncoder writes them.
    private func budgetObject(records: [Int] = [0, 1]) -> [String: Any] {
        ["targetMinutes": 30, "feedback": records.map { index -> [String: Any] in
            ["id": "20000000-0000-0000-0000-00000000000\(index)",
             "sessionID": "30000000-0000-0000-0000-00000000000\(index)",
             "routineVersionID": "40000000-0000-0000-0000-000000000000",
             "wasUseful": index == 0 ? "yes" : "no", "recordedAt": 781_000_000 + index]
        }]
    }

    private func budget(_ object: [String: Any]) throws -> RoutineBudgetAndFeedback {
        try JSONDecoder().decode(RoutineBudgetAndFeedback.self, from: jsonData(object))
    }

    private func load(_ edit: (inout [String: Any]) throws -> Void = { _ in }) throws -> WorkspaceSnapshot {
        var value = try fixtureValue()
        try edit(&value)
        return try withFile { file in
            try jsonData(["schemaVersion": 1, "value": value]).write(to: file.url)
            return try file.load()
        }
    }

    private func loadRaw(_ fields: String) throws -> WorkspaceSnapshot {
        try withFile { file in
            try Data("{\"schemaVersion\":1,\"value\":{\"schemaVersion\":1,\(fields)}}".utf8).write(to: file.url)
            return try file.load()
        }
    }

    /// Exercise the public initializer the app uses when building its next save.
    private func rebuilt(_ s: WorkspaceSnapshot) -> WorkspaceSnapshot {
        WorkspaceSnapshot(routine: s.routine, session: s.session, previousRoutine: s.previousRoutine,
            history: s.history, captures: s.captures, receipts: s.receipts, sessionTimeZone: s.sessionTimeZone,
            automatic: s.automatic, readAloud: s.readAloud, showMorningOnLockScreen: s.showMorningOnLockScreen,
            sessionTimingInterrupted: s.sessionTimingInterrupted, budgetAndFeedback: s.budgetAndFeedback,
            pendingCaptures: s.pendingCaptures,
            voiceIdentifier: s.voiceIdentifier, observationNotes: s.observationNotes,
            observationSource: s.observationSource, observationVideoEvidence: s.observationVideoEvidence,
            observationContextClassification: s.observationContextClassification,
            observationArchive: s.observationArchive, selectedObservationID: s.selectedObservationID,
            pendingRoutineProposal: s.pendingRoutineProposal, consumedMorningEntryIDs: s.consumedMorningEntryIDs,
            routinePreferences: s.routinePreferences, greeting: s.greeting, setAside: s.setAside)
    }

    private func assertStable(_ first: WorkspaceSnapshot) throws {
        try withFile { file in
            var current = first
            for _ in 0..<3 {
                try file.save(rebuilt(current))
                current = try file.load()
                #expect(current.setAside == first.setAside)
                #expect(current.newlySetAside.isEmpty)
                #expect(try json(object(current)) == json(object(first)))
            }
        }
    }

    private func entry(_ part: SetAsideWorkspacePart, _ original: PreservedJSONValue) -> PreservedJSONValue {
        .object(["part": .string(part.rawValue), "original": original])
    }

    /// Set-aside entries hold the exact saved text ({"part", "raw"}). For structural
    /// comparison, read each text back into the {"part", "original"} form above.
    private func normalized(_ list: [PreservedJSONValue]?) throws -> [PreservedJSONValue]? {
        try list?.map { item in
            guard case .object(let fields) = item, fields.count == 2, let part = fields["part"],
                  case .string(let raw)? = fields["raw"] else { return item }
            return .object(["part": part, "original": try JSONDecoder().decode(PreservedJSONValue.self, from: Data(raw.utf8))])
        }
    }

    private func raws(_ list: [PreservedJSONValue]?) -> [String] {
        (list ?? []).compactMap { item in
            guard case .object(let fields) = item, case .string(let raw)? = fields["raw"] else { return nil }
            return raw
        }
    }

    @Test("Each damaged part leaves every other saved field and sibling unchanged")
    func individualDamageIsIsolated() throws {
        let clean = try load()
        for part in SetAsideWorkspacePart.allCases {
            var expected = clean
            var damaged: [String: Any] = [:]
            var scalar: Any?
            let saved = try load { value in
                switch part {
                case .session, .previousRoutine:
                    let key = part.rawValue
                    damaged = try #require(value[key] as? [String: Any])
                    if part == .session { damaged["currentStepIndex"] = -4; expected.session = nil }
                    else { damaged["steps"] = "broken"; expected.previousRoutine = nil }
                    value[key] = damaged
                case .historyRun, .appObservation:
                    var history = try #require(value["history"] as? [String: Any])
                    let key = part == .historyRun ? "runs" : "appObservations"
                    var all = try #require(history[key] as? [[String: Any]])
                    damaged = all[1]
                    damaged["timeZoneIdentifier"] = "Not/A/TimeZone"
                    all[1] = damaged
                    history[key] = all
                    value["history"] = history
                    let old = try #require(clean.history)
                    expected.history = MorningHistory(
                        runs: part == .historyRun ? old.runs.enumerated().filter { $0.offset != 1 }.map(\.element) : old.runs,
                        appObservations: part == .appObservation ? [old.appObservations[0]] : old.appObservations)
                case .capture:
                    var all = try #require(value["captures"] as? [[String: Any]])
                    damaged = all[1]
                    damaged["text"] = " \n\t "
                    all[1] = damaged
                    value["captures"] = all
                    expected.captures = [try #require(clean.captures?.first)]
                case .timeTarget, .longerPlanAcceptance:
                    var saved = budgetObject()
                    let key = part == .timeTarget ? "targetMinutes" : "acceptedLongerPlan"
                    scalar = part == .timeTarget ? 999 : ["routineVersionID": "nope"]
                    saved[key] = scalar
                    value["budgetAndFeedback"] = saved
                    var kept = budgetObject()
                    if part == .timeTarget { kept.removeValue(forKey: "targetMinutes") }
                    expected.budgetAndFeedback = try budget(kept)
                case .runFeedback:
                    var saved = budgetObject()
                    var all = try #require(saved["feedback"] as? [[String: Any]])
                    damaged = all[1]
                    damaged["wasUseful"] = "maybe"
                    all[1] = damaged
                    saved["feedback"] = all
                    value["budgetAndFeedback"] = saved
                    expected.budgetAndFeedback = try budget(budgetObject(records: [0]))
                case .timeBudgetAndFeedback:
                    scalar = "thirty minutes"
                    value["budgetAndFeedback"] = scalar
                    expected.budgetAndFeedback = RoutineBudgetAndFeedback()
                }
            }
            expected.setAside = [entry(part, try json(scalar ?? damaged))]
            #expect(saved.newlySetAside == [part])
            var comparable = saved
            comparable.setAside = try normalized(saved.setAside)
            #expect(try json(object(comparable)) == json(object(expected)), "Changed unrelated data for \(part)")
            try assertStable(saved)
        }
    }

    @Test("A damaged duplicate run never displaces its healthy copy, in either order")
    func duplicateRunIDsWithOneDamagedCopy() throws {
        let clean = try load()
        for damagedFirst in [false, true] {
            var raw: [String: Any] = [:]
            let saved = try load { value in
                var history = try #require(value["history"] as? [String: Any])
                var runs = try #require(history["runs"] as? [[String: Any]])
                let good = runs[1]
                raw = good
                raw["recordedAt"] = "not a date"
                runs.replaceSubrange(1...1, with: damagedFirst ? [raw, good] : [good, raw])
                history["runs"] = runs
                value["history"] = history
            }
            #expect(saved.history == clean.history)
            #expect(try normalized(saved.setAside) == [entry(.historyRun, try json(raw))])
            #expect(saved.newlySetAside == [.historyRun])
            try assertStable(saved)
        }
    }

    @Test("Healthy duplicate runs retain MorningHistory's existing ordering and upsert semantics")
    func healthyDuplicateRunsMatchExistingDecoder() throws {
        var expected: MorningHistory?
        let saved = try load { value in
            var history = try #require(value["history"] as? [String: Any])
            var runs = try #require(history["runs"] as? [[String: Any]])
            var duplicate = runs[0]
            duplicate["timingInterrupted"] = true
            runs = [runs[2], runs[0], runs[1], duplicate]
            history["runs"] = runs
            expected = try JSONDecoder().decode(MorningHistory.self, from: jsonData(history))
            value["history"] = history
        }
        #expect(saved.history == expected)
        #expect(saved.newlySetAside.isEmpty && saved.setAside == nil)
    }

    @Test("Every recoverable element can be damaged without losing the rest of the workspace")
    func everyElementDamaged() throws {
        let clean = try load()
        var originals: [PreservedJSONValue] = []
        var parts: [SetAsideWorkspacePart] = []
        let saved = try load { value in
            for (key, part) in [("session", SetAsideWorkspacePart.session), ("previousRoutine", .previousRoutine)] {
                let bad: [String: Any] = ["broken": key]
                value[key] = bad
                originals.append(entry(part, try json(bad))); parts.append(part)
            }
            var history = try #require(value["history"] as? [String: Any])
            for (key, count, part) in [("runs", 3, SetAsideWorkspacePart.historyRun), ("appObservations", 2, .appObservation)] {
                let bad = (0..<count).map { ["broken": "\(key)-\($0)"] }
                history[key] = bad
                originals += try bad.map { entry(part, try json($0)) }
                parts += Array(repeating: part, count: count)
            }
            value["history"] = history
            let bad = [["broken": "capture-0"], ["broken": "capture-1"]]
            value["captures"] = bad
            originals += try bad.map { entry(.capture, try json($0)) }
            parts += [.capture, .capture]
        }
        var expected = clean
        expected.session = nil; expected.previousRoutine = nil
        expected.history = MorningHistory(); expected.captures = []; expected.setAside = originals
        #expect(saved.newlySetAside == parts)
        var comparable = saved
        comparable.setAside = try normalized(saved.setAside)
        #expect(try json(object(comparable)) == json(object(expected)))
        try assertStable(saved)
    }

    @Test("Non-object array elements, including null, are individually preserved")
    func arraysOfNonObjects() throws {
        let raw: [Any] = [NSNull(), false, 42, -8.5, "é 👩🏽‍💻", [], [1, ["nested"]]]
        let saved = try load { value in
            value["captures"] = raw
            value["history"] = ["runs": raw, "appObservations": raw]
        }
        let parts: [SetAsideWorkspacePart] = [.historyRun, .appObservation, .capture]
        let expected = try parts.flatMap { part in try raw.map { entry(part, try json($0)) } }
        #expect(saved.history == MorningHistory() && saved.captures == [])
        #expect(try normalized(saved.setAside) == expected)
        #expect(saved.newlySetAside == parts.flatMap { Array(repeating: $0, count: raw.count) })
        try assertStable(saved)
    }

    @Test("Missing and null optional fields keep their existing absence behavior")
    func missingAndNullTopLevelFields() throws {
        // Saved choices intentionally distinguish null from missing; tested separately below.
        for key in Self.pathCases.map(\.0).filter({ !["schemaVersion", "routinePreferences"].contains($0) }) {
            let missing = try load { $0.removeValue(forKey: key) }
            let null = try load { $0[key] = NSNull() }
            #expect(try json(object(missing)) == json(object(null)), "Null changed the meaning of \(key)")
            #expect(null.newlySetAside.isEmpty && null.setAside == nil)
            #expect(try object(null)[key] == nil)
        }
    }

    @Test("Null choices retain the preexisting unreadable marker rather than becoming missing")
    func nullPreferencesKeepLegacyBehavior() throws {
        let missing = try load { $0.removeValue(forKey: "routinePreferences") }
        let null = try load { $0["routinePreferences"] = NSNull() }
        #expect(missing.routinePreferences == nil)
        #expect(null.routinePreferences != nil && null.routinePreferences?.value == nil)
        #expect(null.newlySetAside.isEmpty && null.setAside == nil)
        #expect(try object(null)["routinePreferences"] is NSNull)
        try assertStable(null)
    }

    @Test("Missing and null run/day arrays mean empty, while null captures means none")
    func nullAndMissingCollections() throws {
        for history: [String: Any] in [[:], ["runs": NSNull()], ["appObservations": NSNull()],
                                       ["runs": NSNull(), "appObservations": NSNull()]] {
            let expected = try JSONDecoder().decode(MorningHistory.self, from: jsonData(history))
            let saved = try load { $0["history"] = history; $0["captures"] = NSNull() }
            #expect(saved.history == expected && saved.history == MorningHistory())
            #expect(saved.captures == nil && saved.setAside == nil && saved.newlySetAside.isEmpty)
        }
        #expect(try load { $0["captures"] = [] }.captures == [])
    }

    @Test("Earlier setAside objects, numbers and nested arrays retain their exact text")
    func arbitraryEarlierSetAsideShapes() throws {
        let shapes: [String] = [#"{"part":42,"original":[null,{},["雪"]]}"#,
            "18446744073709551617", "-9223372036854775809", "1e400", "true", "\"\"",
            #"[[[{}]],null,[[1,"é"]],{"arbitrary":false}]"#, "[]", "{}", "null"]
        for raw in shapes {
            let saved = try loadRaw("\"setAside\":\(raw)")
            switch raw {
            case "null", "[]": #expect(saved.setAside == nil)
            case _ where raw.hasPrefix("[["):
                // A list: each foreign item is kept as its own exact text.
                #expect(raws(saved.setAside) == [#"[[{}]]"#, "null", #"[[1,"é"]]"#, #"{"arbitrary":false}"#])
            default:
                #expect(raws(saved.setAside) == [raw], "Kept \(raw) as its exact text")
            }
            #expect(saved.newlySetAside.isEmpty)
            try assertStable(saved)
        }
    }

    @Test("A newly damaged occurrence equal to an earlier one is kept once per occurrence")
    func equalPreviouslySetAsidePayloadIsNotMistakenForRetry() throws {
        let raw: [String: Any] = ["broken": ["é", "雪"]]
        let text = String(decoding: try jsonData(raw), as: UTF8.self)
        let prior: [String: Any] = ["part": "capture", "raw": text]
        let saved = try load { value in
            value["setAside"] = [prior]
            value["captures"] = [raw, raw]
        }
        #expect(raws(saved.setAside) == [text, text, text])
        #expect(saved.newlySetAside == [.capture, .capture])
        #expect(saved.captures == [])
        try assertStable(saved)
    }

    @Test("Numbers no Swift type holds exactly, escapes and unicode keep their exact text")
    func setAsideTextFidelity() throws {
        let raw = #"{"signed":-9223372036854775809,"unsigned":18446744073709551617,"aboveDoubleInteger":9007199254740993,"one":1.0000000000000001,"long":0.16894785220002650112,"tiny":5e-324,"huge":1e400,"nested":[[],{},[true,false,null,{"é":"雪 👩🏽‍💻 \u0000 e\u0301 \" ] }"}]],"empty":{}}"#
        let saved = try loadRaw("\"captures\":[ \(raw) ]")
        #expect(raws(saved.setAside) == [raw])
        #expect(saved.newlySetAside == [.capture])
        try assertStable(saved)
    }

    @Test("Deep arrays and objects survive both initial isolation and later saves")
    func deeplyNestedRawContent() throws {
        // Deep nesting once exhausted the stack. Run only this test in a child so that a
        // crash is a reported failure and does not stop the other attack tests.
        let environmentKey = "MO_WORKSPACE_ATTACK_DEPTH"
        guard let text = ProcessInfo.processInfo.environment[environmentKey], let depth = Int(text) else {
            for (depth, shape) in [64, 128, 240, 480].flatMap({ depth in ["array", "object"].map { (depth, $0) } }) {
                let child = Process()
                let developer = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Applications/Xcode.app/Contents/Developer"
                child.executableURL = URL(fileURLWithPath: developer).appendingPathComponent(
                    "Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper")
                child.arguments = ["--test-bundle-path", try #require(Bundle(for: BundleMarker.self).executableURL).path,
                                   "--testing-library", "swift-testing",
                                   "--filter", "WorkspaceRecoveryAttackTests/deeplyNestedRawContent"]
                var environment = ProcessInfo.processInfo.environment
                environment[environmentKey] = String(depth)
                environment["MO_WORKSPACE_ATTACK_SHAPE"] = shape
                child.environment = environment
                let output = Pipe()
                child.standardOutput = output; child.standardError = output
                try child.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                child.waitUntilExit()
                let transcript = String(decoding: data, as: UTF8.self)
                #expect(child.terminationReason == .exit && child.terminationStatus == 0,
                        "Depth \(depth), \(shape): reason \(child.terminationReason), status \(child.terminationStatus). \(transcript)")
                if child.terminationReason == .exit && child.terminationStatus == 0 {
                    #expect(transcript.contains("Save/reload checks complete"),
                            "The isolated test must actually run: \(transcript)")
                }
            }
            return
        }
        // Stay below Foundation's document-wide JSON depth limit; exceeding that
        // rejects JSON before WorkspaceSnapshot or the recovery wrappers run.
        let isArray = ProcessInfo.processInfo.environment["MO_WORKSPACE_ATTACK_SHAPE"] == "array"
        let nested = isArray
            ? String(repeating: "[", count: depth) + "{}" + String(repeating: "]", count: depth)
            : String(repeating: "{\"child\":", count: depth) + "{}" + String(repeating: "}", count: depth)
        let fields = isArray ? "\"captures\":[\(nested)]" : "\"setAside\":\(nested)"
        // Independent parser control and an iteratively built oracle distinguish
        // recovery recursion from malformed JSON or a recursive test decoder.
        struct Header: Decodable { let schemaVersion: Int }
        let document = Data("{\"schemaVersion\":1,\"value\":{\"schemaVersion\":1,\(fields)}}".utf8)
        #expect(try JSONDecoder().decode(Header.self, from: document).schemaVersion == 1)
        func mark(_ stage: String) { FileHandle.standardOutput.write(Data("\(stage)\n".utf8)) }
        mark("JSON syntax accepted; loading workspace")
        let saved = try loadRaw(fields)
        mark("Workspace loaded; checking contents")
        // Both are kept as their exact text: a damaged capture, or a foreign earlier entry.
        #expect(raws(saved.setAside) == [nested])
        #expect(saved.newlySetAside == (isArray ? [.capture] : []))
        mark("Contents checked; saving and reloading")
        try assertStable(saved)
        mark("Save/reload checks complete")
    }

    private final class BundleMarker: NSObject {}

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int?
        init(_ value: String) { stringValue = value; intValue = nil }
        init(stringValue: String) { self.init(stringValue) }
        init(intValue: Int) { self.intValue = intValue; stringValue = "Index \(intValue)" }
    }

    private static let pathCases: [(String, UnreadableWorkspacePart)] = [
        ("schemaVersion", .file), ("routine", .routine), ("session", .other), ("previousRoutine", .other),
        ("history", .history), ("captures", .captures), ("receipts", .appleItems),
        ("sessionTimeZone", .settings), ("automatic", .settings), ("readAloud", .settings),
        ("showMorningOnLockScreen", .settings), ("sessionTimingInterrupted", .settings),
        ("pendingCaptures", .appleItems), ("voiceIdentifier", .settings),
        ("observationNotes", .observations), ("observationSource", .observations),
        ("observationVideoEvidence", .observations), ("observationContextClassification", .observations),
        ("observationArchive", .observations), ("selectedObservationID", .observations),
        ("pendingRoutineProposal", .suggestion), ("consumedMorningEntryIDs", .startedMornings),
        ("routinePreferences", .suggestion), ("greeting", .other), ("setAside", .other)]

    @Test("Every top-level coding path is classified for all four DecodingError variants")
    func everyTopLevelDecodingErrorPath() {
        for (key, expected) in Self.pathCases + [("futureUnknownField", .other)] {
            for tail: [Key] in [[], [Key("nested"), Key(intValue: 2), Key("routine")]] {
                let path = [Key("value"), Key(key)] + tail
                let context = DecodingError.Context(codingPath: path, debugDescription: "Synthetic private text")
                let errors: [DecodingError] = [.typeMismatch(String.self, context),
                    .valueNotFound(String.self, context), .dataCorrupted(context),
                    .keyNotFound(path.last!, .init(codingPath: Array(path.dropLast()), debugDescription: "Synthetic"))]
                for error in errors {
                    #expect(UnreadableWorkspacePart(error: error) == expected, "Incorrect path: \(key)")
                }
            }
        }
    }

    @Test("Actual refused workspace fields carry the envelope coding path")
    func actualRefusedFieldsNameTheirPart() throws {
        let recovered = ["session", "previousRoutine", "observationContextClassification",
                         "pendingRoutineProposal", "routinePreferences", "greeting", "setAside"]
        for (key, expected) in Self.pathCases where !recovered.contains(key) {
            do {
                _ = try load { $0[key] = 123.5 }
                Issue.record("Expected a refused \(key)")
            } catch {
                #expect(error is DecodingError, "Expected a coding path for \(key): \(error)")
                #expect(UnreadableWorkspacePart(error: error) == expected, "Incorrect actual path for \(key)")
            }
        }
    }

    @Test("Invalid routine evidence is reported as routine damage, not a file-open failure")
    func routineValidationFailureNamesRoutine() throws {
        do {
            _ = try load { value in
                var routine = try #require(value["routine"] as? [String: Any])
                var steps = try #require(routine["steps"] as? [[String: Any]])
                steps[0]["observationReference"] = [
                    "acquisitionID": "00000000-0000-0000-0000-000000000001",
                    "revisionSHA256": "bad", "quote": "Invented evidence"]
                routine["steps"] = steps
                value["routine"] = routine
            }
            Issue.record("An invalid evidence revision must refuse the routine")
        } catch {
            #expect(UnreadableWorkspacePart(error: error) == .routine, "Content validation failed: \(error)")
        }
    }

    @Test("Observation validation failures are reported as observations, not file-open failures")
    func observationValidationFailuresNameObservations() throws {
        for key in ["observationArchive", "observationVideoEvidence"] {
            do {
                _ = try load { value in
                    if key == "observationArchive" {
                        var archive = try #require(value[key] as? [String: Any])
                        let entries = try #require(archive["entries"] as? [[String: Any]])
                        let first = try #require(entries.first)
                        archive["entries"] = [first, first]
                        value[key] = archive
                    } else {
                        value[key] = ["id": "00000000-0000-0000-0000-000000000001",
                                      "durationSeconds": 0, "frames": [], "warnings": []] as [String: Any]
                    }
                }
                Issue.record("Invalid \(key) must refuse the workspace")
            } catch {
                #expect(UnreadableWorkspacePart(error: error) == .observations,
                        "Content validation failed for \(key): \(error)")
            }
        }
    }

    @Test("Envelope errors and non-workspace paths cannot be mislabeled as nested data")
    func envelopeFailurePaths() throws {
        for path: [Key] in [[], [Key("value")], [Key("schemaVersion")],
                           [Key("routine")], [Key("unknown"), Key("routine")]] {
            let context = DecodingError.Context(codingPath: path, debugDescription: "Synthetic")
            #expect(UnreadableWorkspacePart(error: DecodingError.dataCorrupted(context)) == .file)
        }
        for raw in ["{", "null", "[]", "{}", #"{"schemaVersion":1}"#,
                    #"{"schemaVersion":1,"value":null}"#, #"{"schemaVersion":1,"value":[]}"#,
                    #"{"schemaVersion":1,"value":{}}"#] {
            try withFile { file in
                try Data(raw.utf8).write(to: file.url)
                do { _ = try file.load(); Issue.record("Expected refusal for \(raw)") }
                catch { #expect(UnreadableWorkspacePart(error: error) == .file) }
            }
        }
        #expect(UnreadableWorkspacePart(error: PersistenceError.unsupportedSchema(2)) == .newerFormat)
    }

    @Test("Every recovery sentence is translated in the required source String Catalog")
    func frenchSourceCatalogCoversEverySentence() throws {
        let url = Self.repository.appendingPathComponent("Sources/MorningApple/Resources/Localizable.xcstrings")
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let keys = SetAsideWorkspacePart.allCases.map(\.sentenceKey) + [SetAsideWorkspacePart.keptKey]
            + UnreadableWorkspacePart.allCases.map(\.sentenceKey) + [UnreadableWorkspacePart.adviceKey]
        #expect(Set(keys).count == keys.count)
        for key in keys {
            let item = try #require(strings[key] as? [String: Any], "Missing catalog key: \(key)")
            let localizations = try #require(item["localizations"] as? [String: Any])
            let french = try #require(localizations["fr"] as? [String: Any], "Missing French for: \(key)")
            let unit = try #require(french["stringUnit"] as? [String: Any])
            let text = try #require(unit["value"] as? String)
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != key)
            #expect(unit["state"] as? String == "translated")
        }
    }
}
