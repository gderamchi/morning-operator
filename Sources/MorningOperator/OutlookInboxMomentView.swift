import MorningApple
import MorningCore
import SwiftUI

/// Previews and a selected inert body stay separate; no remote resources or writes.
struct OutlookInboxMomentView: View {
    @Bindable var store: MorningStore
    private var french: Bool { AppLanguage.isFrench }
    private var blocked: Bool { store.connectedMoment.isInFlight || store.nativeMoment.isActive || store.voiceInputBlocksPlayback }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 14) {
                Label(french ? "Vos messages Outlook" : "Your Outlook messages", systemImage: "envelope")
                    .font(MorningTheme.Typography.heading)
                if OutlookInboxUITestFixture.isRequested {
                    Text("SYNTHETIC local fixture · no Outlook account is read or changed")
                        .font(.raleway(.caption)).accessibilityIdentifier("outlookInbox.synthetic")
                        .accessibilityValue("Inbox reads: \(OutlookInboxUITestFixture.inboxReadCount) · message reads: \(OutlookInboxUITestFixture.messageReadCount)")
                }
                if store.connectedMoment.isInFlight {
                    ProgressView(french ? "Lecture d’Outlook…" : "Reading Outlook…")
                        .accessibilityIdentifier("outlookInbox.loading")
                }
                if let document = store.currentOutlookInbox {
                    Text(document.target.sourceLabel()).font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("outlookInbox.account")
                    Text(document.summary()).font(.raleway(.subheadline)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("outlookInbox.summary")
                    Text(french ? "Au plus trois aperçus de non lus, même anciens. Aucun classement d’importance. Choisissez un message pour lire son corps ; aucune pièce jointe ni ressource distante ne sera ouverte."
                         : "Up to three unread previews, including older messages. No importance ranking. Choose a message to read its body; attachments and remote resources are not opened.")
                        .font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(document.messages.enumerated()), id: \.element.id) { index, message in
                        Button { store.readOutlookMessage(id: message.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Message \(index + 1)").font(.raleway(.caption).weight(.semibold))
                                Text(message.subject.isEmpty ? (french ? "Sans objet" : "No subject") : message.subject)
                                Text(message.senderName.isEmpty ? (message.senderAddress ?? (french ? "Expéditeur non précisé" : "Sender not provided")) : message.senderName)
                                    .font(.raleway(.caption))
                                if let address = message.senderAddress, address != message.senderName {
                                    Text(address).font(.raleway(.caption))
                                }
                                Text(message.receivedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                                    .font(.raleway(.caption))
                                if message.hasAttachments {
                                    Text(french ? "Pièces jointes présentes, non ouvertes" : "Attachments present, not opened").font(.raleway(.caption))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(SecondaryButtonStyle()).disabled(blocked)
                            .accessibilityIdentifier("outlookInbox.message.\(index)")
                    }
                    if let selected = store.currentOutlookMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(selectedMessageTitle(selected, in: document)).font(MorningTheme.Typography.heading)
                            Text(selected.message.subject.isEmpty ? (french ? "Sans objet" : "No subject") : selected.message.subject)
                                .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
                            if let body = selected.bodyText {
                                ScrollView {
                                    Text(body.isEmpty ? (french ? "Le corps du message est vide." : "This message has an empty body.") : body)
                                        .font(.raleway(.subheadline)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("outlookInbox.bodyText")
                                }.frame(maxHeight: 320).accessibilityIdentifier("outlookInbox.body")
                            } else {
                                Text(french ? "Le corps de ce message est indisponible. L’aperçu ne le remplace pas." : "This message’s body is unavailable. Its preview is not a substitute.")
                                    .font(.raleway(.subheadline)).accessibilityIdentifier("outlookInbox.body")
                            }
                            if selected.bodyIsIncomplete {
                                Text(french ? "La lecture du corps est incomplète. Les éléments absents restent inconnus." : "This body reading is incomplete. Missing content remains unknown.")
                                    .font(.raleway(.caption)).accessibilityIdentifier("outlookInbox.bodyIncomplete")
                            }
                        }
                    }
                    Text(store.canHearHandsFreeCommands
                         ? (french ? "Dites répète pour la même lecture, ou actualise Outlook pour de nouveaux aperçus." : "Say repeat for this same reading, or refresh Outlook for new previews.")
                         : (french ? "Utilisez les boutons pour relire cette lecture, actualiser les aperçus ou poursuivre votre matin." : "Use the buttons to read again, refresh the previews or continue your morning."))
                        .font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("outlookInbox.controlsHint")
                    Button(french ? "Relire cette lecture" : "Read this again") { _ = store.repeatOutlookReading() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(blocked).accessibilityIdentifier("outlookInbox.repeat")
                } else if !store.connectedMoment.isInFlight {
                    Text(french ? "Aucune lecture actuelle n’est disponible. Cela ne signifie pas que la boîte est vide. Actualisez ce moment ou passez à la suite."
                         : "No current reading is available. This does not mean the Inbox is empty. Refresh this moment or go to the next moment.")
                        .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("outlookInbox.unavailable")
                }
                Button(french ? "Actualiser Outlook" : "Refresh Outlook") { store.refreshOutlookInbox() }
                    .buttonStyle(SecondaryButtonStyle()).disabled(blocked).accessibilityIdentifier("outlookInbox.refresh")
            }.accessibilityElement(children: .contain)
                .onChange(of: store.currentOutlookInbox?.isCurrent(at: context.date), initial: true) { _, _ in
                    store.checkOutlookInboxFreshness()
                }
        }
    }

    private func selectedMessageTitle(_ selected: OutlookMessageDocument, in document: OutlookInboxDocument) -> String {
        guard let index = document.messages.firstIndex(where: { $0.id == selected.message.id }) else {
            return french ? "Message choisi" : "Selected message"
        }
        return french ? "Message \(index + 1) choisi" : "Selected message \(index + 1)"
    }
}
