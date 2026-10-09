import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Local Shortcuts transition journal")
struct AppTransitionLogStoreTests {
    @Test func clearingSurvivesReloadPreservesWorkspaceAndAllowsNewEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        let firstID = UUID()
        try await store.record(app: .instagram, kind: .entered, eventID: firstID)
        let workspace = directory.appendingPathComponent("workspace.json")
        let workspaceData = Data("Existing routines and notes".utf8)
        try workspaceData.write(to: workspace)

        try await store.clear()
        try await store.clear() // An already cleared journal is a safe no-op.
        let reloaded = AppTransitionLogStore(directory: directory)
        #expect(try await reloaded.events().isEmpty)
        #expect(try Data(contentsOf: workspace) == workspaceData)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("app-transitions.json").path))

        try await reloaded.record(app: .tiktok, kind: .entered)
        let newEvents = try await reloaded.events()
        #expect(newEvents.count == 1)
        #expect(newEvents.first?.app == .tiktok)
        #expect(!newEvents.contains { $0.id == firstID })

        // The explicit clear action must also recover from a journal that cannot be decoded.
        let journal = directory.appendingPathComponent("app-transitions.json")
        try Data("corrupt journal".utf8).write(to: journal)
        try await reloaded.clear()
        #expect(try await reloaded.events().isEmpty)
        #expect(try Data(contentsOf: workspace) == workspaceData)
    }

    @Test func writeRetryAndReloadPreserveOriginalEventAndSeparateWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try await store.record(app: .instagram, kind: .entered, observedAt: date,
            eventID: id, timeZoneIdentifier: "UTC"))
        #expect(try await !store.record(app: .instagram, kind: .entered, observedAt: date.addingTimeInterval(20),
            eventID: id, timeZoneIdentifier: "UTC"))
        let restored = AppTransitionLogStore(directory: directory)
        let events = try await restored.events()
        #expect(events.count == 1)
        #expect(events.first?.observedAt == date)
        #expect(events.first?.source == .shortcut)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path))
        await #expect(throws: AppTransitionError.conflictingEventID) {
            try await store.record(app: .snapchat, kind: .entered, eventID: id)
        }
    }

    @Test func concurrentRequestsAreSerializedAndCorruptLogIsNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<6 {
                group.addTask {
                    _ = try await store.record(app: .tiktok, kind: .entered,
                        observedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), timeZoneIdentifier: "UTC")
                }
            }
            try await group.waitForAll()
        }
        #expect(try await store.events().count == 6)
        let url = directory.appendingPathComponent("app-transitions.json")
        let corrupt = Data("not valid JSON".utf8)
        try corrupt.write(to: url)
        await #expect(throws: (any Error).self) {
            try await store.record(app: .instagram, kind: .entered)
        }
        #expect(try Data(contentsOf: url) == corrupt)
    }
}
