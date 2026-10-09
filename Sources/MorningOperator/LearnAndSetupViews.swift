import SwiftUI
import UniformTypeIdentifiers
import MorningCore

struct LearnView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var importing = false
    @ViewState<Bool> private var recording = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var notesFocused: Bool
    @ScaledMetric(relativeTo: .body) private var notesEditorHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Your rhythm", title: "Make your morning yours.",
                subtitle: "Start with what you already do. You'll review every suggestion before it becomes your routine.")

            if store.busy {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(store.analysisStatus, systemImage: "sparkles")
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if store.progress > 0 {
                            ProgressView(value: store.progress).tint(MorningStyle.accent)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button("Stop analysis") { store.cancelAnalysis() }
                            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("Show us your morning", symbol: "rectangle.on.rectangle")
                    Text("Start an explicitly shared recording or bring one you already made. Go through a short part of your morning, then review what we can see.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    #if os(iOS)
                    if #available(iOS 27.0, *) {
                        Button { recording = true } label: {
                            Label("Record a little of my morning", systemImage: "record.circle")
                        }.buttonStyle(PrimaryButtonStyle())
                            .disabled(!store.canStartRecording)
                            .accessibilityIdentifier("learn.record")
                    }
                    #endif
                    Button { importing = true } label: {
                        Label("Choose a recording or file", systemImage: "plus")
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.busy || store.sessionActive)
                    .accessibilityIdentifier("learn.import")
                    Text("A screenshot or text file works too. Only the file you choose is read; recording never starts automatically.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle(store.hasImportedObservation ? "What we could see" : "Add context, if you like", symbol: "pencil.and.outline")
                    Text(store.hasImportedObservation
                         ? "Review the text we found. Scroll inside it to see more, and correct anything we missed. Visible words don't always mean you performed an activity."
                         : "What do you check first? What helps you feel ready? Include the small things you want to make time for.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    notesEditor
                    if let issue = store.observationSaveIssue {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(issue).font(.footnote).foregroundStyle(MorningStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("learn.saveError")
                            Button("Retry saving this observation") { store.saveObservationEdits() }
                                .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                                .accessibilityIdentifier("learn.retrySave")
                        }
                    }
                    if !store.notes.isEmpty {
                        Button("Clear this observation", role: .destructive) { store.clearObservation() }
                            .buttonStyle(.borderless).font(.caption).disabled(store.busy)
                            .accessibilityIdentifier("learn.clear")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { analyzeControls }
                        VStack(alignment: .leading, spacing: 16) { analyzeControls }
                    }
                    if !store.intelligence.isAvailable {
                        Label("On-device suggestions aren't ready here yet. You can build and edit your routine yourself.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Your routine stays in your hands", systemImage: "hand.raised")
                    .font(.subheadline.weight(.medium)).foregroundStyle(MorningStyle.green)
                Text("Suggestions are a starting point. Change the order, add a step, or remove anything that doesn't fit before you approve it.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("About on-device learning") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.modelSummary)
                        Text("Your latest extracted observation is saved on this device; Clear this observation removes that text. Evidence already attached to a saved routine remains with it.")
                        Text("A recording is sampled at up to 24 moments, so short clips work best and quick actions may be missed. Visible text helps suggest a routine; it doesn't reveal every tap or intention.")
                        Text("Analysis uses Apple's on-device model when available. It doesn't run other apps or approve a routine for you.")
                        Button("Check availability again") { store.refreshCapabilities() }
                            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                    }.font(.footnote).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                }
                .font(.footnote.weight(.medium)).tint(MorningStyle.accent)
            }.padding(.horizontal, 4)
        }
        .foregroundStyle(MorningStyle.ink)
        .task { store.importUITestObservationIfRequested() }
        #if os(iOS)
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                store.saveObservationEdits()
                notesFocused = false
            }.accessibilityIdentifier("input.done")
        } }
        #endif
        .onChange(of: notesFocused) { _, focused in
            if !focused { store.saveObservationEdits() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveObservationEdits() }
        }
        .onDisappear { store.saveObservationEdits() }
        .sheet(isPresented: $recording) {
            RecordMorningView(canStartRecording: store.canStartRecording) { url in
                store.importObservation(url, suggestRoutineWhenReady: true)
            }
        }
        .onChange(of: store.routine?.id) { _, _ in if !store.busy { dismiss() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .image, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { store.importObservation(url) }
            case .failure(let error): store.notice = error.localizedDescription
            }
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.notes.isEmpty {
                Text("I check my calendar, read a few messages, then spend ten minutes playing chess…")
                    .font(.body).foregroundStyle(MorningStyle.muted.opacity(0.7))
                    .padding(12).allowsHitTesting(false)
            }
            TextEditor(text: Binding(get: { store.notes }, set: { store.updateObservationNotes($0) }))
                .font(.body).scrollContentBackground(.hidden)
                .padding(6).frame(height: notesEditorHeight)
                .accessibilityLabel("Describe your morning").accessibilityIdentifier("learn.notes")
                .focused($notesFocused)
                .disabled(store.busy || store.sessionActive)
        }
        .background(MorningStyle.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(MorningStyle.line))
    }

    @ViewBuilder private var analyzeControls: some View {
        Button { store.analyzeNotes() } label: { Label("Suggest a routine", systemImage: "sparkles") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy || store.sessionActive || !store.intelligence.isAvailable)
            .accessibilityIdentifier("learn.analyze")
        Button("Build it myself") { store.useManualRoutine() }
            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
            .disabled(store.busy || store.sessionActive)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold)).foregroundStyle(MorningStyle.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SetupView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var choosingVoice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Make yourself at home", title: "A few things, your way.",
                subtitle: "Choose what to connect and how you'd like your morning to sound.")

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Your calendar", systemImage: "calendar")
                        .font(.title3.weight(.semibold))
                    Text("Bring today's schedule into your morning. Apple asks for full calendar access to read events; any new event is saved only when you choose to save it.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(store.calendarSnapshot == nil ? "Connect Calendar" : "Refresh today's schedule") { store.connectCalendar() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(store.calendarBusy)
                        .accessibilityIdentifier("setup.calendar")
                    if store.calendarBusy {
                        ProgressView("Getting your schedule…").font(.footnote)
                    } else if let snapshot = store.calendarSnapshot {
                        Label(snapshot.events.isEmpty ? "No events in today's calendar snapshot" : "\(snapshot.events.count) events in today's calendar snapshot",
                              systemImage: "checkmark.circle")
                            .font(.footnote).foregroundStyle(MorningStyle.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("A voice to guide you", systemImage: "speaker.wave.2")
                        .font(.title3.weight(.semibold))
                    Button { choosingVoice = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Companion voice").font(.subheadline.weight(.semibold))
                                Text(store.speech.availableVoices.first { $0.id == store.speech.voiceIdentifier }?.name ?? "System default")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }.buttonStyle(.plain).disabled(store.sessionActive)
                        .accessibilityIdentifier("setup.voice")
                    Toggle(isOn: $store.readAloud) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Read each step aloud").font(.subheadline.weight(.medium))
                            Text("Hear the next step as you move through your routine.")
                                .font(.footnote).foregroundStyle(MorningStyle.muted)
                        }
                    }
                    .tint(MorningStyle.accent).accessibilityIdentifier("setup.readAloud")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { voiceControls }
                        VStack(alignment: .leading, spacing: 12) { voiceControls }
                    }
                    Text(store.speech.lastError ?? (store.speech.state == .speaking ? "Speaking…" : store.speech.state == .paused ? "Paused" : "Ready to speak"))
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("setup.speechStatus")
                        .accessibilityValue(store.speech.state.rawValue)
                    Divider().overlay(MorningStyle.line)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Listen where you like").font(.subheadline.weight(.medium))
                        #if os(iOS)
                        HStack(alignment: .top, spacing: 12) {
                            Text("Use the audio output picker to choose an available speaker, including a HomePod on your network.")
                                .font(.footnote).foregroundStyle(MorningStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            MorningAudioRoutePicker()
                        }
                        #else
                        Text("Choose a speaker or HomePod from your Mac's sound controls, then try the voice here.")
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        #endif
                        Text("Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet.")
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Kept close", systemImage: "lock.shield")
                        .font(.title3.weight(.semibold)).foregroundStyle(MorningStyle.green)
                    Text("Thoughts, dreams and routines are saved on this device. When you choose to save to Calendar or Reminders, those apps use your existing account and sync settings.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You can use Morning Operator without connecting your calendar.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                }
            }

            DisclosureGroup("Availability & device details") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Apple Intelligence", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                        Text(store.modelSummary).font(.footnote).foregroundStyle(MorningStyle.muted)
                        Button("Check again") { store.refreshCapabilities() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Divider()
                    Text("You can capture thoughts and dreams, edit a routine, and use spoken guidance even while the on-device model is unavailable.")
                    Text("Connecting a phone to a Mac doesn't automatically give this app control of the phone. The separate development test runner is needed for the phone-control experiment.")
                    Text("Messages and email aren't connected here yet. Automatic room detection and continuous voice commands also need further work.")
                }
                .font(.footnote).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            }
            .font(.subheadline.weight(.medium)).tint(MorningStyle.accent)
            .padding(.horizontal, 4)
        }.foregroundStyle(MorningStyle.ink)
        .sheet(isPresented: $choosingVoice) { VoicePickerView(speech: store.speech) }
    }

    @ViewBuilder private var voiceControls: some View {
        Button("Try the voice") {
            store.speech.speak("Good morning. Let's make room for the things that matter to you.")
        }
        .buttonStyle(PrimaryButtonStyle()).disabled(store.sessionActive).accessibilityIdentifier("setup.testVoice")
        Button("Stop") { store.speech.stop() }.buttonStyle(SecondaryButtonStyle()).disabled(store.sessionActive)
    }
}

struct StepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState<RoutineStep> var step: RoutineStep
    let onSave: (RoutineStep) -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Give this step a name", text: $step.title)
                        .accessibilityLabel("Step name")
                    TextField("What would you like to do?", text: $step.detail, axis: .vertical)
                        .lineLimit(3...7).accessibilityLabel("Step details")
                } header: {
                    Text("Your moment")
                } footer: {
                    Text("Keep it simple. You can change the order of your steps back in your routine.")
                }
                Section {
                    Picker("Category", selection: $step.kind) {
                        ForEach(StepKind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: MorningStyle.symbol(for: kind)).tag(kind)
                        }
                    }
                    Stepper(value: $step.durationMinutes, in: 1...120) {
                        Text("\(step.durationMinutes) \(step.durationMinutes == 1 ? "minute" : "minutes")")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Duration in minutes")
                    Toggle("Make this step essential", isOn: $step.isRequired)
                } header: {
                    Text("How it fits")
                } footer: {
                    Text("The category organizes your routine. Choose an action below to decide what Morning Operator does.")
                }
                Section {
                    Picker("Action", selection: $step.automation) {
                        Text("User-led moment").tag(Optional<RoutineStepAutomation>.none)
                        Text("Read this text aloud").tag(Optional(RoutineStepAutomation.spokenNote))
                        Text("Read today's calendar").tag(Optional(RoutineStepAutomation.todayCalendar))
                    }
                    .accessibilityIdentifier("step.automation")
                } header: {
                    Text("What Morning Operator does")
                } footer: {
                    Text(automationExplanation)
                }
                Section {
                    Button("Remove this step", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(MorningStyle.background)
            .tint(MorningStyle.accent)
            .navigationTitle("Make it yours")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var edited = step
                        edited.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(edited)
                        dismiss()
                    }
                    .disabled(step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 500, minHeight: 500, idealHeight: 540)
            #endif
        }
    }

    private var automationExplanation: String {
        switch step.automation {
        case .none:
            "Take this moment at your own pace, then tap Next when you're ready."
        case .spokenNote:
            "Reads the text you approve for this step. Speaking the instructions doesn't carry out the activity they describe."
        case .todayCalendar:
            "Reads today's actual events from your connected Calendar. Calendar access and spoken guidance are required."
        }
    }
}
