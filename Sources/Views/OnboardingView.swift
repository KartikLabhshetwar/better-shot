import AppKit
import Combine
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, permissions, shortcuts, ready

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .permissions: "Permissions"
            case .shortcuts: "Shortcuts"
            case .ready: "First Capture"
            }
        }
    }

    @State var step: Step = .welcome
    var resourceBundle: Bundle = .main
    @State private var permissions = OnboardingPermissions(resumesOnboarding: true)
    @State private var errorMessage: String?
    @State private var showsOptionalPermissions = false
    private let permissionRefresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            switch step {
                            case .welcome: welcome
                            case .permissions: permissionSetup
                            case .shortcuts: shortcuts
                            case .ready: ready
                            }
                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle")
                                    .font(.callout).foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: 560)
                        .padding(32)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        .id("stepContent")
                    }
                }
                .onChange(of: step) { _, _ in
                    errorMessage = nil
                    proxy.scrollTo("stepContent", anchor: .top)
                    permissions.refresh()
                }
            }
            navigation
        }
        .background(EditorChrome.workspace)
        .tint(EditorChrome.accent)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
        .onReceive(permissionRefresh) { _ in
            if step != .welcome { permissions.refresh() }
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button { step = Step(rawValue: step.rawValue - 1) ?? .welcome } label: {
                    Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                .buttonStyle(EditorButtonStyle())
                .accessibilityLabel("Previous step")
                .help("Back")
            }
            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.self) { item in
                    Button { step = item } label: {
                        Capsule()
                            .fill(item == step ? EditorChrome.accent : Color.primary.opacity(0.18))
                            .frame(width: item == step ? 24 : 10, height: 4)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step \(item.rawValue + 1): \(item.title)")
                    .accessibilityAddTraits(item == step ? .isSelected : [])
                    .help(item.title)
                }
            }
            Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Set Up Later") { OnboardingWindowController.shared.finish(openCaptureBar: true) }
                .buttonStyle(EditorButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button(nextTitle) {
                if step == .ready {
                    OnboardingWindowController.shared.finish(openCaptureBar: true)
                } else {
                    step = Step(rawValue: step.rawValue + 1) ?? .ready
                }
            }
            .buttonStyle(EditorButtonStyle(selected: true, horizontalPadding: 16))
            .keyboardShortcut(.defaultAction)
        }
        .disabled(permissions.requesting != nil)
        .padding(12)
        .studioGlass(cornerRadius: 10)
        .padding(10)
    }

    private var nextTitle: String {
        switch step {
        case .welcome: "Start Setup"
        case .permissions: permissions.status(.screen) == .allowed ? "Continue" : "Continue Without Access"
        case .shortcuts: "Continue"
        case .ready: "Open Capture Bar"
        }
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Image(nsImage: resourceBundle.image(forResource: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable().frame(width: 88, height: 88).accessibilityHidden(true)
            heading("A better way to show it.",
                detail: "Capture a moment. Explain an idea. Turn your screen into something worth sharing.")
            HStack(alignment: .top, spacing: 20) {
                feature("Screenshots", symbol: "rectangle.dashed", detail: "Capture, annotate, and frame.")
                feature("Recordings", symbol: "video", detail: "Record, refine, and export.")
            }
            .padding(24).studioEffectCard()
            Text("A quick setup, then your first capture.")
                .font(.callout).foregroundStyle(.secondary)
            Label("No account needed. Your files stay on your Mac.", systemImage: "lock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var permissionSetup: some View {
        VStack(spacing: 20) {
            heading("A little access. You’re in control.",
                detail: "Enable screen access for screenshots and recordings. Everything else is optional.")
            permissionRow(.screen)
            DisclosureGroup(isExpanded: $showsOptionalPermissions) {
                VStack(spacing: 10) {
                    ForEach(OnboardingPermission.allCases.filter { $0 != .screen }) { permission in
                        permissionRow(permission)
                    }
                }
                .padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional permissions").font(.headline)
                    Text("Global shortcuts, pointer effects, microphone, and camera")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if permissions.shortcutsNeedRestart {
                Label("Accessibility is allowed, but shortcuts aren’t active yet. Save your work, then quit and reopen BetterShot.", systemImage: "arrow.clockwise")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = permissions.settingsError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Text("Status updates when you return from System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Check Again") { permissions.refresh() }
                    .disabled(permissions.requesting != nil)
            }
            Text("Prefer to explore first? Continue without access and try a practice image.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func permissionRow(_ permission: OnboardingPermission) -> some View {
        OnboardingPermissionRow(permission: permission, status: permissions.status(permission),
            attempted: permissions.attempted.contains(permission),
            isRequesting: permissions.requesting == permission,
            requestsDisabled: permissions.requesting != nil,
            request: { Task { await permissions.request(permission) } },
            openSettings: { permissions.openSettings(permission) })
    }

    private var shortcuts: some View {
        VStack(spacing: 22) {
            heading("Your next capture is a shortcut away.",
                detail: "Open the capture bar from any app. Pick a screenshot or recording, then make it yours.")
            VStack(spacing: 12) {
                shortcutValue(.recording, size: 36)
                Text("Open Capture Bar").font(.headline)
            }
            .frame(maxWidth: .infinity).padding(24).studioEffectCard()
            VStack(spacing: 0) {
                shortcutRow("Region screenshot", symbol: "rectangle.dashed", action: .region)
                Divider().padding(.leading, 40)
                shortcutRow("Fullscreen screenshot", symbol: "display", action: .fullscreen)
                Divider().padding(.leading, 40)
                shortcutRow("Recording options", symbol: "video", action: .recordingOptions)
            }
            if permissions.status(.accessibility) != .allowed || permissions.shortcutsNeedRestart {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                    Text(permissions.shortcutsNeedRestart
                         ? "Save your work and reopen BetterShot to activate shortcuts. The clover menu works now."
                         : "Global shortcuts need Accessibility access. You can always use the clover in your menu bar.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Review Access") {
                        showsOptionalPermissions = true
                        step = .permissions
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            Text("These are your current bindings. Change them anytime in Settings → Shortcuts.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            heading("Make your first capture.",
                detail: "BetterShot lives in your menu bar. Look for the clover whenever you need it.")
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Text("Your Mac").font(.caption.weight(.medium))
                    Spacer()
                    Image("MenuBarIcon", bundle: resourceBundle)
                        .padding(7).background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }
                .foregroundStyle(.secondary).padding(12)
                Divider()
                HStack(alignment: .top, spacing: 24) {
                    feature("Take a screenshot", symbol: "rectangle.dashed", detail: "Choose Area, select a region, then click Edit on the preview.")
                    feature("Record a walkthrough", symbol: "video", detail: "Choose Recording, pick a source, then stop to open the editor.")
                }
                .padding(20)
            }
            .studioEffectCard()
            if permissions.status(.screen) != .allowed {
                HStack {
                    Label("Screen access is still off. Practice works without it.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Enable Access") { step = .permissions }
                }
            }
            HStack(spacing: 16) {
                ForEach(OnboardingSample.allCases) { sample in
                    Button { openSample(sample) } label: {
                        HStack(spacing: 10) {
                            if let url = sample.sourceURL(in: resourceBundle), let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 48).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Try a practice edit").font(.callout.weight(.medium))
                                Text(sample.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10).studioEffectCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(sample.title) practice image")
                }
            }
            Text("Practice opens a separate copy in the real editor. Add an arrow, change the background, then export.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Revisit this guide from Getting Started in the clover menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.system(size: 30, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcutRow(_ title: String, symbol: String, action: ShortcutService.Action) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title)
            Spacer()
            shortcutValue(action, size: 15)
        }
        .padding(.vertical, 12)
    }

    private func shortcutValue(_ action: ShortcutService.Action, size: CGFloat) -> some View {
        Group {
            if let shortcut = ShortcutService.shared.effectiveShortcut(for: action) {
                Text(shortcut.displayString).font(.system(size: size, weight: .medium, design: .monospaced))
                    .accessibilityLabel(shortcut.accessibilityDescription)
            } else {
                Text("Shortcut disabled").font(.callout).foregroundStyle(.secondary)
            }
        }
        .fixedSize()
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
