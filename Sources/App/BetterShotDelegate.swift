import AppKit
import SwiftUI
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
final class BetterShotDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.applyAppearance()
        NSApp.setActivationPolicy(.accessory)

        MenuBarPopoverController.shared.setup()

        Task {
            await AppUpdater.shared.checkForUpdatesQuietly()
        }

        if PermissionsOnboarding.allGranted {
            ShortcutService.shared.registerAll()

            if !ShortcutService.shared.isRegistered {
                Self.promptRestart()
            }
        } else {
            PermissionsOnboarding.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShortcutService.shared.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    static func promptRestart() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "BetterShot needs to restart to activate keyboard shortcut overrides. Restart now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            restartApp()
        }
    }

    static func restartApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Permissions Onboarding

/// Guides the user through granting Accessibility and Screen Recording permissions.
/// Fires the native system prompts (which auto-add the app to the corresponding
/// Privacy & Security lists), deep-links to the exact Settings pane, polls until
/// granted, and activates keyboard shortcuts automatically — no manual hunting
/// through System Settings. Stale entries left behind by a previous build (whose
/// code signature no longer matches) are reset automatically via `tccutil`, and
/// the app restarts itself when Screen Recording requires it.
@MainActor
@Observable
final class PermissionsOnboarding {
    static let shared = PermissionsOnboarding()

    private(set) var accessibilityGranted = false
    private(set) var screenRecordingGranted = false
    private(set) var isRestarting = false

    private var window: NSWindow?
    private var pollTimer: Timer?
    /// Screen Recording was granted during this session — the permission only
    /// becomes usable after the process restarts.
    private var screenRecordingNeedsRestart = false

    private init() {}

    static var allGranted: Bool {
        AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()
    }

    func show() {
        resetStalePermissions()
        refreshStatus()

        if window == nil {
            let hosting = NSHostingController(rootView: PermissionsOnboardingView(model: self))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to BetterShot"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.level = .floating
            self.window = window
        }

        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        startPolling()
    }

    func requestAccessibility() {
        // Shows the native prompt AND registers the app in the Accessibility list.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        // The prompt only fires once per app signature — always deep-link too,
        // so the user lands exactly where the toggle lives.
        openSettingsPane("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        // Shows the native prompt AND registers the app in the Screen Recording list.
        CGRequestScreenCaptureAccess()
        openSettingsPane("Privacy_ScreenCapture")
    }

    private func openSettingsPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// After a rebuild the app's code signature changes, so entries left in
    /// Privacy & Security by the previous build silently stop working — and the
    /// system prompt won't fire again because the app is "already in the list".
    /// Resetting the entry via `tccutil` clears the stale record so a fresh
    /// prompt + auto-add works, with no manual "−/+" dance in System Settings.
    private func resetStalePermissions() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        if !AXIsProcessTrusted() {
            runTCCReset(service: "Accessibility", bundleID: bundleID)
        }
        if !CGPreflightScreenCaptureAccess() {
            runTCCReset(service: "ScreenCapture", bundleID: bundleID)
        }
    }

    private func runTCCReset(service: String, bundleID: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        try? process.run()
        process.waitUntilExit()
    }

    private func refreshStatus() {
        accessibilityGranted = AXIsProcessTrusted()
        if !screenRecordingGranted {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }
    }

    /// `CGPreflightScreenCaptureAccess` caches its answer for the process
    /// lifetime, so a grant made while the app is running never turns true.
    /// Probing ScreenCaptureKit directly reflects the real TCC state — when it
    /// succeeds while the preflight still says no, the grant landed and the app
    /// just needs a restart.
    private func probeScreenRecording() async -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenRecordingNeedsRestart = true
            return true
        } catch {
            return false
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                await PermissionsOnboarding.shared.poll()
            }
        }
    }

    private func poll() async {
        guard !isRestarting else { return }

        let hadAccessibility = accessibilityGranted
        accessibilityGranted = AXIsProcessTrusted()

        // Activate shortcuts the moment Accessibility lands — no restart needed.
        if accessibilityGranted, !hadAccessibility || !ShortcutService.shared.isRegistered {
            ShortcutService.shared.registerAll()
        }

        if !screenRecordingGranted {
            screenRecordingGranted = await probeScreenRecording()
        }

        if accessibilityGranted && screenRecordingGranted {
            pollTimer?.invalidate()
            pollTimer = nil

            if screenRecordingNeedsRestart || !ShortcutService.shared.isRegistered {
                // Screen Recording (and sometimes the event tap) only takes
                // effect in a fresh process — restart automatically.
                isRestarting = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    BetterShotDelegate.restartApp()
                }
            } else {
                // Give the user a beat to see both checkmarks, then close.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    self.window?.orderOut(nil)
                }
            }
        }
    }
}

private struct PermissionsOnboardingView: View {
    let model: PermissionsOnboarding

    private var footerText: String {
        if model.isRestarting {
            return "All set! 🎉 Restarting BetterShot…"
        }
        if model.accessibilityGranted && model.screenRecordingGranted {
            return "All set! 🎉"
        }
        return "This window closes automatically once everything is granted."
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("BetterShot needs two permissions")
                    .font(.title3.weight(.semibold))
                Text("Click each button below — macOS will show a system dialog\nand open the right spot in System Settings. Just flip the switch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                permissionRow(
                    granted: model.accessibilityGranted,
                    icon: "keyboard",
                    title: "Accessibility",
                    subtitle: "Powers the global keyboard shortcuts (⌘⇧3, ⌘⇧4…)",
                    action: { model.requestAccessibility() }
                )
                permissionRow(
                    granted: model.screenRecordingGranted,
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    subtitle: "Required to capture screenshots and recordings",
                    action: { model.requestScreenRecording() }
                )
            }

            Text(footerText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 440)
    }

    @ViewBuilder
    private func permissionRow(granted: Bool, icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 32)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: action)
                    .controlSize(.regular)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
