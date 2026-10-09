import SwiftUI
import MorningCore
import MorningApple
#if os(macOS)
import AppKit
#endif

@main
struct MorningOperatorApp: App {
    @ViewState<MorningStore> private var store = MorningStore()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MorningAppDelegate.self) private var appDelegate
    #endif

    init() { MorningAppShortcuts.updateAppShortcutParameters() }

    private var testAppearance: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return nil }
        if arguments.contains("--light-preview") { return .light }
        if arguments.contains("--dark-preview") { return .dark }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            MorningRootView(store: store)
                .preferredColorScheme(testAppearance)
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 680)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 560, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Start morning") { store.start() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(store.routine?.isApproved != true || store.busy)
                Button("Next step") { store.advance() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .disabled(store.session?.status != .running)
                Button("Stop morning") { store.stop() }
                    .keyboardShortcut(".", modifiers: [.command])
            }
        }
        #endif
    }
}

#if os(macOS)
@MainActor
final class MorningAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif
