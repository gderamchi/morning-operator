import SwiftUI
import MorningCore
import MorningApple

/// A dated archive of saved evidence, separate from completed routine runs.
struct ObservationHistoryView: View {
    @Bindable var store: MorningStore
    var onlyUndated = false
    var onLearn: () -> Void
    @ViewState<Bool> private var confirmingClear = false

    private var entries: [ObservationAcquisition] {
        store.observationArchive.entries
            .filter { !onlyUndated || $0.observedDate == nil }
            .sorted { ($0.importedAt ?? .distantPast) > ($1.importedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                Text(onlyUndated
                     ? "These observations need a day before they can appear in your morning history. The day a file was imported doesn't tell us when it was recorded."
                     : "Saved glimpses of your morning. Observations and routine runs stay separate; sampled screens don't measure complete phone use.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                ContentUnavailableView(onlyUndated ? "Every observation has a date" : "No saved observations",
                    systemImage: "sun.horizon", description: Text(onlyUndated ? "New undated imports will appear here." : "Record or import a little of your morning in Learn."))
            } else {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink {
                            ObservationHistoryDetail(store: store, observationID: entry.id, onLearn: onLearn)
                        } label: {
                            ObservationHistoryRow(entry: entry)
                        }.accessibilityIdentifier("observation.row.\(entry.id.uuidString)")
                    }
                }
            }
            if !onlyUndated, !entries.isEmpty {
                Section {
                    Button("Delete all observations", role: .destructive) { confirmingClear = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observations.deleteAll")
                }
            }
            if let notice = store.notice {
                Section { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle(onlyUndated ? "Date needed" : "Observations")
        .accessibilityIdentifier("observations.list")
        .onChange(of: confirmingClear) { _, presented in store.observationDetailPresented = presented }
        .alert("Delete all observations?", isPresented: $confirmingClear) {
            Button("Delete all", role: .destructive) { _ = store.clearAllObservations() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved original text, corrections, sampled frame evidence and screen interpretations. Your routines, saved runs and any recording awaiting recovery remain.")
        }
    }
}

struct ObservationHistoryRow: View {
    let entry: ObservationAcquisition

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.sourceLabel).font(.subheadline.weight(.medium)).lineLimit(2)
            Text(observationDateLabel(entry)).font(.caption).foregroundStyle(.secondary)
            if entry.origin != .human {
                Text(observationOriginLabel(entry.origin)).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct ObservationHistoryDetail: View {
    @Bindable var store: MorningStore
    let observationID: UUID
    var onLearn: () -> Void
    @ViewState<Bool> private var assigningDate = false
    @ViewState<Bool> private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var entry: ObservationAcquisition? { store.observationArchive.entry(id: observationID) }

    var body: some View {
        List {
            if let entry {
                Section {
                    Text(entry.sourceLabel).font(.headline)
                    LabeledContent("Observed day", value: observationDateLabel(entry))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Observed day")
                        .accessibilityValue(observationDateLabel(entry))
                        .accessibilityIdentifier("observation.observedDate")
                    if let date = entry.observedDate {
                        LabeledContent("Time zone", value: date.timeZoneIdentifier)
                        Text(date.provenance == .recordingSession ? "Day recorded by this recording session." : "Day assigned by you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Origin", value: observationOriginLabel(entry.origin))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Origin")
                        .accessibilityValue(observationOriginLabel(entry.origin))
                        .accessibilityIdentifier("observation.origin")
                    LabeledContent("Imported", value: observationImportDateLabel(entry))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Imported")
                        .accessibilityValue(observationImportDateLabel(entry))
                        .accessibilityIdentifier("observation.importedDate")
                    Button(entry.observedDate == nil ? "Set observed day" : "Change day or origin") { assigningDate = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.setDate")
                } footer: {
                    Text("Import time is separate from the day you observed. These dates don't establish how long you used your phone.")
                }

                Section {
                    Button {
                        if store.selectObservation(id: observationID) { onLearn() }
                    } label: { Label("Edit in Learn", systemImage: "pencil") }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.edit")
                    DisclosureGroup("Current notes") {
                        Text(entry.effectiveText.isEmpty ? "No notes saved." : entry.effectiveText)
                            .textSelection(.enabled).font(.subheadline)
                            .accessibilityIdentifier("observation.currentText")
                    }
                    DisclosureGroup("Original extracted text") {
                        Text(entry.originalText.isEmpty ? "No original text was retained." : entry.originalText)
                            .textSelection(.enabled).font(.subheadline)
                            .accessibilityIdentifier("observation.originalText")
                    }
                } footer: {
                    Text("Corrections change the notes used for suggestions. The original evidence stays available here.")
                }

                if let evidence = entry.videoEvidence {
                    Section {
                        LabeledContent("Sampled frames", value: "\(evidence.frames.count)")
                        Text("Occasional sampled screens can miss activity. They don't prove taps, reads, scroll counts or complete app use.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Original sampled text") {
                            ForEach(evidence.frames) { frame in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(String(format: "%.2f s", frame.timeSeconds)).font(.caption.weight(.medium))
                                    Text(frame.text.isEmpty ? "No readable text in this sample." : frame.text)
                                        .font(.caption).textSelection(.enabled)
                                    if frame.textWasTruncated { Text("Text limit reached.").font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical, 5)
                            }
                        }
                        if let classification = entry.classification {
                            Text(observationClassificationLabel(classification.status))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("Original recording evidence") }
                }

                if !entry.warnings.isEmpty {
                    Section {
                        Text("An unsupported screen interpretation was removed. Original evidence is intact.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Delete this observation", role: .destructive) { confirmingDelete = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.delete")
                    if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                ContentUnavailableView("Observation removed", systemImage: "doc", description: Text("Your routines and saved runs are still available."))
            }
        }
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle("Observation")
        .accessibilityIdentifier("observation.detail")
        .onAppear { store.observationDetailPresented = true }
        .onDisappear { store.observationDetailPresented = false }
        .sheet(isPresented: $assigningDate) {
            if let entry { ObservationDateEditor(store: store, entry: entry) }
        }
        .alert("Delete this observation?", isPresented: $confirmingDelete) {
            Button("Delete observation", role: .destructive) {
                if store.deleteObservation(id: observationID) { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes this observation's original text, corrections, sampled frame evidence and screen interpretation. Routines and saved runs keep their existing content.")
        }
    }
}

private struct ObservationDateEditor: View {
    @Bindable var store: MorningStore
    let entry: ObservationAcquisition
    @ViewState<Date> private var date: Date
    @ViewState<String> private var zoneIdentifier: String
    @ViewState<ObservationAcquisitionOrigin> private var origin: ObservationAcquisitionOrigin
    @Environment(\.dismiss) private var dismiss

    init(store: MorningStore, entry: ObservationAcquisition) {
        self.store = store
        self.entry = entry
        _date = ViewState(initialValue: entry.observedDate?.date ?? Date())
        _zoneIdentifier = ViewState(initialValue: entry.observedDate?.timeZoneIdentifier ?? TimeZone.current.identifier)
        _origin = ViewState(initialValue: entry.origin)
    }

    private var zone: TimeZone { TimeZone(identifier: zoneIdentifier) ?? .current }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Observed day", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, zone).environment(\.calendar, calendar)
                        .accessibilityIdentifier("observation.datePicker")
                    NavigationLink {
                        ObservationTimeZonePicker(selection: $zoneIdentifier)
                    } label: { LabeledContent("Time zone", value: zoneIdentifier.replacingOccurrences(of: "_", with: " ")) }
                        .accessibilityIdentifier("observation.timeZone")
                } footer: {
                    Text("Choose the day this activity happened, in the time zone where it happened. Import time isn't used to guess this day.")
                }
                Section {
                    Picker("Whose activity is this?", selection: $origin) {
                        Text("My morning").tag(ObservationAcquisitionOrigin.human)
                        Text("Sample or test").tag(ObservationAcquisitionOrigin.synthetic)
                        Text("Automated").tag(ObservationAcquisitionOrigin.automated)
                        Text("Unsure").tag(ObservationAcquisitionOrigin.unknown)
                    }.pickerStyle(.menu).accessibilityIdentifier("observation.originPicker")
                } footer: {
                    Text("A recording doesn't tell us whether a person or automation caused the activity. Keep Unsure when you don't know.")
                }
                if entry.observedDate != nil {
                    Section {
                        Button("Leave the date unknown") {
                            if store.assignObservationDate(id: entry.id, date: nil, timeZoneIdentifier: zoneIdentifier, origin: origin) { dismiss() }
                        }.disabled(store.busy || store.sessionActive)
                            .accessibilityIdentifier("observation.removeDate")
                    } footer: { Text("Moves this observation to Date needed without deleting its evidence.") }
                }
                if let notice = store.notice { Section { Text(notice).font(.caption).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Observed day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.assignObservationDate(id: entry.id, date: date, timeZoneIdentifier: zoneIdentifier, origin: origin) { dismiss() }
                    }.disabled(store.busy || store.sessionActive).accessibilityIdentifier("observation.saveDate")
                }
            }
            .onChange(of: zoneIdentifier) { old, new in
                // Changing the zone must not silently move the chosen calendar day.
                var oldCalendar = Calendar(identifier: .gregorian)
                oldCalendar.timeZone = TimeZone(identifier: old) ?? .current
                var fields = oldCalendar.dateComponents([.year, .month, .day], from: date)
                fields.hour = 12
                var newCalendar = Calendar(identifier: .gregorian)
                newCalendar.timeZone = TimeZone(identifier: new) ?? .current
                if let sameDay = newCalendar.date(from: fields) { date = sameDay }
            }
        }
    }
}

private struct ObservationTimeZonePicker: View {
    @Binding var selection: String
    @ViewState<String> private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var identifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                Button("Use current time zone: \(TimeZone.current.identifier)") { selection = TimeZone.current.identifier; dismiss() }
            }
            Section {
                ForEach(identifiers, id: \.self) { identifier in
                    Button { selection = identifier; dismiss() } label: {
                        HStack {
                            Text(identifier.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.primary)
                            Spacer()
                            if identifier == selection { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }.searchable(text: $search, prompt: "Search city or region").navigationTitle("Time zone")
    }
}

private func observationDateLabel(_ entry: ObservationAcquisition) -> String {
    guard let value = entry.observedDate else { return "Date needed" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: value.timeZoneIdentifier)
    return formatter.string(from: value.date)
}

private func observationOriginLabel(_ origin: ObservationAcquisitionOrigin) -> String {
    switch origin {
    case .human: "My morning"
    case .synthetic: "Sample or test"
    case .automated: "Automated activity"
    case .unknown: "Origin unsure"
    }
}

private func observationImportDateLabel(_ entry: ObservationAcquisition) -> String {
    entry.importedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Import date unknown"
}

private func observationClassificationLabel(_ status: ObservationContextInferenceStatus) -> String {
    switch status {
    case .completed: "Screen interpretation saved; unclear samples remain unknown."
    case .noEligibleFrames: "No samples have enough complete text to recognize a screen."
    case .unavailable: "Screen interpretation unavailable; original evidence is retained."
    case .partialFailure: "Some screen interpretations failed; those samples remain unknown."
    case .failed: "Screen interpretation failed; original evidence is retained."
    }
}
