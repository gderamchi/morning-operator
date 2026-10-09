import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import AVKit

struct LearnView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Make it yours", title: "Start with a real morning.",
                        subtitle: "Bring a short observation. Apple Intelligence will suggest a routine for you to review.")
            Card {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 27, weight: .light))
                            .foregroundStyle(MorningStyle.accent)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Show how your morning goes").font(.system(size: 19, weight: .semibold, design: .rounded))
                            Text("Choose a short screen recording, screenshot or text file. Only the file you select is read.")
                                .font(.system(size: 13)).foregroundStyle(MorningStyle.muted)
                        }
                    }
                    Button { importing = true } label: { Label("Choose an observation", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("learn.import")
                    Text("Phase 1 samples up to 24 video frames. Start with a short clip; fast actions may be missed. No recording starts automatically.")
                        .font(.system(size: 11)).foregroundStyle(MorningStyle.muted)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Or tell us in your own words").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("What do you check first? What do you enjoy? What would you like to keep?")
                        .font(.system(size: 13)).foregroundStyle(MorningStyle.muted)
                    ZStack(alignment: .topLeading) {
                        if store.notes.isEmpty {
                            Text("I check the weather, read my messages, then spend a little time playing chess…")
                                .font(.system(size: 14)).foregroundStyle(MorningStyle.muted.opacity(0.65))
                                .padding(12).allowsHitTesting(false)
                        }
                        TextEditor(text: $store.notes)
                            .font(.system(size: 14)).scrollContentBackground(.hidden)
                            .padding(6).frame(minHeight: 140)
                            .accessibilityLabel("Describe your morning").accessibilityIdentifier("learn.notes")
                            .disabled(store.busy)
                    }
                    .background(MorningStyle.background, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(MorningStyle.line))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) { analyzeControls }
                        VStack(alignment: .leading, spacing: 14) { analyzeControls }
                    }
                }
            }
            if store.busy {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(store.analysisStatus, systemImage: "sparkles").font(.system(size: 14, weight: .medium))
                        if store.progress > 0 { ProgressView(value: store.progress).tint(MorningStyle.accent) }
                        else { ProgressView().controlSize(.small) }
                        Button("Stop analysis") { store.cancelAnalysis() }.buttonStyle(.borderless)
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cpu").foregroundStyle(MorningStyle.green)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Intelligence on this device").font(.system(size: 13, weight: .semibold))
                    Text(store.modelSummary).font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
                    if !store.intelligence.isAvailable {
                        Text("You can still build a routine by hand or explore the labeled sample.")
                            .font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
                    }
                }
            }.padding(.horizontal, 4)
        }.foregroundStyle(MorningStyle.ink)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .image, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { store.importObservation(url) }
            case .failure(let error): store.notice = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var analyzeControls: some View {
        Button { store.analyzeNotes() } label: { Label("Find my routine", systemImage: "sparkles") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy || store.sessionActive || !store.intelligence.isAvailable)
            .accessibilityIdentifier("learn.analyze")
        Button("I'll build it myself") { store.useManualRoutine() }
            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
            .disabled(store.busy || store.sessionActive)
    }
}

struct SetupView: View {
    @Bindable var store: MorningStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Your setup", title: "A little preparation.\nA calmer start.",
                        subtitle: "See what's working here and what still needs a real-device test.")
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label("Apple Intelligence", systemImage: "sparkles").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        StatusPill(text: store.intelligence.isAvailable ? "Available" : "Not ready",
                                   color: store.intelligence.isAvailable ? MorningStyle.green : MorningStyle.accent)
                    }
                    Text(store.modelSummary).font(.system(size: 13)).foregroundStyle(MorningStyle.muted)
                    Button("Check again") { store.refreshCapabilities() }.buttonStyle(SecondaryButtonStyle())
                    Text("Interpretation stays on this device. If the model is unavailable, the app keeps manual and sample routines usable.")
                        .font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("A real look at your day", systemImage: "calendar").font(.system(size: 18, weight: .semibold))
                    Text("Connect your calendar to see today's events and hear a short schedule. Apple requests full calendar access; this app only reads events.")
                        .font(.system(size: 13)).foregroundStyle(MorningStyle.muted)
                    Button(store.calendarSnapshot == nil ? "Connect calendar" : "Refresh today's schedule") { store.connectCalendar() }
                        .buttonStyle(SecondaryButtonStyle()).disabled(store.calendarBusy)
                        .accessibilityIdentifier("setup.calendar")
                    if store.calendarBusy { ProgressView().controlSize(.small) }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Spoken guidance", systemImage: "speaker.wave.2").font(.system(size: 18, weight: .semibold))
                    Text("Try the voice, then select your HomePod output with the system audio controls. This does not connect to the HomePod microphone.")
                        .font(.system(size: 13)).foregroundStyle(MorningStyle.muted)
                    HStack(spacing: 12) {
                        Button("Test voice") { store.speech.speak("Good morning. Let's make room for the things that matter to you.") }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("setup.testVoice")
                        Button("Stop voice") { store.speech.stop() }.buttonStyle(SecondaryButtonStyle())
                        #if os(iOS)
                        AirPlayPicker().frame(width: 38, height: 38).accessibilityLabel("Choose audio output")
                        #endif
                    }
                    Text("Continuous voice commands and automatic room detection are not connected in Phase 1.")
                        .font(.system(size: 11)).foregroundStyle(MorningStyle.muted)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Your device lab", systemImage: "iphone.and.arrow.right.inward").font(.system(size: 18, weight: .semibold))
                    capabilityRow("iPhone 15 Pro Max", "UI-test harness prepared · needs Xcode and pairing")
                    capabilityRow("MacBook Air M4", "Local interpretation and this companion app")
                    capabilityRow("HomePod mini", "Audio output rehearsal still required")
                    Divider()
                    Text("The ordinary app doesn't control other apps. The separate Xcode test target contains the phone-control experiments. No live inbox or messages are connected here.")
                        .font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield").foregroundStyle(MorningStyle.green)
                Text("Routines and session progress are saved locally. No account, server or cloud upload is used by this app. Export a routine from Today whenever you want a portable copy.")
                    .font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
            }
        }.foregroundStyle(MorningStyle.ink)
    }

    private func capabilityRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
        }
    }
}

#if os(iOS)
struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.tintColor = .label
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

struct StepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState<RoutineStep> var step: RoutineStep
    let onSave: (RoutineStep) -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Make this moment yours") {
                    TextField("Title", text: $step.title)
                    TextField("What happens?", text: $step.detail, axis: .vertical).lineLimit(3...6)
                    Picker("Kind", selection: $step.kind) {
                        ForEach(StepKind.allCases, id: \.self) { kind in Text(kind.displayName).tag(kind) }
                    }
                    Stepper("\(step.durationMinutes) minutes", value: $step.durationMinutes, in: 1...120)
                    Toggle("Keep this in my routine", isOn: $step.isRequired)
                }
                Section {
                    Button("Remove step", role: .destructive) { onDelete() }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(step) }.disabled(step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            #if os(macOS)
            .frame(width: 500, height: 390)
            #endif
        }
    }
}
