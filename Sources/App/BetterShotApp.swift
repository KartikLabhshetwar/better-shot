import SwiftUI

@main
struct BetterShotApp: App {
    @NSApplicationDelegateAdaptor(BetterShotDelegate.self) var delegate
    @State private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("BetterShot", systemImage: "camera.viewfinder", isInserted: $showMenuBarIcon) {
            MenuBarContentView()
        }

        WindowGroup("Annotate", id: "editor", for: URL.self) { $url in
            if let url {
                EditorWindowView(imageURL: url)
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 760)

        Settings {
            PreferencesView()
        }
    }
}
