import SwiftUI
import MorningApple

struct MorningHealthView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MorningForm { MorningHealthSection(store: store) }
                .scrollContentBackground(.hidden)
                .background(MorningStyle.background)
                .navigationTitle(MorningPermissionSetup.text("Health", "Santé"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .disabled(store.privacyBlocksWork)
                .task { await store.prepareDayIfConfigured() }
        }
        .tint(MorningStyle.accent)
    }
}

/// The same connection is reachable directly in Settings and beside the day's sources.
struct MorningHealthSection: View {
    @Bindable var store: MorningStore
    var stopPreview: () -> Void = {}
    private var controller: MorningBriefingController { store.briefing }
    private func text(_ english: String, _ french: String) -> String { MorningPermissionSetup.text(english, french) }

    var body: some View {
        Section {
            Toggle(text("Health in my morning", "La santé dans mon matin"), isOn: Binding(
                get: { controller.settings.includesHealth },
                set: { included in
                    stopPreview()
                    if included { connect() } else { store.disableHealthInBriefing() }
                }))
                .disabled(controller.isConnectingHealth || (store.sessionActive && !controller.settings.includesHealth))
                .accessibilityIdentifier("briefing.healthIncluded")
            if controller.isConnectingHealth {
                ProgressView(text("Opening Apple Health…", "Ouverture de Santé Apple…"))
                Button("Cancel", role: .cancel) { store.disableHealthInBriefing() }
            }
            if let issue = controller.healthConnectionIssue {
                Text(issue).foregroundStyle(MorningStyle.muted).accessibilityIdentifier("briefing.healthError")
            }
            if controller.settings.includesHealth {
                if !controller.settings.includesHealthMetrics {
                    Button(text("Connect heart and breathing data", "Ajouter les mesures cardiaques et respiratoires")) { connect() }
                        .disabled(store.sessionActive || controller.isConnectingHealth)
                        .accessibilityIdentifier("briefing.expandHealth")
                }
                if let document = controller.prepared {
                    sleepSummary(document.sleep)
                    ForEach(document.healthMetrics) { item in
                        if item.section.status == .fresh {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.section.segments.map(\.text).joined(separator: " "))
                                if let source = item.observation?.source.name {
                                    Text(source).font(.caption).foregroundStyle(MorningStyle.muted)
                                }
                            }.accessibilityIdentifier("briefing.health.\(item.metric.rawValue)")
                        }
                    }
                    DisclosureGroup(text("Sources and access", "Sources et accès")) {
                        MorningSleepDetailsView(section: document.sleep)
                        ForEach(document.healthMetrics) { item in
                            Text(item.section.statusText).font(.caption)
                            if let sample = item.observation {
                                Text(sample.end.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
                            }
                        }
                        accessDetails
                    }.font(.footnote).foregroundStyle(MorningStyle.muted)
                }
                Button(text("Refresh Health", "Actualiser Santé")) {
                    stopPreview()
                    Task { _ = await controller.refresh(force: true) }
                }.disabled(controller.isPreparing).accessibilityIdentifier("briefing.refreshSleep")
            } else {
                Text(text("Sleep, heart rate and breathing from the apps you allow in Apple Health.",
                          "Sommeil, rythme cardiaque et respiration des apps autorisées dans Santé Apple."))
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
                DisclosureGroup(text("What is shared?", "Qu’est-ce qui est partagé ?")) { accessDetails }
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
        } header: { Text(text("Apple Health", "Santé Apple")) }
        footer: { Text(text("Read only. No automatic sharing.", "Lecture seule. Aucun partage automatique.")) }
    }

    private func connect() {
        stopPreview()
        Task { if await controller.enableHealth(includeMetrics: true) { await store.prepareDayIfConfigured() } }
    }

    @ViewBuilder private func sleepSummary(_ section: MorningBriefingSection) -> some View {
        if section.status == .fresh {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.segments.map(\.text).joined(separator: " "))
                    .accessibilityIdentifier("briefing.sleep")
                if !section.sourceLabels.isEmpty {
                    Text(section.sourceLabels.joined(separator: " · ")).font(.caption).foregroundStyle(MorningStyle.muted)
                }
            }
        } else if section.issue == .noRecord || section.issue == .olderRecord {
            Text(text("No recent sleep available. Sync your tracker, then refresh.",
                      "Aucun sommeil récent disponible. Synchronisez votre tracker, puis actualisez."))
                .font(.subheadline).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("briefing.sleep")
        } else {
            Text(section.statusText).font(.subheadline).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("briefing.sleep")
        }
    }

    private var accessDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("You choose access to sleep, resting heart rate, heart rate variability (SDNN) and breathing rate in Apple’s sheet.",
                      "Vous choisissez dans la demande Apple l’accès au sommeil, à la fréquence cardiaque au repos, à sa variabilité (SDNN) et à la fréquence respiratoire."))
            Text(text("MORE reads what your apps write to Health. A tracker’s recovery score is available only if that source provides it through a supported connection.",
                      "MORE lit les mesures que vos apps écrivent dans Santé. Le score de récupération d’un tracker nécessite une connexion qui fournit réellement ce score."))
            Text(text("Change access in Apple Health → profile → Apps → MORE. An empty result can mean no synced data or no reading access.",
                      "Modifiez les accès dans Santé Apple → profil → Apps → MORE. Un résultat vide peut signifier une absence de données synchronisées ou d’accès en lecture."))
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
