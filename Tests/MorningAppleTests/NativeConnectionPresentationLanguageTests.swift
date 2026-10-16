import Foundation
import Testing
@testable import MorningApple

@Suite("Native connection notices follow the chosen presentation language")
struct NativeConnectionPresentationLanguageTests {
    @Test func retainedNoticeHasBothLanguagesWithoutRepeatingItsAction() {
        let french = Locale(identifier: "fr_FR"), english = Locale(identifier: "en_US")
        let completed = NativeConnectionNotice.reminderCompleted
        #expect(completed.text(locale: english) == "Marked complete in Apple Reminders.")
        #expect(completed.text(locale: french) == "Marqué comme terminé dans Rappels Apple.")
        let waiting = NativeConnectionNotice.stoppedWaiting
        #expect(waiting.text(locale: english).contains("may still be running"))
        #expect(waiting.text(locale: french).contains("raccourci"))
        let failed = NativeConnectionNotice.shortcutCouldNotOpen
        #expect(failed.text(locale: english).contains("couldn't open"))
        #expect(failed.text(locale: french).contains("ouvrir"))
        let timedOut = NativeConnectionNotice.remindersTimedOut
        #expect(timedOut.text(locale: english).contains("didn't answer in time"))
        #expect(timedOut.text(locale: french).contains("temps"))
    }
}
