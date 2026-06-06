import SwiftUI

@main
struct BetterShotApp: App {
    @NSApplicationDelegateAdaptor(BetterShotDelegate.self) var delegate
    @State private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("BetterShot", image: "MenuBarIcon", isInserted: $showMenuBarIcon) {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}
