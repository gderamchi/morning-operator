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

    var body: some Scene {
        WindowGroup {
            MorningRootView(store: store)
                .preferredColorScheme(.light)
                #if os(macOS)
                .frame(minWidth: 840, minHeight: 680)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1140, height: 820)
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
