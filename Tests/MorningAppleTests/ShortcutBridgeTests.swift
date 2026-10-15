import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Named shortcut request and return boundary")
struct ShortcutBridgeTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func launchEncodesNamesInputAndCallbackIdentity() throws {
        var bridge = ShortcutBridge(callbackScheme: "moreqa")
        let request = try bridge.begin(name: "Mon raccourci + # & café", input: "A+B & x=é? #", operation: .mail, now: instant)
        let url = try #require(URLComponents(url: request.launchURL, resolvingAgainstBaseURL: false))
        #expect(url.scheme == "shortcuts")
        #expect(url.host == "x-callback-url")
        #expect(url.path == "/run-shortcut")
        #expect(value("name", in: url) == "Mon raccourci + # & café")
        #expect(value("text", in: url) == "A+B & x=é? #")
        let callback = try callback(for: request, kind: "success", result: "two + three & four")
        #expect(callback.scheme == "moreqa")
        let outcome = try bridge.accept(callback, now: instant.addingTimeInterval(1))
        #expect(outcome.text == "two + three & four")
        #expect(outcome.operation == .mail)
        #expect(outcome.status == .returned)
        #expect(bridge.pending == nil)
        #expect(throws: ShortcutBridgeError.noPendingRequest) { try bridge.accept(callback, now: instant.addingTimeInterval(2)) }
    }

    @Test func forgedOrMalformedCallbacksCannotConsumeThePendingRequest() throws {
        var bridge = ShortcutBridge()
        let request = try bridge.begin(name: "Messages", input: "", operation: .messages, now: instant)
        let valid = try callback(for: request, kind: "success", result: "hello")
        let base = try #require(URLComponents(url: valid, resolvingAgainstBaseURL: false))
        for modification in 0..<6 {
            var wrong = base
            switch modification {
            case 0: wrong.queryItems?.removeAll { $0.name == "nonce" }
            case 1: wrong.queryItems?.append(.init(name: "nonce", value: request.id.uuidString))
            case 2: wrong.queryItems = wrong.queryItems?.map { $0.name == "operation" ? .init(name: "operation", value: "notes") : $0 }
            case 3: wrong.fragment = "unexpected"
            case 4: wrong.user = "untrusted"
            default: wrong.queryItems?.append(.init(name: "unexpected", value: "true"))
            }
            let url = try #require(wrong.url)
            #expect(throws: ShortcutBridgeError.invalidCallback) { try bridge.accept(url, now: instant) }
            #expect(bridge.pending == request)
        }
        _ = try bridge.accept(valid, now: instant)
    }

    @Test func expiryCancellationAndProcessRestartRejectLateReturns() throws {
        var bridge = ShortcutBridge()
        let request = try bridge.begin(name: "Notes", input: "", now: instant)
        let success = try callback(for: request, kind: "success", result: "old")
        #expect(throws: ShortcutBridgeError.expired) { try bridge.accept(success, now: request.expiresAt) }
        #expect(bridge.pending == nil)
        var relaunched = ShortcutBridge()
        #expect(throws: ShortcutBridgeError.noPendingRequest) { try relaunched.accept(success, now: instant) }
        let next = try bridge.begin(name: "Notes", input: "", now: instant)
        bridge.cancel()
        #expect(throws: ShortcutBridgeError.noPendingRequest) { try bridge.accept(try callback(for: next, kind: "success"), now: instant) }
    }

    @Test func errorAndCancelAreDistinctFromSuccessfulText() throws {
        for kind in ["error", "cancel"] {
            var bridge = ShortcutBridge()
            let request = try bridge.begin(name: "Clock", input: "", now: instant)
            let outcome = try bridge.accept(try callback(for: request, kind: kind), now: instant)
            #expect(outcome.status == (kind == "error" ? .failed : .cancelled))
            #expect(outcome.text.isEmpty)
        }
    }

    @Test func namesInputsResultsAndConcurrentRequestsAreBounded() throws {
        var bridge = ShortcutBridge()
        #expect(throws: ShortcutBridgeError.invalidName) { try bridge.begin(name: "\n", input: "", now: instant) }
        #expect(throws: ShortcutBridgeError.inputTooLarge) {
            try bridge.begin(name: "Notes", input: String(repeating: "é", count: 513), now: instant)
        }
        let request = try bridge.begin(name: "Notes", input: "", now: instant)
        #expect(throws: ShortcutBridgeError.alreadyWaiting) { try bridge.begin(name: "Mail", input: "", now: instant) }
        #expect(throws: ShortcutBridgeError.resultTooLarge) {
            try bridge.accept(try callback(for: request, kind: "success", result: String(repeating: "é", count: 4_097)), now: instant)
        }
        #expect(bridge.pending == request)
        let firstExpiry = bridge.expire(at: request.expiresAt)
        let secondExpiry = bridge.expire(at: request.expiresAt)
        #expect(firstExpiry)
        #expect(!secondExpiry)
    }

    private func value(_ name: String, in url: URLComponents) -> String? { url.queryItems?.first { $0.name == name }?.value }
    private func callback(for request: ShortcutBridgeRequest, kind: String, result: String? = nil) throws -> URL {
        let url = try #require(URLComponents(url: request.launchURL, resolvingAgainstBaseURL: false))
        let destination = try #require(value("x-\(kind)", in: url))
        var callback = try #require(URLComponents(string: destination))
        if let result { callback.queryItems?.append(.init(name: "result", value: result)) }
        return try #require(callback.url)
    }
}

@Suite("Native connections privacy", .timeLimit(.minutes(1)))
@MainActor
struct NativeConnectionsPrivacyTests {
    @Test func lateOpenFailureCannotCancelANewerRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "morning-native-open-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let service = NativeConnectionsService(directory: directory, defaults: defaults)
        let first = try service.launchShortcut(name: "My Notes", input: "")
        let firstID = try #require(service.pendingShortcut?.id)
        #expect(service.handle(url: try returnURL(from: first, text: "done")))
        _ = try service.launchShortcut(name: "My Mail", input: "")
        let secondID = try #require(service.pendingShortcut?.id)
        service.shortcutCouldNotOpen(requestID: firstID)
        #expect(service.pendingShortcut?.id == secondID)
        service.cancelPendingWork()
    }

    @Test func isolatedWorkspaceCannotReadOrClearAnotherWorkspacesNames() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "morning-native-isolation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: base) }
        let ownerDirectory = base.appendingPathComponent("owner")
        let owner = NativeConnectionsService(directory: ownerDirectory, defaults: defaults)
        try owner.setShortcutName("Owner shortcut", for: .mail)
        let fixture = NativeConnectionsService(directory: base.appendingPathComponent("fixture"), defaults: defaults)
        #expect(fixture.shortcutNames.isEmpty)
        try fixture.setShortcutName("Fixture shortcut", for: .mail)
        try fixture.clearForPrivacy()
        #expect(NativeConnectionsService(directory: ownerDirectory, defaults: defaults).shortcutNames[.mail] == "Owner shortcut")
    }

    @Test func onlyNamesPersistAndForgettingInvalidatesOutstandingCallbacks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "morning-native-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let service = NativeConnectionsService(directory: directory, defaults: defaults)
        try service.setShortcutName("My Notes", for: .notes)
        let url = try service.launchShortcut(name: "My Notes", input: "PRIVATE_QUERY", operation: .notes)
        let callback = try returnURL(from: url, text: "PRIVATE_RESULT")
        #expect(service.handle(url: callback))
        #expect(service.shortcutOutcomes[.notes]?.text == "PRIVATE_RESULT")
        let restored = NativeConnectionsService(directory: directory, defaults: defaults)
        #expect(restored.shortcutNames[.notes] == "My Notes")
        #expect(restored.shortcutOutcomes.isEmpty)
        #expect(!defaults.dictionaryRepresentation().description.contains("PRIVATE_RESULT"))
        #expect(!defaults.dictionaryRepresentation().description.contains("PRIVATE_QUERY"))
        let next = try service.launchShortcut(name: "My Notes", input: "", operation: .notes)
        let oldReturn = try returnURL(from: next, text: "SHOULD_NOT_RETURN")
        let control = LocalDataControl(directory: directory)
        let marker = try control.beginForget()
        await service.quiesce()
        try service.clearForPrivacy()
        try control.finishForget(expectedGeneration: try #require(marker.generation))
        #expect(service.handle(url: oldReturn))
        #expect(service.shortcutOutcomes.isEmpty)
        #expect(service.shortcutNames.isEmpty)
        #expect(NativeConnectionsService(directory: directory, defaults: defaults).shortcutNames.isEmpty)
        await restored.quiesce()
    }

    private func returnURL(from launch: URL, text: String) throws -> URL {
        let components = try #require(URLComponents(url: launch, resolvingAgainstBaseURL: false))
        let value = try #require(components.queryItems?.first { $0.name == "x-success" }?.value)
        var callback = try #require(URLComponents(string: value))
        callback.queryItems?.append(.init(name: "result", value: text))
        return try #require(callback.url)
    }
}
