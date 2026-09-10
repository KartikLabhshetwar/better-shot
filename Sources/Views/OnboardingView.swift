import AppKit
import Combine
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, permissions, ready

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .permissions: "Permissions"
            case .ready: "First Capture"
            }
        }
    }

    @State var step: Step = .welcome
    var resourceBundle: Bundle = .main
    var isPermissionPreview = ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1"
    @State private var permissions = OnboardingPermissions(resumesOnboarding: true)
    @State private var errorMessage: String?
    @State private var demo: OnboardingDemo = .screenshot
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
                            case .ready: ready
                            }
                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle")
                                    .font(.callout).foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: 560)
                        .padding(24)
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
            Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Skip Setup") { OnboardingWindowController.shared.finish(openCaptureBar: true) }
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
        .padding(20)
        .background(EditorChrome.workspace)
        .overlay(alignment: .top) { Divider() }
    }

    private var nextTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .permissions: "Continue"
        case .ready: "Open Capture Bar"
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: resourceBundle.image(forResource: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable().frame(width: 48, height: 48).accessibilityHidden(true)
                heading("Welcome to BetterShot",
                    detail: "Capture, edit, and share screenshots and screen recordings.")
            }
            Picker("Explore BetterShot", selection: $demo) {
                ForEach(OnboardingDemo.allCases) { demo in
                    Text(demo.title).tag(demo)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            OnboardingDemoView(demo: demo, resourceBundle: resourceBundle)
                .id(demo)
        }
    }

    private var permissionSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Set up permissions",
                detail: "Allow screen capture to get started. Choose the other features you’ll use.")
            if isPermissionPreview {
                Label("Preview only. Open BetterShot to grant permissions.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(OnboardingPermission.allCases) { permission in
                    permissionRow(permission)
                }
            }
            Text("Microphone and camera stay off until you choose them for a recording.")
                .font(.caption).foregroundStyle(.secondary)
            if permissions.shortcutsNeedRestart {
                Label("Save your work and reopen BetterShot to activate shortcuts.", systemImage: "arrow.clockwise")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("Access updates when you return here.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Check Again") { permissions.refresh() }
                    .buttonStyle(EditorButtonStyle(bordered: true))
                    .disabled(permissions.requesting != nil || isPermissionPreview)
            }
        }
    }

    private func permissionRow(_ permission: OnboardingPermission) -> some View {
        OnboardingPermissionRow(permission: permission, status: permissions.status(permission),
            attempted: permissions.attempted.contains(permission),
            isRequesting: permissions.requesting == permission,
            requestsDisabled: permissions.requesting != nil || isPermissionPreview,
            errorMessage: permissions.settingsErrorPermission == permission ? permissions.settingsError : nil,
            request: { Task { await permissions.request(permission) } },
            openSettings: { permissions.openSettings(permission) })
    }

    private var ready: some View {
        VStack(spacing: 16) {
            heading("Take your first capture", detail: "Choose Area for a screenshot, or Recording for a video.")
            HStack(spacing: 14) {
                Image("MenuBarIcon", bundle: resourceBundle)
                    .padding(12).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find the clover in your menu bar").font(.headline)
                    Text("Your captures and tools are always there.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16).studioEffectCard()
            shortcutRow("Open capture bar", symbol: "rectangle.bottomthird.inset.filled", action: .recording)
            if permissions.status(.accessibility) != .allowed || permissions.shortcutsNeedRestart {
                HStack(alignment: .top, spacing: 12) {
                    Text(permissions.shortcutsNeedRestart
                         ? "Reopen BetterShot to activate shortcuts. The clover menu works now."
                         : "Shortcuts need Accessibility access. The clover menu works without it.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Enable Shortcuts") {
                        step = .permissions
                    }
                }
            }
            if permissions.status(.screen) != .allowed {
                HStack {
                    Text("Screen access is off. Practice works without it.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Allow Access") { step = .permissions }
                }
            }
            Button { openSample(.coast) } label: {
                HStack(spacing: 14) {
                    if let url = OnboardingSample.coast.sourceURL(in: resourceBundle), let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 60).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Try a practice image").font(.headline)
                        Text("Add an arrow, change the background, then export.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .padding(14).studioEffectCard()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a separate copy in the image editor. No screen access needed.")
            Text("Change your shortcuts anytime in Settings → Shortcuts.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 30, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
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
            errorMessage = "The editor isn’t ready yet. Try the practice image again in a moment."
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
            errorMessage = "Couldn’t prepare the sample. Check that your Mac has free space, then try the practice image again."
        }
    }
}
