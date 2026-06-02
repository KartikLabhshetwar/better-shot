import SwiftUI

@main
struct BetterShotApp: App {
    @NSApplicationDelegateAdaptor(BetterShotDelegate.self) var delegate
    @State private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("BetterShot", systemImage: "camera.viewfinder", isInserted: $showMenuBarIcon) {
            MenuBarContentView()
        }

        Settings {
            PreferencesView()
        }
    }
}
