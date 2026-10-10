import AppKit
import Combine
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, ready

    var title: String {
        switch self {
        case .welcome: "Capture anything on your screen"
        case .permissions: "Allow screen capture"
        case .ready: "Take your first capture"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "Screenshots and recordings, polished and ready to share."
        case .permissions: "Screen capture is required. Turn on the others for the features you use."
        case .ready: "Choose Area for a screenshot, or Recording for a video."
        }
    }

    var symbol: String? {
        switch self {
        case .welcome: nil
        case .permissions: "hand.raised.fill"
        case .ready: "viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: EditorChrome.accent
        case .permissions: .blue
        case .ready: .orange
        }
    }
}

struct OnboardingView: View {
    private static let permissionList: [OnboardingPermission] = [.screen, .accessibility, .microphone, .camera]

    @State var step: OnboardingStep = .welcome
    var resourceBundle: Bundle = .main
    var isPermissionPreview = ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1"
    @State private var forward = true
    @State private var permissions = OnboardingPermissions(resumesOnboarding: true)
    @State private var errorMessage: String?
    @State private var demo: OnboardingDemo = .screenshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let permissionRefresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                GeometryReader { geometry in
                    ScrollView {
                        page.frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                }
                .id(step)
                .transition(pageTransition)
            }
            .clipped()
            bottomBar
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

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private var page: some View {
        VStack(spacing: 28) {
            hero.frame(height: 96)
            VStack(spacing: 10) {
                Text(step.title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(step.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    @ViewBuilder private var hero: some View {
        if let symbol = step.symbol {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(step.tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(nsImage: resourceBundle.image(forResource: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: permissionSetup
        case .ready: ready
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                if let shortcut = ShortcutService.shared.effectiveShortcut(for: .region) {
                    Text("Press \(shortcut.displayString) to capture an area")
                        .accessibilityLabel("Press \(shortcut.accessibilityDescription) to capture an area")
                } else {
                    Text("Capture an area from the clover in your menu bar")
                }
            } icon: {
                Image(systemName: "rectangle.dashed")
            }
            Label("Add arrows, text, and a soft background", systemImage: "pencil.tip.crop.circle")
            Label("Record your screen with zoom and 3D shots", systemImage: "record.circle")
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .labelStyle(OnboardingLabelStyle())
    }

    private var permissionSetup: some View {
        VStack(spacing: 12) {
            if isPermissionPreview {
                Label("Preview only. Open BetterShot to grant permissions.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Form {
                Section {
                    ForEach(Self.permissionList) { permission in
                        permissionRow(permission)
                    }
                } footer: {
                    Text("Microphone and camera stay off until you choose them for a recording. Access updates when you return here.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            if permissions.shortcutsNeedRestart {
                Label("Save your work and reopen BetterShot to activate shortcuts.", systemImage: "arrow.clockwise")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(_ permission: OnboardingPermission) -> some View {
        OnboardingPermissionRow(permission: permission, status: permissions.status(permission),
            attempted: permissions.attempted.contains(permission),
            isRequesting: permissions.requesting == permission,
            requestsDisabled: permissions.requesting != nil || isPermissionPreview,
            errorMessage: permissions.settingsErrorPermission == permission ? permissions.settingsError : nil,
            isFormRow: true,
            request: { Task { await permissions.request(permission) } },
            openSettings: { permissions.openSettings(permission) })
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Form {
                Section {
                    LabeledContent {
                        shortcutValue(.recording)
                    } label: {
                        Text("Open the capture bar")
                        Text("Capture an area, a window, or a recording.")
                    }
                    LabeledContent {
                        Image("MenuBarIcon", bundle: resourceBundle).accessibilityHidden(true)
                    } label: {
                        Text("Find the clover in your menu bar")
                        Text("Your captures and tools are always there.")
                    }
                    if permissions.status(.accessibility) != .allowed || permissions.shortcutsNeedRestart {
                        LabeledContent {
                            Button("Enable Shortcuts") { go(to: .permissions) }
                        } label: {
                            Text("Shortcuts are off")
                            Text(permissions.shortcutsNeedRestart
                                 ? "Reopen BetterShot to activate them. The clover menu works now."
                                 : "They need Accessibility access. The clover menu works without it.")
                        }
                    }
                    if permissions.status(.screen) != .allowed {
                        LabeledContent {
                            Button("Allow Access") { go(to: .permissions) }
                        } label: {
                            Text("Screen access is off")
                            Text("The practice image works without it.")
                        }
                    }
                    practiceRow
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Watch a short demo") {
                VStack(spacing: 12) {
                    Picker("Explore BetterShot", selection: $demo) {
                        ForEach(OnboardingDemo.allCases) { demo in Text(demo.title).tag(demo) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    OnboardingDemoView(demo: demo, resourceBundle: resourceBundle).id(demo)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
    }

    private var practiceRow: some View {
        Button { openSample(.coast) } label: {
            HStack(spacing: 12) {
                if let url = OnboardingSample.coast.sourceURL(in: resourceBundle), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 36).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try a practice image")
                    Text("Add an arrow, change the background, then export.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a separate copy in the image editor. No screen access needed.")
    }

    private func shortcutValue(_ action: ShortcutService.Action) -> some View {
        Group {
            if let shortcut = ShortcutService.shared.effectiveShortcut(for: action) {
                Text(shortcut.displayString).font(.system(.body, design: .monospaced).weight(.medium))
                    .accessibilityLabel(shortcut.accessibilityDescription)
            } else {
                Text("Shortcut disabled").foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    private var bottomBar: some View {
        HStack {
            if step == .welcome {
                Button("Skip") { OnboardingWindowController.shared.finish(openCaptureBar: true) }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Back") { go(to: OnboardingStep(rawValue: step.rawValue - 1)) }
            }
            Spacer()
            if step == .ready {
                Button("Open Capture Bar") { OnboardingWindowController.shared.finish(openCaptureBar: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { go(to: OnboardingStep(rawValue: step.rawValue + 1)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .overlay { progressDots }
        .controlSize(.large)
        .disabled(permissions.requesting != nil)
        .padding(20)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? EditorChrome.accent : Color.secondary.opacity(0.3))
                    .frame(width: item == step ? 20 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    private func go(to target: OnboardingStep?) {
        guard let target, target != step else { return }
        forward = target.rawValue > step.rawValue
        errorMessage = nil
        withAnimation(.easeOut(duration: 0.2)) { step = target }
        permissions.refresh()
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

private struct OnboardingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .foregroundStyle(EditorChrome.accent)
                .frame(width: 22)
            configuration.title
        }
    }
}
