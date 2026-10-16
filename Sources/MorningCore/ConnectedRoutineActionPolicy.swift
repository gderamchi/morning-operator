import Foundation

/// Routine approval does not replace the owner's spoken mail-send instruction.
/// Directly reviewed UI actions have their own explicit execution path.
public enum ConnectedRoutineActionPolicy {
    public static func requiresSpokenMailSend(service: String, tool: String) -> Bool {
        let serviceWords = words(service)
        let toolWords = words(tool)
        let compactService = serviceWords.joined()
        let compactTool = toolWords.joined()
        let mailServices: Set<String> = ["gmail", "googlemail", "outlook", "microsoftoutlook", "office365", "microsoft365", "email", "mail", "smtp", "sendgrid", "resend", "mailgun", "postmark", "amazonses"]
        let mailPrefix = ["gmail", "outlook", "microsoftoutlook", "email", "smtp", "sendgrid", "resend", "mailgun", "postmark", "amazonses"]
            .contains { compactTool.hasPrefix($0) }
        guard mailServices.contains(compactService) || mailPrefix || toolWords.contains("email") || toolWords.contains("mail") else { return false }
        // Get/list operations about sent mail or send-as aliases do not send mail.
        let actionWords = toolWords.drop(while: {
            ["gmail", "googlemail", "outlook", "microsoftoutlook", "microsoft", "office", "office365", "365", "email", "mail", "smtp", "sendgrid", "resend", "mailgun", "postmark", "amazon", "ses", "amazonses"].contains($0)
        })
        if let first = actionWords.first, ["get", "list", "fetch", "search", "read", "find"].contains(first) { return false }
        return toolWords.contains { ["send", "reply", "replyall", "forward"].contains($0) } ||
            ["sendemail", "sendmail", "sendmessage", "senddraft", "replytoemail", "replytomessage", "replytothread", "replyall", "forwardemail", "forwardmessage"]
                .contains { compactTool.contains($0) }
    }

    public static var spokenMailSendExplanation: String {
        AppLanguage.isFrench
            ? "L’envoi, la réponse ou le transfert d’un mail demande votre instruction au moment de l’envoi. Ajoutez « Lire mes mails et m’aider à répondre » à votre routine Gmail pour envoyer à la voix. Vous pouvez aussi lancer cette action après l’avoir vérifiée dans vos comptes."
            : "Sending, replying to or forwarding mail needs your instruction at send time. Add “Read my mail and help me reply” to your Gmail routine to send by voice, or run this action explicitly after reviewing it in your accounts."
    }

    private static func words(_ value: String) -> [String] {
        // Split camelCase before folding so provider tool naming does not change policy.
        let separated = value.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        return separated.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
