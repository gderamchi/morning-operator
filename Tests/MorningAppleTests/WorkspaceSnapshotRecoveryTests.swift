import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// The saved workspace is read through the same type and path as the app:
/// `AtomicJSONFile<WorkspaceSnapshot>.load()` (issue #94).
///
/// `Tests/Fixtures/workspace-1952d9f.json` was written by the code of commit 1952d9f, the
/// build installed on the owner's phone on 10 October: that commit's own package and a copy
/// of its app-side snapshot type, run in a scratch directory. Every text in it is invented.
/// Its key names and value types were checked against a real file from that build.
@Suite("Saved workspace: real earlier file and one bad element")
struct WorkspaceSnapshotRecoveryTests {
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/workspace-1952d9f.json")

    private func fixtureObject() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixture)) as? [String: Any])
    }

    /// Writes an edited copy of the fixture to its own folder and loads it as the app does.
    private func load(_ edit: (inout [String: Any]) throws -> Void = { _ in }) throws -> WorkspaceSnapshot {
        var root = try fixtureObject()
        var value = try #require(root["value"] as? [String: Any])
        try edit(&value)
        root["value"] = value
        return try AtomicJSONFile<WorkspaceSnapshot>(url: try write(root)).load()
    }

    private func write(_ root: Any) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("workspace.json")
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        return url
    }

    private func runs(_ value: [String: Any]) throws -> [[String: Any]] {
        try #require((value["history"] as? [String: Any])?["runs"] as? [[String: Any]])
    }

    private func setRuns(_ runs: [[String: Any]], in value: inout [String: Any]) throws {
        var history = try #require(value["history"] as? [String: Any])
        history["runs"] = runs
        value["history"] = history
    }

    private func json(_ object: Any) throws -> PreservedJSONValue {
        try JSONDecoder().decode(PreservedJSONValue.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("The file written by the 10 October build loads whole")
    func earlierBuildFileLoads() throws {
        let saved = try AtomicJSONFile<WorkspaceSnapshot>(url: Self.fixture).load()
        let routine = try #require(saved.routine)
        #expect(routine.isApproved && routine.steps.count >= 3)
        #expect(saved.previousRoutine?.isApproved == true)
        #expect(saved.session?.status == .running)
        #expect(saved.session?.routine == routine)
        let history = try #require(saved.history)
        #expect(history.runs.count == 3)
        #expect(history.runs.contains { $0.session.status == .completed })
        #expect(history.runs.contains { run in
            run.session.status == .stopped && run.session.events.contains { $0.kind == .paused }
        }, "A run stopped while paused")
        #expect(history.runs.contains { run in
            run.session.status == .stopped && !run.session.events.contains { $0.kind == .started }
        }, "A run stopped before it started")
        let choices = try #require(saved.routinePreferences?.value)
        let kept = try #require(choices.entries.first)
        #expect(kept.presence == .keep && kept.retainedStep != nil)
        #expect(routine.steps.contains { $0.id == kept.targetID })
        let archive = try #require(saved.observationArchive)
        let proposal = try #require(saved.pendingRoutineProposal?.value, "The saved proposal is read, not dropped")
        #expect(proposal.isCurrent(archive: archive, baseRoutine: routine, preferences: choices))
        #expect(saved.selectedObservationID.flatMap { archive.entry(id: $0) } != nil)
        #expect(saved.newlySetAside.isEmpty && saved.setAside == nil)
    }

    @Test("One unreadable past morning is set aside alone and kept verbatim")
    func oneBadRunIsSetAside() throws {
        let clean = try load()
        var damagedRun: [String: Any] = [:]
        let saved = try load { value in
            var all = try runs(value)
            var session = try #require(all[1]["session"] as? [String: Any])
            session["status"] = "flying"
            all[1]["session"] = session
            damagedRun = all[1]
            try setRuns(all, in: &value)
        }
        #expect(saved.newlySetAside == [.historyRun])
        #expect(saved.history?.runs.count == 2)
        #expect(saved.history?.runs == clean.history?.runs.enumerated().filter { $0.offset != 1 }.map(\.element))
        #expect(saved.routine == clean.routine && saved.session == clean.session)
        #expect(saved.previousRoutine == clean.previousRoutine)
        #expect(saved.pendingRoutineProposal?.value == clean.pendingRoutineProposal?.value)
        #expect(saved.setAside == [.object(["part": .string("historyRun"), "original": try json(damagedRun)])])
    }

    @Test("An unreadable morning in progress is set aside; the rest loads")
    func badSessionIsSetAside() throws {
        let clean = try load()
        let saved = try load { value in
            var session = try #require(value["session"] as? [String: Any])
            session["currentStepIndex"] = -4
            value["session"] = session
        }
        #expect(saved.session == nil)
        #expect(saved.newlySetAside == [.session])
        #expect(saved.history?.runs == clean.history?.runs)
        #expect(saved.routine == clean.routine)
        #expect(saved.setAside?.count == 1)
    }

    @Test("A bad session, run, day of app use, note and previous routine are each set aside")
    func everyRecoverablePartAtOnce() throws {
        let note = try QuickCapture(kind: .thought, text: "Invented test note", timeZoneIdentifier: "Europe/Paris")
        let noteObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note))
        let saved = try load { value in
            value["session"] = "not a session"
            value["previousRoutine"] = ["steps": 3]
            var all = try runs(value)
            all[0]["recordedAt"] = "yesterday"
            try setRuns(all, in: &value)
            var history = try #require(value["history"] as? [String: Any])
            history["appObservations"] = [["id": "not an id"]]
            value["history"] = history
            value["captures"] = [noteObject, ["kind": "dream"]]
        }
        #expect(Set(saved.newlySetAside) == Set(SetAsideWorkspacePart.allCases))
        #expect(saved.session == nil && saved.previousRoutine == nil)
        #expect(saved.history?.runs.count == 2 && saved.history?.appObservations.isEmpty == true)
        #expect(saved.captures == [note])
        #expect(saved.routine?.isApproved == true)
        #expect(saved.setAside?.count == 5)
    }

    @Test("Set-aside elements survive every later save and are not set aside twice")
    func setAsideSurvivesSaves() throws {
        let first = try load { value in
            var all = try runs(value)
            all[2]["timeZoneIdentifier"] = 12
            try setRuns(all, in: &value)
        }
        let kept = try #require(first.setAside)
        // The app builds each save from its own state, passing the kept elements along.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString).json")
        let file = AtomicJSONFile<WorkspaceSnapshot>(url: url)
        try file.save(WorkspaceSnapshot(routine: first.routine, session: first.session, history: first.history,
                                        setAside: kept))
        let second = try file.load()
        #expect(second.newlySetAside.isEmpty, "Nothing new was unreadable")
        #expect(second.setAside == kept)
        #expect(second.history?.runs.count == 2)
        try file.save(WorkspaceSnapshot(routine: second.routine, history: second.history, setAside: second.setAside))
        #expect(try file.load().setAside == kept)
        // An empty list is not written at all.
        try file.save(WorkspaceSnapshot(routine: second.routine, setAside: []))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("setAside"))
    }

    @Test("A damaged earlier set-aside list is kept as it is and never refuses the file")
    func damagedSetAsideListIsKept() throws {
        let saved = try load { value in value["setAside"] = "something odd" }
        #expect(saved.setAside == [.string("something odd")])
        #expect(saved.routine != nil && saved.newlySetAside.isEmpty)
        let null = try load { value in value["setAside"] = NSNull() }
        #expect(null.setAside == nil)
    }

    @Test("A session or previous routine saved as null is none, as before")
    func nullIsStillNone() throws {
        let saved = try load { value in
            value["session"] = NSNull()
            value["previousRoutine"] = NSNull()
            value["history"] = NSNull()
        }
        #expect(saved.session == nil && saved.previousRoutine == nil && saved.history == nil)
        #expect(saved.newlySetAside.isEmpty && saved.setAside == nil)
    }

    @Test("History written by the package reads back the same through the snapshot")
    func historyKeysMatch() throws {
        let clean = try load()
        let history = try #require(clean.history)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString).json")
        let file = AtomicJSONFile<WorkspaceSnapshot>(url: url)
        try file.save(WorkspaceSnapshot(history: history))
        #expect(try file.load().history == history)
    }

    @Test("An element too deep to set aside refuses the file instead of writing one that cannot be read back")
    func tooDeepToSetAside() throws {
        let depth = PreservedJSONValue.maximumDepth - 2
        var nested: Any = [String: Any]()
        for _ in 0..<depth { nested = [nested] }
        do {
            _ = try load { value in value["previousRoutine"] = nested }
            Issue.record("A previous routine nested \(depth) deep was set aside")
        } catch { #expect(UnreadableWorkspacePart(error: error) == .other) }
        // Shallow enough to be written and read back: set aside and reloaded unchanged.
        var shallow: Any = [String: Any]()
        for _ in 0..<(PreservedJSONValue.maximumDepth - 5) { shallow = [shallow] }
        let saved = try load { value in value["previousRoutine"] = shallow }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString).json")
        let file = AtomicJSONFile<WorkspaceSnapshot>(url: url)
        try file.save(WorkspaceSnapshot(routine: saved.routine, setAside: saved.setAside))
        #expect(try file.load().setAside == saved.setAside)
    }

    @Test("Numbers the app writes are set aside and written back with the same digits")
    func numbersKeepTheirDigits() throws {
        let values: [Double] = [0.1, 1.2345678901234567, 1_760_000_000.437, -0.125, 3, 1e20]
        let saved = try load { value in value["captures"] = values.map { ["n": $0] } }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString).json")
        let file = AtomicJSONFile<WorkspaceSnapshot>(url: url)
        try file.save(WorkspaceSnapshot(setAside: saved.setAside))
        struct Number: Decodable { let n: Double }
        struct Entry: Decodable { let original: Number }
        struct Envelope: Decodable { struct Value: Decodable { let setAside: [Entry] }; let value: Value }
        let back = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url)).value.setAside.map(\.original.n)
        #expect(back == values)
    }

    // MARK: Say what failed

    private func failure(_ edit: (inout [String: Any]) throws -> Void) throws -> UnreadableWorkspacePart {
        do { _ = try load(edit) } catch { return UnreadableWorkspacePart(error: error) }
        Issue.record("The damaged file was read")
        return .other
    }

    @Test("A refused file names the part that failed")
    func failureNamesThePart() throws {
        #expect(try failure { value in
            var routine = try #require(value["routine"] as? [String: Any])
            routine["steps"] = "none"
            value["routine"] = routine
        } == .routine)
        #expect(try failure { value in value["observationArchive"] = ["entries": 4] } == .observations)
        #expect(try failure { value in value["receipts"] = ["a": 1] } == .appleItems)
        #expect(try failure { value in value["readAloud"] = "loud" } == .settings)
        #expect(try failure { value in value["consumedMorningEntryIDs"] = ["x"] } == .startedMornings)
        #expect(try failure { value in value["history"] = ["runs": "none"] } == .history)
        #expect(try failure { value in value["captures"] = "none" } == .captures)
        #expect(try failure { value in value.removeValue(forKey: "schemaVersion") } == .file)
        #expect(UnreadableWorkspacePart(error: ObservationArchiveError.invalidSource) == .observations,
                "A legacy observation that cannot move into the archive")
    }

    @Test("A file that is not JSON, not there, or newer is named too")
    func wholeFileFailures() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let broken = folder.appendingPathComponent("broken.json")
        try Data("{\"schemaVersion\": 1, \"value\": {".utf8).write(to: broken)
        let missing = folder.appendingPathComponent("missing.json")
        let newer = try write(["schemaVersion": 2, "value": [:] as [String: Any]])
        func part(_ url: URL) -> UnreadableWorkspacePart? {
            do { _ = try AtomicJSONFile<WorkspaceSnapshot>(url: url).load(); return nil }
            catch { return UnreadableWorkspacePart(error: error) }
        }
        #expect(part(broken) == .file)
        #expect(part(missing) == .notOpened)
        #expect(part(newer) == .newerFormat)
    }

    @Test("Every sentence the person can read has French and no raw error text")
    func everySentenceHasFrench() throws {
        let path = try #require(Bundle.module.path(forResource: "fr", ofType: "lproj"))
        let french = try #require(Bundle(path: path))
        let keys = SetAsideWorkspacePart.allCases.map(\.sentenceKey) + [SetAsideWorkspacePart.keptKey]
            + UnreadableWorkspacePart.allCases.map(\.sentenceKey) + [UnreadableWorkspacePart.adviceKey]
        #expect(Set(keys).count == keys.count)
        for key in keys {
            let text = french.localizedString(forKey: key, value: nil, table: nil)
            #expect(text != key && !text.isEmpty, "No French for: \(key)")
        }
        let notice = try #require(SetAsideWorkspacePart.notice(for: [.historyRun, .session, .historyRun], bundle: french))
        #expect(notice.hasPrefix(french.localizedString(forKey: SetAsideWorkspacePart.session.sentenceKey, value: nil, table: nil)))
        #expect(SetAsideWorkspacePart.notice(for: []) == nil)
        #expect(UnreadableWorkspacePart.routine.sentence(bundle: french) != UnreadableWorkspacePart.routine.sentenceKey)
    }
}
