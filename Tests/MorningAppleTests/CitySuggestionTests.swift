import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("City field lookups — injected sources only")
@MainActor
struct CitySuggestionTests {
    @Test func failedOrTimedOutSuggestionsAreNotReportedAsNoMatch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var answer: Result<[CitySuggestion], any Error> = .failure(URLError(.notConnectedToInternet))
        let controller = makeController(directory: directory, suggestions: { _ in try answer.get() })
        #expect(controller.citySearchOutcome == nil)
        await controller.suggestCities("To")
        #expect(controller.citySearchOutcome == .unavailable && controller.citySuggestions.isEmpty)
        answer = .success([])
        await controller.suggestCities("To")
        #expect(controller.citySearchOutcome == .noMatch)
        answer = .success([tokyo])
        await controller.suggestCities("To")
        #expect(controller.citySearchOutcome == nil && controller.citySuggestions == [tokyo])
        answer = .failure(URLError(.timedOut))
        await controller.suggestCities("Tok")
        #expect(controller.citySearchOutcome == .unavailable)
        #expect(controller.citySuggestions == [tokyo], "Earlier suggestions stay until newer ones arrive.")

        let gate = CityGate<[CitySuggestion]>()
        let slow = makeController(directory: temporaryDirectory(), suggestions: { _ in try await gate.value() },
                                  timeout: .milliseconds(20))
        await slow.suggestCities("To")
        #expect(slow.citySearchOutcome == .unavailable)
        gate.release([tokyo])
        await settle()
        #expect(slow.citySuggestions.isEmpty, "A result after the deadline has no recipient.")
    }

    @Test func olderSuggestionsCannotReplaceTheAnswerToNewerTyping() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CityGate<[CitySuggestion]>()
        var fragments: [String] = []
        let controller = makeController(directory: directory, suggestions: { fragment in
            fragments.append(fragment); return try await gate.value()
        })
        controller.cityQueryChanged("P")
        await settle()
        #expect(fragments.isEmpty, "One character is not sent to Apple Maps.")
        controller.cityQueryChanged("Pa")
        await until { gate.calls == 1 }
        controller.cityQueryChanged(" Pa ")
        await settle()
        #expect(gate.calls == 1, "Surrounding spaces are not a new query.")
        controller.cityQueryChanged("To")
        await until { gate.calls == 2 }
        gate.release([paris])
        await settle()
        #expect(controller.citySuggestions.isEmpty)
        gate.release([tokyo])
        await until { !controller.citySuggestions.isEmpty }
        #expect(controller.citySuggestions == [tokyo] && fragments == ["Pa", "To"])
    }

    @Test func typingAfterChoosingACityCancelsThePendingChoice() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CityGate<[WeatherLocation]>()
        let lyon = try WeatherLocation(latitude: 45.76, longitude: 4.83, displayName: "Lyon, France")
        let controller = makeController(directory: directory, suggestions: { _ in [] }, resolver: { _ in try await gate.value() })
        controller.cityQueryChanged("Ly")
        let choice = Task { await controller.chooseCity(CitySuggestion(title: "Lyon", subtitle: "France")) }
        await until { gate.calls == 1 }
        #expect(controller.isSearchingCities)
        controller.cityQueryChanged("Tok")
        #expect(!controller.isSearchingCities)
        gate.release([lyon])
        #expect(await choice.value == nil, "A late place must not be saved over newer typing.")

        let kept = Task { await controller.chooseCity(CitySuggestion(title: "Lyon", subtitle: "France")) }
        await until { gate.calls == 2 }
        gate.release([lyon])
        #expect(await kept.value == lyon)
    }

    @Test func explicitResultsDoNotHideSuggestionsForNewerTyping() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let place = try WeatherLocation(latitude: 48.86, longitude: 2.35, displayName: "Paris, France")
        let searchGate = CityGate<[WeatherLocation]>()
        var held = false
        let controller = makeController(directory: directory, suggestions: { _ in [self.tokyo] },
            search: { _ in held ? try await searchGate.value() : [place] })
        controller.cityQueryChanged("Paris")
        await controller.searchCities("Paris")
        #expect(controller.cityResults == [place])
        controller.cityQueryChanged("Tokyo")
        #expect(controller.cityResults.isEmpty)
        await until { controller.citySuggestions == [tokyo] }

        // A search still running when the text changes cannot publish either.
        held = true
        let search = Task { await controller.searchCities("Tokyo") }
        await until { searchGate.calls == 1 }
        controller.cityQueryChanged("Tokyo, J")
        #expect(!controller.isSearchingCities)
        searchGate.release([place])
        await search.value
        #expect(controller.cityResults.isEmpty)
    }

    @Test func leavingTheCityFieldCancelsLookupsAndClearsTheirState() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CityGate<[CitySuggestion]>()
        let resolverGate = CityGate<[WeatherLocation]>()
        let controller = makeController(directory: directory, suggestions: { _ in try await gate.value() },
                                        resolver: { _ in try await resolverGate.value() })
        controller.cityQueryChanged("To")
        await until { gate.calls == 1 }
        gate.release([tokyo])
        await until { controller.citySuggestions == [tokyo] }

        controller.cityQueryChanged("Tok")
        await until { gate.calls == 2 }
        let choice = Task { await controller.chooseCity(tokyo) }
        await until { resolverGate.calls == 1 }
        controller.clearCitySearch()
        #expect(controller.citySuggestions.isEmpty && controller.citySearchOutcome == nil && !controller.isSearchingCities)
        gate.release([tokyo])
        resolverGate.release([try WeatherLocation(latitude: 35.68, longitude: 139.69, displayName: "Tokyo, Japan")])
        #expect(await choice.value == nil)
        await settle()
        #expect(controller.citySuggestions.isEmpty, "A reopened sheet starts without the earlier query's suggestions.")

        controller.cityQueryChanged("Tok")
        await until { gate.calls == 3 }
        gate.release([tokyo])
        await until { controller.citySuggestions == [tokyo] }
    }

    @Test func forgettingResetsTheSuggestionSource() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var resets = 0
        let controller = makeController(directory: directory, suggestions: { _ in [self.tokyo] }, reset: { resets += 1 })
        await controller.suggestCities("To")
        #expect(controller.citySuggestions == [tokyo])
        let before = resets
        try controller.updateSettings(.init(temperatureUnit: .fahrenheit))
        #expect(resets == before, "Saving a choice is not forgetting.")
        await controller.suggestCities("To")
        controller.cancelAndClear()
        #expect(resets == before + 1)
        #expect(controller.citySuggestions.isEmpty && controller.citySearchOutcome == nil)
        controller.reloadSettings()
        #expect(resets == before + 2)
    }

    private var tokyo: CitySuggestion { CitySuggestion(title: "Tokyo", subtitle: "Japan") }
    private var paris: CitySuggestion { CitySuggestion(title: "Paris", subtitle: "France") }

    private func makeController(directory: URL,
        suggestions: @escaping WeatherObservationService.CitySuggestionProvider,
        resolver: WeatherObservationService.CitySuggestionResolver? = nil,
        search: @escaping WeatherObservationService.CitySearchProvider = { _ in [] },
        reset: WeatherObservationService.CitySuggestionReset? = nil,
        timeout: Duration = .seconds(10)) -> MorningBriefingController {
        MorningBriefingController(directory: directory,
            calendar: CalendarObservationService(provider: CitySuggestionCalendarFixture()),
            weather: WeatherObservationService(weatherProvider: { _ in throw WeatherObservationError.serviceUnavailable },
                citySearchProvider: search, citySuggestionProvider: suggestions,
                citySuggestionResolver: resolver, citySuggestionReset: reset),
            sourceTimeout: timeout, suggestionDelay: .zero)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CitySuggestionTests-\(UUID().uuidString)")
    }

    /// Waits for main-actor work that is already scheduled; no timers are involved.
    private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}

/// Holds each call until released, in order, and ignores cancellation like a
/// late native callback.
@MainActor
private final class CityGate<Value: Sendable> {
    private var waiting: [CheckedContinuation<Value, any Error>] = []
    private(set) var calls = 0
    func value() async throws -> Value {
        calls += 1
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }
    func release(_ value: Value) { waiting.removeFirst().resume(returning: value) }
}

@MainActor
private final class CitySuggestionCalendarFixture: CalendarObservationProviding {
    var isAuthorized: Bool { false }
    func requestAccess() async throws -> Bool { false }
    func calendarChoices() throws -> [CalendarChoice] { [] }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] { [] }
}
