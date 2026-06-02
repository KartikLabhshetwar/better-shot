import SwiftUI

@main
struct BetterShotApp: App {
    @NSApplicationDelegateAdaptor(BetterShotDelegate.self) var delegate
    @State private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("BetterShot", systemImage: "camera.viewfinder", isInserted: $showMenuBarIcon) {
            MenuBarContentView()
                .withAnnotateWiring()
        }

        WindowGroup("Annotate", id: "editor", for: URL.self) { $url in
            if let url {
                EditorWindowView(imageURL: url)
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .onDisappear {
                        NSApp.setActivationPolicy(.accessory)
                    }
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 760)

        Settings {
            PreferencesView()
        }
    }
}

private struct AnnotateWiringModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                PreviewOverlay.shared.onAnnotate = { url in
                    openWindow(id: "editor", value: url)
                }
            }
    }
}

extension View {
    func withAnnotateWiring() -> some View {
        modifier(AnnotateWiringModifier())
    }
}
