import MorningApple
import MorningCore
import SwiftUI

struct CalendlyDayMomentView: View {
    @Bindable var store: MorningStore
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 14) {
                Label(french ? "Vos rendez-vous" : "Your bookings", systemImage: "calendar")
                    .font(MorningTheme.Typography.heading)
                if CalendlyDayUITestFixture.isRequested {
                    Text("SYNTHETIC local fixture · no Calendly account is read or changed")
                        .font(.raleway(.caption)).accessibilityIdentifier("calendlyDay.synthetic")
                        .accessibilityValue("HTTP event reads: \(CalendlyDayUITestFixture.eventsReadCount)")
                }
                if store.connectedMoment.isInFlight {
                    ProgressView(french ? "Lecture des rendez-vous…" : "Reading your bookings…")
                        .accessibilityIdentifier("calendlyDay.loading")
                }
                if let document = store.currentCalendlyDay {
                    Text(document.summary()).font(.raleway(.subheadline)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("calendlyDay.summary")
                    Text(french ? "Rendez-vous qui commencent aujourd’hui, dans le fuseau de cet iPhone. Posez une question, dites répète ou actualise mes rendez-vous."
                         : "Bookings starting today, in this iPhone’s time zone. Ask a question, say repeat or refresh my bookings.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                    Button(french ? "Relire ces rendez-vous" : "Read these bookings again") { _ = store.repeatCalendlyDay() }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("calendlyDay.repeat")
                } else if !store.connectedMoment.isInFlight {
                    Text(french ? "Aucune lecture actuelle n’est disponible. Cela ne signifie pas que vous n’avez aucun rendez-vous. Actualisez ce moment ou dites suivant."
                         : "No current reading is available. This does not mean you have no bookings. Refresh this moment or say next.")
                        .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("calendlyDay.unavailable")
                }
                Button(french ? "Actualiser mes rendez-vous" : "Refresh my bookings") { store.refreshCalendlyDay() }
                    .buttonStyle(SecondaryButtonStyle()).disabled(store.connectedMoment.isInFlight)
                    .accessibilityIdentifier("calendlyDay.refresh")
            }.accessibilityElement(children: .contain)
                .onChange(of: store.calendlyDayDocument?.isCurrent(at: context.date, timeZone: .current), initial: true) { _, _ in
                    store.checkCalendlyDayFreshness()
                }
        }
    }
}
