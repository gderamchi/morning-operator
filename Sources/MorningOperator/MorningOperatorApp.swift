import SwiftUI
import MorningCore
import MorningApple

@main
struct MorningOperatorApp: App {
    @UIApplicationDelegateAdaptor(MorningNotificationDelegate.self) private var notificationDelegate
    @ViewState<MorningStore> private var store = MorningStore()

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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--design-preview") {
                HorizonDesignPreview().preferredColorScheme(testAppearance)
            } else {
                MorningRootView(store: store).preferredColorScheme(testAppearance)
            }
            #else
            MorningRootView(store: store)
                .preferredColorScheme(testAppearance)
            #endif
        }
    }
}
