//
//  RecordingInputAuthorization.swift
//  BetterShot
//
//  Resolves camera and microphone authorization before a recording input is
//  persisted. Denied access is surfaced with a direct route to System Settings
//  instead of failing later while the recording stream is starting.
//

import AppKit
import AVFoundation

@MainActor
enum RecordingInputAuthorization {
    enum Input {
        case camera
        case microphone

        fileprivate var mediaType: AVMediaType {
            switch self {
            case .camera:
                .video
            case .microphone:
                .audio
            }
        }

        fileprivate var title: String {
            switch self {
            case .camera:
                "Camera"
            case .microphone:
                "Microphone"
            }
        }

        fileprivate var settingsURL: URL? {
            let pane: String
            switch self {
            case .camera:
                pane = "Privacy_Camera"
            case .microphone:
                pane = "Privacy_Microphone"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        }
    }

    static func status(for input: Input) -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: input.mediaType)
    }

    /// Requests access when it has not been decided yet. Denied or restricted
    /// access is explained immediately so callers never persist an unusable
    /// recording-device selection.
    static func ensureAccess(for input: Input) async -> Bool {
        let currentStatus = status(for: input)
        let granted = await requestAccess(for: input)
        guard !granted else { return true }

        presentDeniedAlert(for: input, isRestricted: currentStatus == .restricted)
        return false
    }

    /// Resolves access without presenting UI. Recording startup uses this to
    /// collect all unavailable optional inputs into one downgrade warning.
    static func requestAccess(for input: Input) async -> Bool {
        switch status(for: input) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: input.mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func presentDeniedAlert(for input: Input, isRestricted: Bool) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(input.title) access needed"

        if isRestricted {
            alert.informativeText = "BetterShot can't use the \(input.title.lowercased()) because access is restricted on this Mac."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        alert.informativeText = "Allow BetterShot to use the \(input.title.lowercased()) in Privacy & Security, then select it again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn,
           let settingsURL = input.settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
