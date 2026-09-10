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
    private let resumesOnboarding: Bool
    private(set) var statuses: [OnboardingPermission: OnboardingPermissionStatus] = [:]
    private(set) var attempted: Set<OnboardingPermission> = []
    private(set) var requesting: OnboardingPermission?
    private(set) var settingsError: String?
    private(set) var settingsErrorPermission: OnboardingPermission?
    private(set) var shortcutsNeedRestart = false

    init(resumesOnboarding: Bool = false) {
        self.resumesOnboarding = resumesOnboarding
    }

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
        if resumesOnboarding && permission.mayNeedRestart { OnboardingState.resumeAtPermissions() }
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
        if resumesOnboarding && permission.mayNeedRestart { OnboardingState.resumeAtPermissions() }
        attempted.insert(permission)
        settingsError = NSWorkspace.shared.open(permission.settingsURL) ? nil
            : "Couldn’t open settings. Try again, or open System Settings → Privacy & Security → \(permission.title)."
        settingsErrorPermission = settingsError == nil ? nil : permission
    }
}

struct OnboardingPermissionRow: View {
    let permission: OnboardingPermission
    let status: OnboardingPermissionStatus
    var attempted = false
    var isRequesting = false
    var requestsDisabled = false
    var errorMessage: String?
    var request: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: permission.symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(permission == .screen ? EditorChrome.accent : .secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(permission.displayTitle).font(.system(size: 13, weight: .semibold))
                        Text(permission == .screen ? "Required" : "Optional")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text(permission.explanation).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                action.frame(minWidth: 88)
            }
            if status == .restricted {
                Text("Restricted by this Mac’s settings or administrator. You can continue without this feature.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if status != .allowed && permission.needsSettings(status: status, attempted: attempted) {
                Text("In Privacy & Security → \(permission.title), turn on BetterShot, then return here.")
                    .font(.caption).foregroundStyle(.secondary)
                if permission.mayNeedRestart {
                    Text("If macOS asks you to quit, save your work and reopen BetterShot.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioEffectCard()
    }

    @ViewBuilder private var action: some View {
        if isRequesting {
            ProgressView().controlSize(.small).accessibilityLabel("Waiting for \(permission.displayTitle) permission")
        } else if status == .allowed {
            Label {
                Text("Allowed").foregroundStyle(.primary)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
                .font(.caption.weight(.medium))
                .accessibilityLabel("\(permission.displayTitle) access allowed")
        } else if status == .restricted {
            Label("Restricted", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            let settings = permission.needsSettings(status: status, attempted: attempted)
            Button(settings ? "Open Settings" : "Allow", action: settings ? openSettings : request)
                .buttonStyle(EditorButtonStyle(selected: permission == .screen, bordered: true))
                .disabled(requestsDisabled)
                .accessibilityLabel(settings ? "Open \(permission.title) settings" : "Allow \(permission.displayTitle) access")
        }
    }
}

/// Settings retains the same recovery controls for people who skip onboarding.
struct ShortcutPermissionView: View {
    @State private var permissions = OnboardingPermissions()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingPermissionRow(permission: .accessibility, status: permissions.status(.accessibility),
                attempted: permissions.attempted.contains(.accessibility),
                isRequesting: permissions.requesting == .accessibility,
                requestsDisabled: permissions.requesting != nil,
                errorMessage: permissions.settingsError,
                request: { Task { await permissions.request(.accessibility) } },
                openSettings: { permissions.openSettings(.accessibility) })
            if permissions.shortcutsNeedRestart {
                Text("Access is allowed, but shortcuts aren’t active. Save your work, then quit and reopen BetterShot.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
}
