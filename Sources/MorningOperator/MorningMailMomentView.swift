import SwiftUI
import MorningCore
import MorningApple

/// Ordinary foreground mail controls, including a literal editable self-note
/// when the optional local model is unavailable. Draft text stays in memory.
struct MorningMailMomentView: View {
    @Bindable var store: MorningStore
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        let mail = store.mailMorning
        VStack(alignment: .leading, spacing: 12) {
            if mail.canComposeSelfMessage, !mail.isComposingSelfMessage {
                Button(french ? "Note à moi-même" : "Note to myself") { store.beginSelfMail() }
                    .accessibilityIdentifier("mail.composeSelf")
            }
            if mail.isComposingSelfMessage {
                if let recipient = mail.recipient {
                    Text((french ? "À vous-même : " : "To yourself: ") + recipient)
                        .textSelection(.enabled).accessibilityIdentifier("mail.selfRecipient")
                }
                TextField(french ? "Objet" : "Subject", text: Binding(
                    get: { mail.selfMessageSubject },
                    set: { store.editSelfMail(subject: $0, body: mail.draftText) }))
                    .accessibilityIdentifier("mail.selfSubject")
                    .disabled(mail.lastSendOutcome != nil || mail.state != .reviewingSelfMessage)
                Text(french ? "Texte du message" : "Message body").font(.caption)
                TextEditor(text: Binding(get: { mail.draftText },
                    set: { store.editSelfMail(subject: mail.selfMessageSubject, body: $0) }))
                    .frame(minHeight: 120, maxHeight: 220)
                    .accessibilityIdentifier("mail.selfBody")
                    .disabled(mail.lastSendOutcome != nil || mail.state != .reviewingSelfMessage)
                Button(french ? "Relire ce brouillon" : "Review this draft") { store.reviewSelfMail() }
                    .disabled(mail.selfMessageSubject.isEmpty || mail.draftText.isEmpty || mail.lastSendOutcome != nil)
                    .accessibilityIdentifier("mail.selfReview")
                Button(french ? "Envoyer ce mail" : "Send this email") { store.sendReviewedSelfMail() }
                    .disabled(!mail.canSendSelfMessage)
                    .accessibilityIdentifier("mail.selfSend")
                Text(french ? "Chaque modification demande une nouvelle relecture. Le destinataire vient du compte Gmail connecté."
                            : "Each edit needs a new review. The recipient comes from the connected Gmail account.")
                    .font(.caption)
            }
            if mail.isAwaitingResponse {
                Button(french ? "Continuer mon matin" : "Continue my morning") { store.continueMailMorning() }
                    .accessibilityIdentifier("mail.continue")
            }
        }
        .disabled([.preparing, .preparingReply, .sending].contains(mail.state))
        .font(.subheadline)
        .accessibilityElement(children: .contain)
    }
}
