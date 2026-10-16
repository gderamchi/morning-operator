import Foundation
import Testing
@testable import MorningCore

@Suite("First-opening permission explanations")
struct MorningPermissionProgressTests {
    @Test func requestsKeepOrderAndSpeechHasItsOwnStepBeforeMicrophone() {
        let supported = MorningPermission.allCases
        #expect(MorningPermissionProgress().pending(supported: supported) == supported)
        #expect(supported.firstIndex(of: .speech)! < supported.firstIndex(of: .microphone)!)
    }
    @Test func handledChoicesSurviveRelaunchAndDoNotRepeat() throws {
        var progress = MorningPermissionProgress()
        progress.resolve(.location)
        progress.resolve(.speech)
        let restored = try JSONDecoder().decode(MorningPermissionProgress.self, from: JSONEncoder().encode(progress))
        #expect(restored.pending(supported: [.location, .calendar, .speech, .microphone]) == [.calendar, .microphone])
    }
    @Test func unavailableCapabilitiesAndDuplicatesDoNotAddPrompts() {
        let progress = MorningPermissionProgress(completed: [.location])
        #expect(progress.pending(supported: [.location, .calendar, .calendar, .microphone]) == [.calendar, .microphone])
    }
    @Test func newlySupportedCapabilityIsOfferedAfterAnEarlierSetup() {
        let progress = MorningPermissionProgress(completed: [.location, .calendar])
        #expect(progress.pending(supported: [.location, .calendar, .alarms]) == [.alarms])
    }
}
