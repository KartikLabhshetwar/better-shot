import AppKit
import Combine
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case images, video, permissions, ready
        var title: String {
            switch self {
            case .images: "Screenshots"
            case .video: "Video"
            case .permissions: "Permissions"
            case .ready: "Ready"
            }
        }
    }

    @State var step: Step = .images
    var resourceBundle: Bundle = .main
    @State private var permissions = OnboardingPermissions(resumesOnboarding: true)
    @State private var errorMessage: String?
    private let permissionRefresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(nsImage: resourceBundle.image(forResource: "AppIcon") ?? NSApp.applicationIconImage)
                        .resizable().frame(width: 40, height: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Welcome to BetterShot").font(.headline)
                        Text("Screenshots, recordings, and a clear start.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count): \(step.title)")
                }
                Picker("Setup step", selection: $step) {
                    ForEach(Step.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .disabled(permissions.requesting != nil)
            }
            .padding(20)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch step {
                        case .images: images
                        case .video: video
                        case .permissions: permissionSetup
                        case .ready: ready
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("stepContent")
                }
                .onChange(of: step) { _, _ in
                    errorMessage = nil
                    proxy.scrollTo("stepContent", anchor: .top)
                    permissions.refresh()
                }
            }
            Divider()
            HStack {
                Button("Set Up Later") { OnboardingWindowController.shared.finish(openCaptureBar: true) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if step != .images {
                    Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .images }
                }
                Button(nextTitle) {
                    if step == .ready {
                        OnboardingWindowController.shared.finish(openCaptureBar: true)
                    } else {
                        step = Step(rawValue: step.rawValue + 1) ?? .ready
                    }
                }
                .buttonStyle(EditorButtonStyle(selected: true))
                .keyboardShortcut(.defaultAction)
            }
            .disabled(permissions.requesting != nil)
            .padding(16)
            .studioGlass(cornerRadius: 0)
        }
        .background(EditorChrome.workspace)
        .tint(EditorChrome.accent)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
        .onReceive(permissionRefresh) { _ in
            if step == .permissions || step == .ready { permissions.refresh() }
        }
    }

    private var nextTitle: String {
        switch step {
        case .images: "Next: Video"
        case .video: "Next: Permissions"
        case .permissions: permissions.status(.screen) == .allowed ? "Continue" : "Continue Without Access"
        case .ready: "Open Capture Bar"
        }
    }

    private var images: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Turn a screenshot into a clear explanation.", detail: "Capture exactly what you need, then add context without opening another app.")
            samplePreview(.coast, caption: "Your image, ready for arrows, notes, and a background.")
            feature("Capture a region, window, or display", symbol: "rectangle.dashed", action: .region,
                    detail: "Choose Area in the capture bar to use macOS’s screenshot selector. OCR copies text from the screen; Color samples a pixel.")
            feature("Point things out. Keep private details private.", symbol: "arrow.up.right",
                    detail: "Add arrows, text, numbered steps, or highlights. Blur or Pixelate a selected area. Click an active tool again to return to Select; undo with ⌘Z.")
            feature("Frame it, then send it", symbol: "photo.on.rectangle",
                    detail: "Choose a background, padding, corners, and shadow in the left inspector. Save keeps an editable project; Export writes a finished file. Copy pastes the image into another app.")
            Text("After setup, you can try the image editor with a practice photo—no screen access needed.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var video: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Record a walkthrough people can follow.", detail: "From your first take to a polished video, everything stays in BetterShot.")
            HStack(spacing: 12) {
                workflowStage("Record", symbol: "record.circle")
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                workflowStage("Edit", symbol: "scissors")
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                workflowStage("Export", symbol: "square.and.arrow.up")
            }
            .padding(20).studioEffectCard()
            feature("Choose your screen and inputs", symbol: "video", action: .recordingOptions,
                    detail: "Record a display, a window, or an adjustable area. Add a microphone, system audio, or face camera only when you need them. A teleprompter can keep your script nearby.")
            feature("Stay in control while recording", symbol: "pause.circle",
                    detail: "The recording bar keeps Stop, timer, Pause, Restart, and Discard together. Stop saves the take. Restart and Discard ask you to confirm first.")
            feature("Refine the story in the video editor", symbol: "scissors",
                    detail: "Trim or cut clips, adjust speed, and add zoom. Use the left tabs for Background, Cursor, Camera, Effects, and Zoom & Clips. Effects includes Crop, Blur, and Pixelate.")
            feature("Make movement easy to follow", symbol: "cursorarrow.motionlines",
                    detail: "BetterShot recordings keep cursor data separate, so you can change its style, smooth its motion, and show clicks. Imported videos with a baked-in cursor cannot be restyled.")
            feature("Export or share when you’re ready", symbol: "icloud.and.arrow.up",
                    detail: "Export MOV or MP4 to your Mac. Cloud sharing is optional and uses your own R2 storage; connect it later in Settings > Sharing.")
        }
    }

    private var permissionSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Give each feature the access it needs.", detail: "Set up access here before your first capture. Only screen access is needed to capture; the other permissions enable optional features.")
            Text("Choose Request Access for a feature you want. macOS displays the permission dialog. If access was denied, Open System Settings takes you to the right pane.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(OnboardingPermission.allCases) { permission in
                OnboardingPermissionRow(permission: permission, status: permissions.status(permission),
                    attempted: permissions.attempted.contains(permission),
                    isRequesting: permissions.requesting == permission,
                    requestsDisabled: permissions.requesting != nil,
                    request: { Task { await permissions.request(permission) } },
                    openSettings: { permissions.openSettings(permission) })
            }
            if permissions.shortcutsNeedRestart {
                Label("Accessibility is allowed, but shortcuts aren’t active yet. Save your work, then quit and reopen BetterShot.", systemImage: "arrow.clockwise")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = permissions.settingsError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            Button("Check Permissions Again") { permissions.refresh() }
                .disabled(permissions.requesting != nil)
            Text("Status refreshes when you return. If an enabled permission still says Not enabled, save your work and reopen BetterShot. This guide returns to Permissions after a setup request that may need a restart.")
                .font(.caption).foregroundStyle(.secondary)
            Text("You can continue without granting access. Capturing will remain unavailable until screen access is enabled; the practice image editor still works.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(permissions.status(.screen) == .allowed ? "You’re ready to capture." : "Your next step: screen access.",
                    detail: "Find BetterShot’s clover in the menu bar whenever you need a screenshot, a recording, or your recent work.")
            HStack(alignment: .top, spacing: 12) {
                Image("MenuBarIcon", bundle: resourceBundle).accessibilityHidden(true)
                Text("Open Capture Bar for screenshots. Choose Recording options for video. After a capture, choose Edit on its preview to open the right editor.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).studioEffectCard()
            if permissions.status(.screen) != .allowed {
                Label("Screen access is not enabled. You can review it now or try a practice image below.", systemImage: "exclamationmark.circle")
                    .font(.callout)
                Button("Review Permissions") { step = .permissions }
            } else {
                Button("Open Recording Options") {
                    OnboardingWindowController.shared.finish(openCaptureBar: true, recordingOptions: true)
                }
            }
            Text("Try a first edit").font(.headline)
            HStack(spacing: 14) {
                ForEach(OnboardingSample.allCases) { sample in
                    VStack(alignment: .leading, spacing: 10) {
                        samplePreview(sample, caption: sample.title)
                        Button("Edit This Sample") { openSample(sample) }
                            .accessibilityLabel("Edit \(sample.title) sample")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Practice uses a separate copy in the real editor. Your original captures stay untouched.")
                .font(.callout).foregroundStyle(.secondary)
            feature("Everything is still here later", symbol: "questionmark.circle",
                    detail: "Reopen Getting Started from the clover menu to review features or permissions. Customize shortcuts and your separate image/video default backgrounds in Settings.")
            Label("No account. Files stay on your Mac unless you choose cloud sharing.", systemImage: "lock")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 26, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func workflowStage(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity)
    }

    private func samplePreview(_ sample: OnboardingSample, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let url = sample.sourceURL(in: resourceBundle), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 155).frame(maxWidth: .infinity)
                    .background(EditorChrome.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func feature(_ title: String, symbol: String, action: ShortcutService.Action? = nil, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol).font(.headline)
                if let action, let shortcut = ShortcutService.shared.effectiveShortcut(for: action) {
                    Spacer(minLength: 4)
                    Text(shortcut.displayString).font(.callout.monospaced()).foregroundStyle(.secondary)
                        .fixedSize().accessibilityLabel(shortcut.accessibilityDescription)
                }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openSample(_ sample: OnboardingSample) {
        errorMessage = nil
        guard let openEditor = PreviewPanelPresenter.shared.onAnnotate else {
            errorMessage = "The editor isn’t ready yet. Try Edit This Sample again in a moment."
            return
        }
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("BetterShot/Practice", isDirectory: true)
            let url = try sample.makeWorkingCopy(in: directory, bundle: resourceBundle)
            OnboardingWindowController.shared.finish()
            openEditor(url)
        } catch {
            errorMessage = "Couldn’t prepare the sample. Check that your Mac has free space, then try Edit This Sample again."
        }
    }
}
