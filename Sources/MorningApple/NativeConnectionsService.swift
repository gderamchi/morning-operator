import Foundation
import MorningCore
import Observation

/// Semantic notices keep their failure/receipt meaning when the interface language changes.
enum NativeConnectionNotice {
    case failure(any Error), shortcutCouldNotOpen, stoppedWaiting, remindersTimedOut, reminderCompleted

    func text(locale: Locale = AppLanguage.locale) -> String {
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        switch self {
        case .failure(let error): return error.moreDescription
        case .shortcutCouldNotOpen: return AppLanguage.localized("Shortcuts couldn't open. Check that it is installed and the shortcut name is correct.", bundle: bundle, locale: locale)
        case .stoppedWaiting: return AppLanguage.localized("MORE stopped waiting. The shortcut may still be running; check its outcome before running it again.", bundle: bundle, locale: locale)
        case .remindersTimedOut: return AppLanguage.localized("Reminders didn't answer in time. Try reading them again.", bundle: bundle, locale: locale)
        case .reminderCompleted: return AppLanguage.localized("Marked complete in Apple Reminders.", bundle: bundle, locale: locale)
        }
    }
}

/// One owner for native snapshots and named Shortcuts. Only shortcut names persist.
@MainActor @Observable
public final class NativeConnectionsService {
    public private(set) var shortcutNames: [NativeShortcutOperation: String] = [:]
    public private(set) var shortcutOutcomes: [NativeShortcutOperation: ShortcutBridgeOutcome] = [:]
    private var shortcutNotice: NativeConnectionNotice?
    public var shortcutMessage: String? { shortcutNotice?.text() }
    public private(set) var reminders: [ReminderSummary] = []
    public private(set) var remindersReadAt: Date?
    public private(set) var remindersBusy = false
    private var reminderNotice: NativeConnectionNotice?
    public var reminderMessage: String? { reminderNotice?.text() }
    public var pendingShortcut: ShortcutBridgeRequest? { bridge.pending }
    public var reminderAuthorization: EventKitAccess { reminderService.reminderAuthorization }
    public var hasReminderAccess: Bool { reminderService.hasReminderAccess }
    public var callbackScheme: String { scheme }
    @ObservationIgnored private let reminderService: ReminderService
    @ObservationIgnored private let control: LocalDataControl
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let scheme: String
    @ObservationIgnored private var generation: UUID?
    private var bridge: ShortcutBridge
    @ObservationIgnored private var shortcutDeadline: Task<Void, Never>?
    @ObservationIgnored private var reminderTask: Task<Void, Never>?
    @ObservationIgnored private var reminderDeadline: Task<Void, Never>?
    @ObservationIgnored private var reminderAttempt: UUID?
    @ObservationIgnored private let namesKey: String

    public init(directory: URL = LocalDataControl.defaultDirectory,
                callbackScheme: String = Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "more",
                defaults: UserDefaults = .standard) {
        control = LocalDataControl(directory: directory)
        self.defaults = defaults; scheme = callbackScheme
        namesKey = "morning.nativeShortcutNames.v1.\(directory.standardizedFileURL.path)"
        bridge = ShortcutBridge(callbackScheme: callbackScheme)
        reminderService = ReminderService()
        do {
            try control.withReadyAccess { state in
                generation = state.generation
                for (key, name) in defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:] {
                    if let operation = NativeShortcutOperation(rawValue: key), ShortcutBridge.isValidName(name) {
                        shortcutNames[operation] = name
                    }
                }
            }
        } catch { shortcutNotice = .failure(error) }
    }

    public func setShortcutName(_ name: String, for operation: NativeShortcutOperation) throws {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty || ShortcutBridge.isValidName(value) else { throw ShortcutBridgeError.invalidName }
        try withReadyAccess {
            var next = shortcutNames
            next[operation] = value.isEmpty ? nil : value
            defaults.set(Dictionary(uniqueKeysWithValues: next.map { ($0.key.rawValue, $0.value) }), forKey: namesKey)
            shortcutNames = next; shortcutOutcomes[operation] = nil; shortcutNotice = nil
        }
    }

    public func launchShortcut(name: String, input: String, operation: NativeShortcutOperation = .custom) throws -> URL {
        try withReadyAccess {
            if bridge.expire() { shortcutNotice = .failure(ShortcutBridgeError.expired) }
            let request = try bridge.begin(name: name, input: input, operation: operation)
            shortcutOutcomes[operation] = nil; shortcutNotice = nil
            shortcutDeadline?.cancel()
            shortcutDeadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(ShortcutBridge.timeout)) } catch { return }
                guard let self, self.bridge.pending?.id == request.id else { return }
                self.bridge.cancel()
                self.shortcutNotice = .failure(ShortcutBridgeError.expired)
            }
            return request.launchURL
        }
    }

    @discardableResult public func handle(url: URL) -> Bool {
        guard bridge.recognizes(url) else { return false }
        do {
            try withReadyAccess {
                let outcome = try bridge.accept(url)
                shortcutDeadline?.cancel(); shortcutDeadline = nil
                shortcutOutcomes[outcome.operation] = outcome; shortcutNotice = nil
            }
        } catch { shortcutNotice = .failure(error) }
        return true
    }

    public func shortcutCouldNotOpen(requestID: UUID? = nil) {
        if let requestID, bridge.pending?.id != requestID { return }
        bridge.cancel(); shortcutDeadline?.cancel(); shortcutDeadline = nil
        shortcutNotice = .shortcutCouldNotOpen
    }

    public func refreshAccess() {
        if bridge.expire() { shortcutNotice = .failure(ShortcutBridgeError.expired) }
        if !hasReminderAccess { reminders = []; remindersReadAt = nil }
    }

    public func stopWaitingForShortcut() {
        bridge.cancel(); shortcutDeadline?.cancel(); shortcutDeadline = nil
        shortcutNotice = .stoppedWaiting
    }

    public func readUpcomingReminders() {
        guard !remindersBusy else { return }
        do { try withReadyAccess { } } catch { reminderNotice = .failure(error); return }
        let attempt = UUID()
        reminderAttempt = attempt; remindersBusy = true; reminderNotice = nil
        reminders = []; remindersReadAt = nil
        reminderTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if reminderAttempt == attempt { reminderAttempt = nil; remindersBusy = false; reminderTask = nil }
            }
            do {
                try await reminderService.requestReminderAccess()
                try Task.checkCancellation(); try withReadyAccess { }
                guard reminderAttempt == attempt else { return }
                reminderDeadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    guard let self, self.reminderAttempt == attempt else { return }
                    self.cancelReminderRead()
                    self.reminderNotice = .remindersTimedOut
                }
                let values = try await reminderService.fetchUpcomingReminders(limit: 50)
                try Task.checkCancellation(); try withReadyAccess { }
                guard reminderAttempt == attempt else { return }
                reminderDeadline?.cancel(); reminderDeadline = nil
                reminders = values; remindersReadAt = Date()
            } catch {
                guard reminderAttempt == attempt else { return }
                reminderDeadline?.cancel(); reminderDeadline = nil
                if !(error is CancellationError) { reminderNotice = .failure(error) }
            }
        }
    }

    public func completeReminder(_ reminder: ReminderSummary) {
        do {
            try withReadyAccess {
                guard !remindersBusy, reminders.contains(reminder), let readAt = remindersReadAt,
                      (0..<300).contains(Date().timeIntervalSince(readAt)) else { throw ReminderServiceError.reminderChanged }
                try reminderService.completeReminder(reminder)
                reminders.removeAll { $0.id == reminder.id }
                reminderNotice = .reminderCompleted
            }
        } catch {
            reminders = []; remindersReadAt = nil
            reminderNotice = .failure(error)
        }
    }

    /// An uncancellable EventKit read may finish later; invalidated attempts cannot publish.
    private func cancelReminderRead() {
        reminderAttempt = nil; reminderTask?.cancel(); reminderTask = nil
        reminderDeadline?.cancel(); reminderDeadline = nil; remindersBusy = false
    }
    public func cancelPendingWork() {
        cancelReminderRead(); bridge.cancel(); shortcutDeadline?.cancel(); shortcutDeadline = nil
        reminders = []; remindersReadAt = nil; shortcutOutcomes = [:]
        shortcutNotice = nil; reminderNotice = nil
    }
    public func quiesce() async { cancelPendingWork() }
    public func clearForPrivacy() throws {
        cancelPendingWork(); shortcutNames = [:]; defaults.removeObject(forKey: namesKey)
        generation = try control.status().generation
    }
    private func withReadyAccess<T>(_ body: () throws -> T) throws -> T {
        try control.withReadyAccess { state in
            guard state.generation == generation else { throw LocalDataControlError.staleGeneration }
            return try body()
        }
    }
}
