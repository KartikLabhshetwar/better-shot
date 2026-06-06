import AppKit

@MainActor
final class BetterShotDelegate: NSObject, NSApplicationDelegate {
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.accessory)

        MenuBarPopoverController.shared.setup()

        if ShortcutService.hasAccessibilityPermission {
            ShortcutService.shared.registerAll()

            if !ShortcutService.shared.isRegistered {
                Self.promptRestart()
            }
        } else {
            ShortcutService.requestAccessibilityPermission()
            startPermissionPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionPollTimer?.invalidate()
        ShortcutService.shared.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func startPermissionPolling() {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard ShortcutService.hasAccessibilityPermission else { return }
            timer.invalidate()

            DispatchQueue.main.async {
                self?.permissionPollTimer = nil
                ShortcutService.shared.registerAll()

                if !ShortcutService.shared.isRegistered {
                    Self.promptRestart()
                }
            }
        }
    }

    private static func promptRestart() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "BetterShot needs to restart to activate keyboard shortcut overrides. Restart now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
            try? task.run()
            NSApp.terminate(nil)
        }
    }
}
