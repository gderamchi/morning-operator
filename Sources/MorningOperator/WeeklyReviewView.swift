import SwiftUI
import MorningCore

struct WeeklyReviewView: View {
    @Bindable var store: MorningStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(eyebrow: "The last seven mornings", title: "Find your rhythm.",
                            subtitle: "Small moments add up. Here's what your mornings are telling you.")
                if let week = store.weekSummary {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(week.recordedDayCount)").font(.system(size: 54, weight: .light, design: .rounded))
                            Text("of 7 days recorded").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "leaf").font(.title).foregroundStyle(MorningStyle.green)
                        }
                        weekChart(week)
                        Text(week.recordedDayCount < 7 ? "Each morning adds a little clarity. Missing days stay open, not zero." : "A week of mornings, in your own rhythm.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(24).background(MorningStyle.sage.opacity(0.65), in: RoundedRectangle(cornerRadius: 28))
                    HStack(alignment: .top, spacing: 12) {
                        metric("Average routine", value: MorningStyle.duration(week.averageActiveDurationSeconds),
                               detail: "Across \(week.timedRunCount) timed runs")
                        metric("Completed", value: "\(week.completedRunCount)", detail: "\(week.stoppedRunCount) ended early")
                    }
                    Text("Routine timing excludes pauses. It doesn't measure time in other apps or time saved.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Inside your morning").font(.title3.weight(.semibold))
                    if week.apps.isEmpty {
                        EmptyMoment(symbol: "rectangle.stack", title: "Your habits, with context.",
                            detail: "App time, reels and email counts will appear when supported observations are connected. A routine plan alone can't measure them.")
                    } else {
                        ForEach(week.apps) { app in appSummary(app) }
                    }
                    if !store.history.runs.filter(\.isSynthetic).isEmpty {
                        Label("Sample runs are kept out of your personal averages.", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if week.recordedDayCount == 0 {
                        Button("Go to my morning") { store.tab = .today }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("review.week")
    }

    private func metric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded, weight: .medium)).minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func weekChart(_ week: SevenDaySummary) -> some View {
        let highest = max(week.days.compactMap(\.totalActiveDurationSeconds).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(week.days) { day in
                VStack(spacing: 10) {
                    if let duration = day.totalActiveDurationSeconds {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(MorningStyle.green.opacity(0.65))
                            .frame(height: max(6, 76 * duration / highest))
                            .frame(height: 80, alignment: .bottom)
                    } else {
                        VStack { Spacer(); Circle().strokeBorder(MorningStyle.green.opacity(0.3), lineWidth: 1).frame(width: 7, height: 7) }
                            .frame(height: 80)
                    }
                    Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))): \(day.totalActiveDurationSeconds == nil ? "not recorded" : MorningStyle.duration(day.totalActiveDurationSeconds))")
            }
        }
    }

    private func appSummary(_ app: AppUsageSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(app.appName).font(.headline); Spacer(); Text(MorningStyle.duration(app.averageObservedDurationSeconds)).font(.headline) }
                Text("Average observed time · \(app.daysWithDurationEvidence) days with time evidence").font(.caption).foregroundStyle(.secondary)
                countLine("Reels viewed", app.reelsViewed)
                countLine("Likes", app.likes)
                countLine("Emails read", app.emailsRead)
                countLine("Emails replied to", app.emailsReplied)
                Text("\(app.completeWindowDayCount) complete windows · \(app.partialWindowDayCount) partial windows")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func countLine(_ title: String, _ count: CountSummary) -> some View {
        if let average = count.averagePerEvidenceDay {
            HStack { Text(title); Spacer(); Text(average.formatted(.number.precision(.fractionLength(0...1)))) }
                .font(.subheadline)
            Text("Average across \(count.daysWithEvidence) days with evidence").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
