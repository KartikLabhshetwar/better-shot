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

    var explanation: String {
        switch self {
        case .screen: "Capture screenshots and record your screen. System audio is included only when you choose it in Recording options."
        case .accessibility: "Use BetterShot’s global capture shortcuts from other apps. You can still capture from the menu bar without this."
        case .inputMonitoring: "Record precise pointer motion and, when enabled, shortcuts and special keys. Plain typing is never recorded. Basic pointer tracking works without this."
        case .microphone: "Narrate your videos. Granting access doesn’t turn on the mic; choose it in Recording options when you want to speak."
        case .camera: "Add your face to a recording. Granting access doesn’t turn on the camera; choose it in Recording options when you want it."
        }
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
        requesting = permission
        attempted.insert(permission)
        settingsError = nil
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
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        if resumesOnboarding && permission.mayNeedRestart { OnboardingState.resumeAtPermissions() }
        attempted.insert(permission)
        settingsError = NSWorkspace.shared.open(permission.settingsURL) ? nil
            : "Open System Settings manually, then Privacy & Security > \(permission.title)."
    }
}

struct OnboardingPermissionRow: View {
    let permission: OnboardingPermission
    let status: OnboardingPermissionStatus
    var attempted = false
    var isRequesting = false
    var requestsDisabled = false
    var request: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label(permission.title, systemImage: permission.symbol).font(.headline)
                    Spacer(minLength: 8)
                    statusLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(permission.title, systemImage: permission.symbol).font(.headline)
                    statusLabel
                }
            }
            Text(permission == .screen ? "Needed for screenshots and screen recording" : "Optional · Only for the feature described below")
                .font(.caption).foregroundStyle(.secondary)
            Text(permission.explanation).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if status == .restricted {
                Text("Access is restricted by this Mac’s settings or administrator. You can continue without this feature.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if status != .allowed {
                HStack {
                    if status == .notEnabled && !attempted {
                        Button("Request Access", action: request)
                            .accessibilityLabel("Request \(permission.title) access")
                    }
                    Button("Open System Settings", action: openSettings)
                        .accessibilityLabel("Open \(permission.title) settings")
                    if isRequesting { ProgressView().controlSize(.small).accessibilityLabel("Waiting for permission") }
                }
                .disabled(requestsDisabled)
                if attempted || status == .denied {
                    Text("In Privacy & Security > \(permission.title), enable BetterShot, then return here to check again.")
                        .font(.caption).foregroundStyle(.secondary)
                    if permission.mayNeedRestart {
                        Text("If macOS asks you to quit, save your work first. Reopen BetterShot to return to this permissions step.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioEffectCard()
    }

    private var statusLabel: some View {
        Label(status.label, systemImage: status == .allowed ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(status == .allowed ? Color.green : Color.secondary)
            .fixedSize()
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
                request: { Task { await permissions.request(.accessibility) } },
                openSettings: { permissions.openSettings(.accessibility) })
            if permissions.shortcutsNeedRestart {
                Text("Access is allowed, but shortcuts aren’t active. Save your work, then quit and reopen BetterShot.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = permissions.settingsError { Text(error).font(.callout).foregroundStyle(.red) }
        }
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
}
