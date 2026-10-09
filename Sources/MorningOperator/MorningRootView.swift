import SwiftUI
import UniformTypeIdentifiers
import MorningCore

struct MorningRootView: View {
    @Bindable var store: MorningStore

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            Rectangle().fill(MorningStyle.line).frame(width: 1)
            page.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MorningStyle.background)
        #else
        TabView(selection: $store.tab) {
            ForEach(MorningTab.allCases) { tab in
                content(for: tab)
                    .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .tint(MorningStyle.accent)
        #endif
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(MorningStyle.accent)
                Text("morning\noperator").font(.system(size: 27, weight: .semibold, design: .rounded))
                    .lineSpacing(-2).foregroundStyle(MorningStyle.ink)
            }
            VStack(spacing: 7) {
                ForEach(MorningTab.allCases) { tab in
                    Button { store.tab = tab } label: {
                        HStack(spacing: 13) {
                            Image(systemName: tab.symbol).font(.system(size: 17)).frame(width: 22)
                            Text(tab.rawValue).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            if store.tab == tab { Circle().fill(MorningStyle.accent).frame(width: 5, height: 5) }
                        }
                        .foregroundStyle(store.tab == tab ? MorningStyle.ink : MorningStyle.muted)
                        .padding(.horizontal, 15).padding(.vertical, 14)
                        .background(store.tab == tab ? .white : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                    .accessibilityIdentifier("navigation.\(tab.rawValue.lowercased())")
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Rectangle().fill(MorningStyle.line).frame(height: 1)
                Label("On your device", systemImage: "lock.shield").font(.system(size: 12, weight: .medium))
                Text("Personal prototype · Phase 1")
                    .font(.system(size: 10)).foregroundStyle(MorningStyle.muted)
            }.foregroundStyle(MorningStyle.green)
        }.padding(.horizontal, 24).padding(.top, 42).padding(.bottom, 26)
    }

    private var page: some View { content(for: store.tab) }

    @ViewBuilder private func content(for tab: MorningTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                switch tab {
                case .today: TodayView(store: store)
                case .learn: LearnView(store: store)
                case .setup: SetupView(store: store)
                }
                if let notice = store.notice {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle").foregroundStyle(MorningStyle.accent)
                        Text(notice).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { store.notice = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                    }
                    .foregroundStyle(MorningStyle.ink).padding(16)
                    .background(MorningStyle.paleOrange.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("app.notice")
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }.background(MorningStyle.background).id(tab)
    }
}

struct TodayView: View {
    @Bindable var store: MorningStore
    @ViewState<RoutineStep?> private var editingStep: RoutineStep?
    @ViewState<Bool> private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageHeading(eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                        title: "Make room for your morning.",
                        subtitle: "The things you care about. A little less phone handling.")
            if let snapshot = store.calendarSnapshot {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Today's schedule", systemImage: "calendar").font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Button { store.readCalendar() } label: { Image(systemName: "speaker.wave.2") }
                                .buttonStyle(.borderless).accessibilityLabel("Read today's schedule aloud")
                        }
                        if snapshot.events.isEmpty {
                            Text("No events in this calendar snapshot.").font(.system(size: 13)).foregroundStyle(MorningStyle.muted)
                        }
                        ForEach(Array(snapshot.events.prefix(3).enumerated()), id: \.offset) { _, event in
                            HStack(alignment: .top, spacing: 12) {
                                Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(MorningStyle.accent)
                                    .frame(width: 80, alignment: .leading)
                                Text(event.title).font(.system(size: 13))
                            }
                        }
                        Text("Local calendar · checked \(snapshot.retrievedAt.formatted(date: .abbreviated, time: .shortened)). Remote changes may still be syncing.")
                            .font(.system(size: 10)).foregroundStyle(MorningStyle.muted)
                    }
                }
            }
            if let routine = store.routine {
                routineHero(routine)
                if store.previousRoutine != nil && !routine.isApproved {
                    Button("Restore previous approved routine") { store.restorePreviousRoutine() }
                        .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("routine.restore")
                }
                if store.sessionActive || store.session?.status == .completed || store.session?.status == .stopped {
                    sessionCard
                }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your routine").font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(store.sessionActive ? "Your approved version stays fixed during this session." : "Tap a step to make it yours.")
                            .font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
                    }
                    Spacer()
                    Button { exporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderless).foregroundStyle(MorningStyle.ink)
                }
                VStack(spacing: 10) {
                    ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, index: index)
                    }
                }
                if !store.sessionActive {
                    Button {
                        editingStep = RoutineStep(title: "New step", detail: "What would you like to do?", kind: .custom, durationMinutes: 3, isRequired: false)
                    } label: { Label("Add a moment", systemImage: "plus") }
                    .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent).disabled(store.busy)
                }
            } else {
                welcomeHero
                HStack(alignment: .top, spacing: 18) {
                    miniExplainer("01", "Observe", "Bring a short recording or describe your morning.")
                    miniExplainer("02", "Make it yours", "Review the interpretation. Keep what matters.")
                    miniExplainer("03", "Here we go", "Move through your routine with spoken guidance.")
                }
            }
        }
        .foregroundStyle(MorningStyle.ink)
        .sheet(item: $editingStep) { step in
            StepEditor(step: step, onSave: { edited in
                var steps = store.routine?.steps ?? []
                if let index = steps.firstIndex(where: { $0.id == edited.id }) { steps[index] = edited }
                else { steps.append(edited) }
                store.updateSteps(steps)
                editingStep = nil
            }, onDelete: {
                store.updateSteps((store.routine?.steps ?? []).filter { $0.id != step.id })
                editingStep = nil
            })
        }
        .fileExporter(isPresented: $exporting,
                      document: store.routine.map(RoutineExportDocument.init),
                      contentType: .json,
                      defaultFilename: "Morning-Routine-v\(store.routine?.number ?? 1)") { result in
            if case .failure(let error) = result { store.notice = error.localizedDescription }
            else { store.notice = "Routine exported. Review any evidence quotes before sharing." }
        }
    }

    private var welcomeHero: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                StatusPill(text: "A fresh start", color: MorningStyle.accent)
                Spacer()
                Image(systemName: "sun.horizon.fill").font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(MorningStyle.accent.opacity(0.7)).accessibilityHidden(true)
            }
            Text("Your routine is already there.\nLet's get to know it.")
                .font(.system(size: 31, weight: .medium, design: .serif))
            Text("A briefing, a few messages, maybe a game of chess. Start with what your mornings actually look like.")
                .font(.system(size: 14)).foregroundStyle(MorningStyle.muted).frame(maxWidth: 480, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { welcomeButtons }
                VStack(alignment: .leading, spacing: 12) { welcomeButtons }
            }
        }
        .padding(30).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.81), Color(red: 0.98, green: 0.94, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }

    @ViewBuilder private var welcomeButtons: some View {
        Button { store.tab = .learn } label: { Label("Figure out my morning routine", systemImage: "sparkles") }
            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("learn.begin")
        Button("Explore a sample") { store.loadSample() }.buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("routine.sample").disabled(store.busy)
    }

    private func routineHero(_ routine: RoutineVersion) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                StatusPill(text: routine.isApproved ? "Ready for you" : "Your review comes first",
                           color: routine.isApproved ? MorningStyle.green : MorningStyle.accent)
                Spacer()
                Text("V\(routine.number)").font(.system(size: 12, weight: .bold)).foregroundStyle(MorningStyle.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(store.totalMinutes)").font(.system(size: 58, weight: .light, design: .rounded))
                Text("minutes, your way.").font(.system(size: 22, weight: .medium, design: .serif))
            }
            Text(routine.sourceLabel).font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("routine.source")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { routineControls(routine) }
                VStack(alignment: .leading, spacing: 16) { routineControls(routine) }
            }
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(MorningStyle.paleOrange.opacity(0.64), in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder private func routineControls(_ routine: RoutineVersion) -> some View {
        if !routine.isApproved {
            Button { store.approve() } label: { Label("This feels like me", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("routine.approve").disabled(store.busy)
        } else if !store.sessionActive {
            Button { store.start() } label: { Label("OK, here we go", systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("run.start")
                .disabled(store.busy)
        }
        Toggle("Read steps aloud", isOn: $store.readAloud)
            .toggleStyle(.switch).font(.system(size: 13)).fixedSize()
    }

    private var sessionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Eyebrow(text: "Right now")
                    Spacer()
                    Text(store.stateLabel).font(.system(size: 12, weight: .semibold)).foregroundStyle(MorningStyle.green)
                        .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
                }
                Text(store.currentStep?.title ?? (store.session?.status == .completed ? "A morning well spent." : "Take your time."))
                    .font(.system(size: 25, weight: .medium, design: .serif)).accessibilityIdentifier("run.step")
                if let step = store.currentStep {
                    Text(step.detail).font(.system(size: 14)).foregroundStyle(MorningStyle.muted)
                }
                if let session = store.session {
                    ProgressView(value: Double(session.currentStepIndex), total: Double(max(session.routine.steps.count, 1)))
                        .tint(MorningStyle.accent)
                }
                if store.sessionActive {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { sessionControls }
                        VStack(alignment: .leading, spacing: 12) { sessionControls }
                    }
                }
            }
        }
    }

    @ViewBuilder private var sessionControls: some View {
        if store.session?.status == .running {
            Button { store.advance() } label: { Label("Next", systemImage: "arrow.right") }
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("run.next")
            Button("Pause") { store.pause() }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("run.pause")
            Button("Skip") { store.advance(skipping: true) }.buttonStyle(.borderless)
        } else {
            Button("Continue") { store.resume() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("run.resume")
        }
        Button { store.readCurrent() } label: { Image(systemName: "speaker.wave.2") }
            .buttonStyle(SecondaryButtonStyle()).accessibilityLabel("Read current step aloud")
        Button("Stop") { store.stop() }.buttonStyle(.borderless).foregroundStyle(MorningStyle.muted)
            .accessibilityIdentifier("run.stop")
    }

    private func stepRow(_ step: RoutineStep, index: Int) -> some View {
        Button { editingStep = step } label: {
            HStack(spacing: 16) {
                Image(systemName: MorningStyle.symbol(for: step.kind))
                    .font(.system(size: 20, weight: .regular)).foregroundStyle(MorningStyle.accent)
                    .frame(width: 45, height: 45).background(MorningStyle.paleOrange.opacity(0.5), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title).font(.system(size: 15, weight: .semibold))
                    Text(step.detail).font(.system(size: 12)).foregroundStyle(MorningStyle.muted).lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(step.durationMinutes) min").font(.system(size: 12, weight: .semibold))
                    if step.isRequired { Text("KEEP").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(MorningStyle.green) }
                }
                if !store.sessionActive { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(MorningStyle.muted) }
            }
            .padding(17).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(MorningStyle.line.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(store.sessionActive || store.busy)
        .accessibilityIdentifier("routine.step.\(index)")
    }

    private func miniExplainer(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(number).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(MorningStyle.accent)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(MorningStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RoutineExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let routine: RoutineVersion

    init(_ routine: RoutineVersion) { self.routine = routine }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        routine = try JSONDecoder().decode(RoutineVersion.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(routine))
    }
}
