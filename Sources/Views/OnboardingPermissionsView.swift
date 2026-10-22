import AppKit
import AVFoundation
import SwiftUI

enum OnboardingPermission: String, CaseIterable, Identifiable {
    case screen, accessibility, inputMonitoring, microphone, camera
    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen: "Screen & System Audio Recording"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .microphone: "Microphone"
        case .camera: "Camera"
        }
    }

    var symbol: String {
        switch self {
        case .screen: "desktopcomputer"
        case .accessibility: "keyboard"
        case .inputMonitoring: "cursorarrow.motionlines"
        case .microphone: "mic"
        case .camera: "video"
        }
    }

    var displayTitle: String { self == .screen ? "Screen capture" : title }

    var explanation: String {
        switch self {
        case .screen: "Screenshots, screen recordings, and optional system audio."
        case .accessibility: "Use capture shortcuts from any app."
        case .inputMonitoring: "Precise cursor effects and shortcut overlays. Never plain typing."
        case .microphone: "Add your voice to recordings."
        case .camera: "Show your camera alongside your screen."
        }
    }

    func needsSettings(status: OnboardingPermissionStatus, attempted: Bool) -> Bool {
        status == .denied || (mayNeedRestart && attempted && status == .notEnabled)
    }

    var settingsURL: URL {
        let pane: String
        switch self {
        case .screen: pane = "ScreenCapture"
        case .accessibility: pane = "Accessibility"
        case .inputMonitoring: pane = "ListenEvent"
        case .microphone: pane = "Microphone"
        case .camera: pane = "Camera"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)")!
    }

    var mayNeedRestart: Bool { self == .screen || self == .inputMonitoring || self == .accessibility }
}

enum OnboardingPermissionStatus: Equatable {
    case notEnabled, allowed, denied, restricted

    var label: String {
        switch self {
        case .notEnabled: "Not enabled"
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted on this Mac"
        }
    }

    static func media(_ status: AVAuthorizationStatus) -> Self {
        switch status {
        case .authorized: .allowed
        case .notDetermined: .notEnabled
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
}

@MainActor @Observable
final class OnboardingPermissions {
    private(set) var statuses: [OnboardingPermission: OnboardingPermissionStatus] = [:]
    private(set) var attempted: Set<OnboardingPermission> = []
    private(set) var requesting: OnboardingPermission?
    private(set) var settingsError: String?
    private(set) var settingsErrorPermission: OnboardingPermission?
    private(set) var shortcutsNeedRestart = false

    func status(_ permission: OnboardingPermission) -> OnboardingPermissionStatus {
        statuses[permission] ?? .notEnabled
    }

    func refresh() {
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        statuses = [
            .screen: CGPreflightScreenCaptureAccess() ? .allowed : .notEnabled,
            .accessibility: ShortcutService.hasAccessibilityPermission ? .allowed : .notEnabled,
            .inputMonitoring: CGPreflightListenEventAccess() ? .allowed : .notEnabled,
            .microphone: .media(RecordingInputAuthorization.status(for: .microphone)),
            .camera: .media(RecordingInputAuthorization.status(for: .camera)),
        ]
        if status(.accessibility) == .allowed && !ShortcutService.shared.isRegistered {
            ShortcutService.shared.registerAll()
        }
        shortcutsNeedRestart = status(.accessibility) == .allowed && !ShortcutService.shared.isRegistered
    }

    func request(_ permission: OnboardingPermission) async {
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1",
              requesting == nil, status(permission) != .allowed, status(permission) != .restricted else { return }
        refresh()
        guard status(permission) != .allowed, status(permission) != .restricted else { return }
        if permission.needsSettings(status: status(permission), attempted: attempted.contains(permission)) {
            openSettings(permission)
            return
        }
        requesting = permission
        attempted.insert(permission)
        settingsError = nil
        settingsErrorPermission = nil
        defer { requesting = nil; refresh() }
        switch permission {
        case .screen: _ = CGRequestScreenCaptureAccess()
        case .accessibility: ShortcutService.requestAccessibilityPermission()
        case .inputMonitoring: _ = CGRequestListenEventAccess()
        case .microphone: _ = await RecordingInputAuthorization.requestAccess(for: .microphone)
        case .camera: _ = await RecordingInputAuthorization.requestAccess(for: .camera)
        }
    }

    func openSettings(_ permission: OnboardingPermission) {
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1",
              requesting == nil, status(permission) != .restricted else { return }
        attempted.insert(permission)
        settingsError = NSWorkspace.shared.open(permission.settingsURL) ? nil
            : "Couldn’t open settings. Try again, or open System Settings → Privacy & Security → \(permission.title)."
        settingsErrorPermission = settingsError == nil ? nil : permission
    }
}

/// One onboarding permission as a native form row, with its recovery steps in the detail text.
struct OnboardingPermissionRow: View {
    let permission: OnboardingPermission
    let status: OnboardingPermissionStatus
    var attempted = false
    var isRequesting = false
    var requestsDisabled = false
    var errorMessage: String?
    var request: () -> Void
    var openSettings: () -> Void

    private var needsSettings: Bool { permission.needsSettings(status: status, attempted: attempted) }

    private var detail: String {
        if status == .restricted {
            return "Restricted by this Mac’s settings or administrator. You can continue without it."
        }
        if status != .allowed && needsSettings {
            let restart = permission.mayNeedRestart ? " If macOS asks you to quit, reopen BetterShot to continue setup." : ""
            return "In Privacy & Security \u{203A} \(permission.title), turn on BetterShot, then return here.\(restart)"
        }
        return "\(permission == .screen ? "Required" : "Optional"). \(permission.explanation)"
    }

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(permission.displayTitle)
            Text(detail)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var control: some View {
        if isRequesting {
            ProgressView().controlSize(.small).accessibilityLabel("Waiting for \(permission.displayTitle) permission")
        } else if status == .allowed {
            Label {
                Text("Allowed")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(permission.displayTitle) access allowed")
        } else if status == .restricted {
            Label("Restricted", systemImage: "lock.fill").foregroundStyle(.secondary)
        } else {
            Button(needsSettings ? "Open Settings\u{2026}" : "Allow\u{2026}", action: needsSettings ? openSettings : request)
                .disabled(requestsDisabled)
                .accessibilityLabel(needsSettings ? "Open \(permission.title) settings" : "Allow \(permission.displayTitle) access")
        }
    }
}
