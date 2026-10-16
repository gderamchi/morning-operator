import Testing
@testable import MorningCore

@Suite("Jury browser commands")
struct JuryDemoBrowserCommandTests {
    @Test func recognizesOnlyExplicitNavigationRequests() {
        for request in ["VIDÉO SUIVANTE !", "La suivante, s’il te plaît.", "scroll", "descends", "fais défiler"] {
            #expect(JuryDemoBrowserCommand.parse(request) == .nextVideo)
        }
        for request in ["reviens avant", "reviens à celle d’avant", "vidéo précédente"] {
            #expect(JuryDemoBrowserCommand.parse(request) == .previousVideo)
        }
        for request in ["ferme", "retour à mon matin", "ferme le navigateur"] {
            #expect(JuryDemoBrowserCommand.parse(request) == .close)
        }
    }

    @Test func leavesQuestionsRefusalsAndRoutineCommandsToConversation() {
        for request in ["suivant", "continue", "pause", "arrête", "ne scroll pas", "ne ferme pas", "Tu peux faire défiler ?", "J’aime cette vidéo", "regarde les stories", ""] {
            #expect(JuryDemoBrowserCommand.parse(request) == nil)
        }
    }
}
