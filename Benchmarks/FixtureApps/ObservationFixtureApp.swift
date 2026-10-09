import SwiftUI

/// Two separately installed, test-only apps share this source. All content is invented;
/// there are no accounts, network calls, external stores, permissions or write actions.
@main
struct ObservationFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                FixtureListView()
                    .navigationDestination(for: FixtureItem.self) { FixtureDetailView(item: $0) }
            }
            .tint(FixtureContent.tint)
        }
    }
}

private struct FixtureItem: Identifiable, Hashable {
    let index: Int
    let title: String
    let subtitle: String
    let preview: String
    var id: String { String(format: "%02d", index) }
}

private enum FixtureContent {
    #if FIXTURE_INBOX
    static let title = "Cedar Mail"
    static let listTitle = "Inbox"
    static let detailKind = "Synthetic message"
    static let tint: Color = .indigo
    static let symbol = "envelope"
    static let items = (1...30).map { index in
        let subjects = ["Weekend garden plans", "A quiet reading afternoon", "Notes for the sketchbook",
                        "Saturday picnic ideas", "A walk by the river", "Library opening hours"]
        let senders = ["Juniper", "Maya", "Robin", "Alex", "Taylor", "Sam"]
        return FixtureItem(index: index, title: "\(subjects[(index - 1) % subjects.count]) · \(index)",
                           subtitle: "\(senders[(index - 1) % senders.count]) · Sample mail \(index)",
                           preview: "A small fictional note, saved here for a controlled screen observation.")
    }
    static func body(for item: FixtureItem) -> String {
        "Hello,\n\nThis is invented message \(item.id) in Cedar Mail. Let's bring a notebook on our next walk and sketch a tree beside the river. There is no account connected and no reply to send.\n\nHave a peaceful morning."
    }
    #elseif FIXTURE_CALENDAR
    static let title = "Lumen Calendar"
    static let listTitle = "Saturday agenda"
    static let detailKind = "Synthetic event"
    static let tint: Color = .teal
    static let symbol = "calendar"
    static let items = (1...30).map { index in
        let subjects = ["Morning walk", "Reading hour", "Sketchbook time", "Garden break", "Quiet planning", "Tea by the window"]
        let minute = 7 * 60 + (index - 1) * 20
        let time = String(format: "%02d:%02d", minute / 60, minute % 60)
        return FixtureItem(index: index, title: "\(subjects[(index - 1) % subjects.count]) · \(index)",
                           subtitle: "\(time) · Sample event \(index)",
                           preview: "A fictional twenty-minute activity in this local demonstration agenda.")
    }
    static func body(for item: FixtureItem) -> String {
        "Event \(item.id) is a fictional entry for this observation benchmark.\n\nBring a notebook and take a quiet break. No calendar account is connected. This screen cannot create, edit or invite anyone to an event."
    }
    #else
    #error("Build this source only in a benchmark fixture target with FIXTURE_INBOX or FIXTURE_CALENDAR.")
    #endif
}

private struct FixtureHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: FixtureContent.symbol).accessibilityHidden(true)
                Text(FixtureContent.title).accessibilityIdentifier("benchmark.heading")
            }
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .foregroundStyle(FixtureContent.tint)
            Text("Benchmark fixture · Synthetic content only")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.vertical, 14)
    }
}

private struct FixtureListView: View {
    var body: some View {
        VStack(spacing: 0) {
            FixtureHeader()
            HStack {
                Text(FixtureContent.listTitle).font(.title2.bold())
                Spacer()
                Text("30 items").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(FixtureContent.items) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline).foregroundStyle(.primary)
                                Text(item.subtitle).font(.subheadline).foregroundStyle(FixtureContent.tint)
                                Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("benchmark.row.\(item.id)")
                        Divider().padding(.leading, 22)
                    }
                }
            }
            .accessibilityIdentifier("benchmark.list")
        }
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FixtureDetailView: View {
    let item: FixtureItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FixtureHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(FixtureContent.detailKind) \(item.id)")
                        .font(.subheadline).foregroundStyle(FixtureContent.tint)
                        .accessibilityIdentifier("benchmark.detail.kind")
                    Text(item.title).font(.title.bold())
                        .accessibilityIdentifier("benchmark.detail.title")
                    Text(item.subtitle).font(.headline).foregroundStyle(.secondary)
                    Divider()
                    Text(FixtureContent.body(for: item)).font(.body).lineSpacing(7)
                        .accessibilityIdentifier("benchmark.detail.body")
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("benchmark.detail")
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") { dismiss() }
                    .accessibilityIdentifier("benchmark.back")
            }
        }
    }
}
