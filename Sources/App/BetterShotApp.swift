import SwiftUI

@main
struct BetterShotApp: App {
    @NSApplicationDelegateAdaptor(BetterShotDelegate.self) var delegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}
