#if DEBUG && os(iOS)
import DeviceActivity
import FamilyControls
import ManagedSettings
import MorningCore
import SwiftUI

/// Debug-only spike (docs/SEAMLESS-LEARNING.md): read this morning's per-app minutes from
/// Screen Time with the App and Website Usage data access. Nothing is saved or logged;
/// the result lives in memory while this screen is open.
@MainActor @Observable
final class ScreenTimeSpikeModel {
    var startHour = 5
    var endHour = 11
    private(set) var statusText = ""
    private(set) var summary: ScreenTimeMorningSummary?
    private(set) var detection: MorningDetectionResult?
    /// Per-hour evidence of the last read, for the spike export only.
    private(set) var hourLines: [String] = []
    private(set) var problem: String?
    private(set) var reading = false
    private(set) var readAt: Date?
    private(set) var resultCount = 0
    private(set) var rowCount = 0
    private(set) var streamFinished = false
    private var readTask: Task<Void, Never>?
    /// Each read has its own number; a cancelled or replaced read cannot publish or finish.
    private var generation = 0

    /// `--screen-time-spike-auto` (Debug launch argument): open this screen at launch, ask for
    /// access if needed, read once and write the summary to the app's temporary folder so a
    /// tethered Mac can copy it during the spike. The file is overwritten on each run.
    static let autoRunRequested = ProcessInfo.processInfo.arguments.contains("--screen-time-spike-auto")
    static var exportURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("screen-time-spike.txt") }

    func autoRun() async {
        refreshStatus()
        if #available(iOS 26.4, *), AuthorizationCenter.shared.authorizationStatus != .approvedWithDataAccess {
            await requestAccess()
        }
        read()
    }

    private func export(_ text: String) {
        guard Self.autoRunRequested else { return }
        try? Data(text.utf8).write(to: Self.exportURL, options: [.atomic, .completeFileProtection])
    }

    func refreshStatus() {
        let status = AuthorizationCenter.shared.authorizationStatus
        statusText = switch status {
        case .notDetermined: "Not asked yet"
        case .denied: "Denied"
        case .approved: "Approved, without data access (app names are hidden)"
        default:
            if #available(iOS 26.4, *), status == .approvedWithDataAccess { "Approved with data access" }
            else { "Unknown (\(status.rawValue))" }
        }
    }

    func requestAccess() async {
        problem = nil
        do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual) }
        catch { problem = "Authorization: \(error.localizedDescription) [\(String(describing: error))]" }
        refreshStatus()
    }

    func read() {
        readTask?.cancel()
        guard #available(iOS 26.4, *) else { problem = "Needs iOS 26.4 or later."; return }
        // Read from 18:00 yesterday so a sleep gap before this morning is covered (owner's rule:
        // the morning starts at the first use after three hours without use).
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let coveredFrom = calendar.date(byAdding: .hour, value: -6, to: today) else { return }
        let fallback = ScreenTimeMorningSummary.morningWindow(on: .now, startHour: startHour, endHour: endHour)
        generation += 1
        let token = generation
        problem = nil; reading = true; streamFinished = false; resultCount = 0; rowCount = 0
        summary = nil; detection = nil; readAt = nil; hourLines = []
        readTask = Task { [weak self] in
            let query = DateInterval(start: coveredFrom, end: .now)
            let filter = DeviceActivityFilter(segment: .hourly(during: query), devices: .init([.iPhone]))
            var rows: [ScreenTimeUsageRow] = []
            var pickups: [Date] = []
            var updated: [Date] = []
            var uses: [PhoneUse] = []
            // With data access, installed apps carry real display names (names in usage rows may be nil).
            let names = await Self.installedAppNames()
            do {
                for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
                    updated.append(data.lastUpdatedDate)
                    for await segment in data.activitySegments {
                        if let first = segment.firstPickup { pickups.append(first) }
                        var segmentSeconds: TimeInterval = 0
                        var detail: [String] = []
                        for await category in segment.categories {
                            let categoryName = category.category.localizedDisplayName ?? "?"
                            for await web in category.webDomains where web.totalActivityDuration > 0 {
                                detail.append("  web: \(web.webDomain.domain ?? "?") \(Int(web.totalActivityDuration)) s [\(categoryName)]")
                            }
                            for await activity in category.applications {
                                let app = activity.application
                                let shownName = app.localizedDisplayName ?? app.bundleIdentifier.flatMap { names[$0] } ?? app.bundleIdentifier ?? "Unnamed app"
                                detail.append("  app: \(shownName) (\(app.bundleIdentifier ?? "-")) \(Int(activity.totalActivityDuration)) s pickups=\(activity.numberOfPickups) notifications=\(activity.numberOfNotifications) [\(categoryName)] rowName=\(app.localizedDisplayName ?? "nil")")
                                if app.bundleIdentifier != Bundle.main.bundleIdentifier { segmentSeconds += activity.totalActivityDuration }
                                rows.append(ScreenTimeUsageRow(
                                    segment: segment.dateInterval,
                                    appName: shownName,
                                    bundleIdentifier: app.bundleIdentifier, seconds: activity.totalActivityDuration,
                                    pickups: activity.numberOfPickups, notifications: activity.numberOfNotifications))
                            }
                        }
                        let hourLine = "hour: \(segment.dateInterval.start) total=\(Int(segmentSeconds)) s firstPickup=\(segment.firstPickup.map { "\($0)" } ?? "-") longest=\(segment.longestActivity.map { "\($0.start)+\(Int($0.duration))s" } ?? "-")"
                        self?.hourLines.append(hourLine + " pickupsWithoutApp=\(segment.totalPickupsWithoutApplicationActivity) segmentTotal=\(Int(segment.totalActivityDuration)) s")
                        self?.hourLines += detail
                        uses += PhoneUse.fromScreenTimeSegment(hour: segment.dateInterval, totalSeconds: segmentSeconds,
                                                               firstPickup: segment.firstPickup, longestActivity: segment.longestActivity,
                                                               sessionGap: MorningDetectionPolicy().sessionGap)
                    }
                    // The sequence may stay open for updates; show each result as it arrives.
                    let detected = MorningStartDetector.detect(uses: uses, on: .now, coveredFrom: coveredFrom)
                    guard !Task.isCancelled else { break }
                    self?.publish(token: token, rows: rows, detection: detected, fallback: fallback, pickups: pickups, updated: updated)
                }
                self?.finish(token: token, problem: nil)
            } catch is CancellationError {
                self?.finish(token: token, problem: nil)
            } catch {
                self?.finish(token: token, problem: "Activity data: \(error.localizedDescription) [\(String(describing: error))]")
            }
        }
    }

    func cancel() { readTask?.cancel() }

    @available(iOS 26.4, *)
    nonisolated private static func installedAppNames() async -> [String: String] {
        guard let installed = try? await FamilyActivityData.shared.installedApplications else { return [:] }
        var names: [String: String] = [:]
        for app in installed { if let id = app.bundleIdentifier, let name = app.localizedDisplayName { names[id] = name } }
        return names
    }

    /// Plain summary for the spike export: status, detected morning, apps and minutes.
    var exportText: String {
        var lines = ["status: \(statusText)", "readAt: \(readAt.map { "\($0)" } ?? "-")"]
        if let problem { lines.append("problem: \(problem)") }
        switch detection {
        case .found(let m)?:
            lines.append("morning: \(m.start) – \(m.end) end=\(m.endReason.rawValue) skipped=\(m.skippedSessions.map { "\($0.start)" }) sleepHint=\(m.usedSleepHint)")
        case let other?: lines.append("morning: \(other)")
        case nil: lines.append("morning: not read")
        }
        if let summary {
            lines.append("window: \(summary.window.start) – \(summary.window.end) outsideWindow=\(summary.includesTimeOutsideWindow) firstPickup=\(summary.firstPickup.map { "\($0)" } ?? "-") lastUpdated=\(summary.lastUpdated.map { "\($0)" } ?? "-")")
            for app in summary.appsInFirstUseOrder {
                lines.append("app: \(app.name) | \(Int(app.seconds)) s | firstHour=\(app.firstSegmentStart) pickups=\(app.pickups) notifications=\(app.notifications)")
            }
        }
        lines += hourLines
        lines.append("results=\(resultCount) rows=\(rowCount) finished=\(streamFinished)")
        return lines.joined(separator: "\n")
    }

    private func publish(token: Int, rows: [ScreenTimeUsageRow], detection: MorningDetectionResult, fallback: DateInterval?,
                         pickups: [Date], updated: [Date]) {
        guard token == generation else { return }
        self.detection = detection
        let window: DateInterval
        if case .found(let morning) = detection { window = morning.interval }
        else if let fallback { window = fallback }
        else { problem = "No morning detected and the fixed window has not started."; return }
        defer { export(exportText) }
        resultCount = updated.count
        rowCount = rows.count
        readAt = .now
        summary = ScreenTimeMorningSummary.summarize(
            rows: rows, window: window, firstPickups: pickups, lastUpdated: updated,
            excludingBundleIdentifiers: [Bundle.main.bundleIdentifier ?? ""])
    }

    private func finish(token: Int, problem: String?) {
        guard token == generation else { return }
        reading = false
        streamFinished = true
        if let problem { self.problem = problem }
        if readAt == nil { readAt = .now }
        export(exportText)
    }
}

struct ScreenTimeSpikeView: View {
    @State private var model = ScreenTimeSpikeModel()

    var body: some View {
        Form {
            Section {
                LabeledContent { Text(verbatim: model.statusText) } label: { Text(verbatim: "Screen Time access") }
                    .accessibilityIdentifier("screenTime.status")
                Button { Task { await model.requestAccess() } } label: { Text(verbatim: "Allow Screen Time access") }
                    .accessibilityIdentifier("screenTime.request")
            } footer: {
                Text(verbatim: "Debug spike. Asks once (Face ID). Reads minutes per app; nothing leaves the phone or is saved.")
            }
            Section {
                Text(verbatim: detectionText).font(.footnote).accessibilityIdentifier("screenTime.detection")
                Stepper(value: $model.startHour, in: 0...22) { Text(verbatim: "From \(model.startHour):00") }
                Stepper(value: $model.endHour, in: 1...24) { Text(verbatim: "To \(model.endHour):00") }
                Button { model.read() } label: { Text(verbatim: model.reading ? "Reading…" : "Read this morning") }
                    .accessibilityIdentifier("screenTime.read")
                if model.reading { Button(role: .cancel) { model.cancel() } label: { Text(verbatim: "Stop reading") } }
            }
            if let problem = model.problem {
                Section { Text(verbatim: problem).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("screenTime.problem") }
            }
            if let summary = model.summary {
                Section {
                    if summary.isEmpty {
                        Text(verbatim: "No usage returned for this window (no data, not zero use).")
                    }
                    ForEach(summary.apps) { app in
                        HStack {
                            Text(verbatim: app.name)
                            Spacer()
                            Text(verbatim: app.seconds < 30 ? "< 1 min" : "≈ \(app.roundedMinutes) min")
                                .monospacedDigit()
                        }
                        .accessibilityIdentifier("screenTime.app")
                    }
                } header: {
                    Text(verbatim: "This morning, longest first")
                } footer: {
                    Text(verbatim: footer(summary)).accessibilityIdentifier("screenTime.footer")
                }
                Section {
                    Text(verbatim: summary.appsInFirstUseOrder.map {
                        "\($0.firstSegmentStart.formatted(date: .omitted, time: .shortened)) \($0.name)"
                    }.joined(separator: "\n")).font(.footnote)
                } header: { Text(verbatim: "Coarse order (hour of first use)") }
            }
        }
        .navigationTitle(Text(verbatim: "Screen Time spike"))
        .onAppear { model.refreshStatus() }
        .task { if ScreenTimeSpikeModel.autoRunRequested { await model.autoRun() } }
        .onDisappear { model.cancel() }
    }

    private var detectionText: String {
        switch model.detection {
        case nil: return "Morning: the first use after 3 h without use; ends after a 20 min pause or 3 h. Fixed hours below are the fallback."
        case .noData?: return "Morning: no use found today; using the fixed hours."
        case .noSleepGapCovered?: return "Morning: no 3 h gap without use is covered; using the fixed hours."
        case .found(let m)?:
            let f = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
            var text = "Morning: \(f(m.start))–\(f(m.end)) (\(m.endReason.rawValue))"
            if !m.skippedSessions.isEmpty { text += ", skipped \(m.skippedSessions.map { f($0.start) }.joined(separator: ", "))" }
            return text + ". Hourly data: minutes are whole hours overlapping it."
        }
    }

    private func footer(_ summary: ScreenTimeMorningSummary) -> String {
        var parts = ["Total ≈ \(Int((summary.totalSeconds / 60).rounded())) min across \(summary.apps.count) apps."]
        if let first = summary.firstPickup { parts.append("First pickup \(first.formatted(date: .omitted, time: .shortened)).") }
        if let updated = summary.lastUpdated { parts.append("Data as of \(updated.formatted(date: .omitted, time: .standard)).") }
        if summary.includesTimeOutsideWindow { parts.append("Hourly data: the first hour may include use before the window.") }
        parts.append("\(model.resultCount) result(s), \(model.rowCount) rows, stream \(model.streamFinished ? "finished" : "open").")
        return parts.joined(separator: " ")
    }
}
#endif
