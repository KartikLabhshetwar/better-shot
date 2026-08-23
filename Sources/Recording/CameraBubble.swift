import AVFoundation
import AppKit
import SwiftUI

/// Floating circular camera preview that sits on top of whatever you record. It is a real on-screen window rather than a composited overlay, so ScreenCaptureKit picks it up by excepting it from BetterShot's own excluded application.
@Observable
@MainActor
final class CameraBubbleController {
    static let shared = CameraBubbleController()

    enum Size: Int, CaseIterable, Identifiable {
        case small = 140
        case medium = 200
        case large = 280

        var id: Int { rawValue }
        var diameter: CGFloat { CGFloat(rawValue) }
        var label: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    private(set) var isEnabled = false
    private(set) var isStarting = false

    @ObservationIgnored private var session: CameraSessionBox?
    @ObservationIgnored private var panel: NSPanel?

    var windowID: CGWindowID? {
        guard let panel, panel.isVisible else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    private init() {}

    var hasCamera: Bool { !Self.availableCameras().isEmpty }

    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    func enable() {
        guard !isEnabled, !isStarting else { return }
        isStarting = true

        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isStarting = false
                guard granted else {
                    AppPreferences.recordingShowCamera = false
                    ToastWindow.shared.show(
                        title: "Camera Blocked",
                        message: "Allow BetterShot in System Settings > Privacy & Security > Camera.",
                        systemIcon: "video.slash"
                    )
                    return
                }
                self.startSession()
            }
        }
    }

    func disable() {
        AppPreferences.recordingShowCamera = false
        suspend()
    }

    /// Tears the bubble down without forgetting that the user wants it, so it comes back with the next recording.
    func suspend() {
        isEnabled = false
        panel?.orderOut(nil)
        panel = nil
        session?.stop()
        session = nil
    }

    func resize(to size: Size) {
        AppPreferences.recordingCameraSize = size.rawValue
        guard let panel else { return }
        let frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let diameter = size.diameter
        panel.setFrame(
            NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter),
            display: true,
            animate: !RecordingMotion.reduceMotion
        )
    }

    private func startSession() {
        guard let device = Self.preferredCamera() else {
            AppPreferences.recordingShowCamera = false
            ToastWindow.shared.show(
                title: "No Camera Found",
                message: "Connect a camera, or use Continuity Camera with your iPhone.",
                systemIcon: "video.slash"
            )
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            AppPreferences.recordingShowCamera = false
            ToastWindow.shared.show(
                title: "Camera Unavailable",
                message: "Another app may be using \(device.localizedName).",
                systemIcon: "video.slash"
            )
            return
        }
        session.addInput(input)

        let box = CameraSessionBox(session: session)
        self.session = box
        presentPanel(for: session)
        isEnabled = true
        AppPreferences.recordingShowCamera = true
        box.start()
    }

    private static func preferredCamera() -> AVCaptureDevice? {
        let cameras = availableCameras()
        if let savedID = AppPreferences.recordingCameraDeviceID,
           let match = cameras.first(where: { $0.uniqueID == savedID }) {
            return match
        }
        return cameras.first
    }

    private func presentPanel(for session: AVCaptureSession) {
        let diameter = Size(rawValue: AppPreferences.recordingCameraSize)?.diameter ?? Size.medium.diameter
        let screen = ActiveDisplayResolver.activeScreen(preferPointer: false) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 948)

        let panel = CameraBubblePanel(
            contentRect: NSRect(x: visible.minX + 32, y: visible.minY + 32, width: diameter, height: diameter),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = CameraBubbleView(session: session)

        panel.orderFrontRegardless()
        self.panel = panel
    }
}

/// Keeps `AVCaptureSession` off the main actor: start and stop block for hundreds of milliseconds while the camera warms up.
private final class CameraSessionBox: @unchecked Sendable {
    private let session: AVCaptureSession
    private let queue = DispatchQueue(label: "com.bettershot.camera.session", qos: .userInitiated)

    init(session: AVCaptureSession) {
        self.session = session
    }

    func start() {
        queue.async { self.session.startRunning() }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }
}

/// Borderless panel that never takes key focus, so clicking the bubble does not interrupt what you are recording.
private final class CameraBubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Circular live preview, mirrored so it reads like a mirror rather than a video call.
private final class CameraBubbleView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)

        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true

        let container = CALayer()
        container.masksToBounds = true
        container.addSublayer(previewLayer)
        layer = container
        updateShape()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        updateShape()
    }

    private func updateShape() {
        guard let layer else { return }
        layer.frame = bounds
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        layer.borderWidth = 3
        layer.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        previewLayer.frame = bounds
        previewLayer.cornerRadius = layer.cornerRadius
    }
}
