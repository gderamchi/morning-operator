import MorningApple
import MorningCore
import SwiftUI

struct GoogleCalendarDayMomentView: View {
    @Bindable var store: MorningStore
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 14) {
                Label(french ? "Votre journée" : "Your day", systemImage: "calendar")
                    .font(MorningTheme.Typography.heading)
                if GoogleCalendarDayUITestFixture.isRequested {
                    Text("SYNTHETIC local fixture · no Google account is read or changed")
                        .font(.raleway(.caption)).accessibilityIdentifier("googleCalendarDay.synthetic")
                        .accessibilityValue("HTTP event reads: \(GoogleCalendarDayUITestFixture.eventsReadCount)")
                }
                if store.connectedMoment.isInFlight {
                    ProgressView(french ? "Lecture du calendrier…" : "Reading your calendar…")
                        .accessibilityIdentifier("googleCalendarDay.loading")
                }
                if let document = store.currentGoogleCalendarDay {
                    Text(document.summary()).font(.raleway(.subheadline)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("googleCalendarDay.summary")
                    Text(store.canHearHandsFreeCommands
                         ? (french ? "Jour courant, fuseau de cet iPhone. Posez une question, dites répète ou actualise ce calendrier."
                            : "Today, in this iPhone’s time zone. Ask a question, say repeat or refresh this calendar.")
                         : (french ? "Jour courant, fuseau de cet iPhone. Utilisez les boutons pour relire, actualiser ou poursuivre votre matin."
                            : "Today, in this iPhone’s time zone. Use the buttons to read again, refresh or continue your morning."))
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("googleCalendarDay.controlsHint")
                    Button(french ? "Relire cette journée" : "Read this day again") { _ = store.repeatGoogleCalendarDay() }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("googleCalendarDay.repeat")
                } else if !store.connectedMoment.isInFlight {
                    Text(french ? "Aucune lecture actuelle n’est disponible. Cela ne signifie pas que votre calendrier est vide. Actualisez ce moment ou passez à la suite."
                         : "No current reading is available. This does not mean your calendar is empty. Refresh this moment or go to the next moment.")
                        .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("googleCalendarDay.unavailable")
                }
                Button(french ? "Actualiser ce calendrier" : "Refresh this calendar") { store.refreshGoogleCalendarDay() }
                    .buttonStyle(SecondaryButtonStyle()).disabled(store.connectedMoment.isInFlight)
                    .accessibilityIdentifier("googleCalendarDay.refresh")
            }.accessibilityElement(children: .contain)
                .onChange(of: store.googleCalendarDayDocument?.isCurrent(at: context.date, timeZone: .current), initial: true) { _, _ in
                    store.checkGoogleCalendarDayFreshness()
                }
        }
    }
}
