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
    private(set) var problem: String?
    private(set) var reading = false
    private(set) var readAt: Date?
    private(set) var resultCount = 0
    private(set) var rowCount = 0
    private(set) var streamFinished = false
    private var readTask: Task<Void, Never>?

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
        guard let window = ScreenTimeMorningSummary.morningWindow(on: .now, startHour: startHour, endHour: endHour) else {
            problem = "The \(startHour):00–\(endHour):00 window has not started yet today."; return
        }
        problem = nil; reading = true; streamFinished = false; resultCount = 0; rowCount = 0
        readTask = Task { [weak self] in
            let query = Self.hourAligned(window)
            let filter = DeviceActivityFilter(segment: .hourly(during: query), devices: .init([.iPhone]))
            var rows: [ScreenTimeUsageRow] = []
            var pickups: [Date] = []
            var updated: [Date] = []
            do {
                for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
                    updated.append(data.lastUpdatedDate)
                    for await segment in data.activitySegments {
                        if let first = segment.firstPickup { pickups.append(first) }
                        for await category in segment.categories {
                            for await activity in category.applications {
                                let app = activity.application
                                rows.append(ScreenTimeUsageRow(
                                    segment: segment.dateInterval,
                                    appName: app.localizedDisplayName ?? app.bundleIdentifier ?? "Unnamed app",
                                    bundleIdentifier: app.bundleIdentifier, seconds: activity.totalActivityDuration,
                                    pickups: activity.numberOfPickups, notifications: activity.numberOfNotifications))
                            }
                        }
                    }
                    // The sequence may stay open for updates; show each result as it arrives.
                    self?.publish(rows: rows, window: window, pickups: pickups, updated: updated)
                }
                self?.finish(problem: nil)
            } catch is CancellationError {
                self?.finish(problem: nil)
            } catch {
                self?.finish(problem: "Activity data: \(error.localizedDescription) [\(String(describing: error))]")
            }
        }
    }

    func cancel() { readTask?.cancel() }

    private func publish(rows: [ScreenTimeUsageRow], window: DateInterval, pickups: [Date], updated: [Date]) {
        resultCount = updated.count
        rowCount = rows.count
        readAt = .now
        summary = ScreenTimeMorningSummary.summarize(
            rows: rows, window: window, firstPickups: pickups, lastUpdated: updated,
            excludingBundleIdentifiers: [Bundle.main.bundleIdentifier ?? ""])
    }

    private func finish(problem: String?) {
        reading = false
        streamFinished = true
        if let problem { self.problem = problem }
        if readAt == nil { readAt = .now }
    }

    /// Hourly segments start on the hour; widen the query so the first hour is whole.
    nonisolated private static func hourAligned(_ window: DateInterval) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .hour, for: window.start)?.start ?? window.start
        return DateInterval(start: start, end: max(window.end, start.addingTimeInterval(60)))
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
        .onDisappear { model.cancel() }
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
