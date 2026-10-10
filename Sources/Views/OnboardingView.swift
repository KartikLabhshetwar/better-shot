import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, saving, practice

    var title: String {
        switch self {
        case .welcome: "Capture anything on your screen"
        case .permissions: "Two quick permissions"
        case .saving: "Choose where screenshots go"
        case .practice: "Try it now"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "Screenshots and recordings, polished and ready to share."
        case .permissions: "BetterShot needs screen access to capture. Accessibility lets your shortcuts work in any app."
        case .saving: "Every capture opens in a preview first. Keep a copy in your folder, or save only when you choose."
        case .practice: "Take a screenshot and watch it land here."
        }
    }

    var symbol: String? {
        switch self {
        case .welcome: nil
        case .permissions: "hand.raised.fill"
        case .saving: "folder.fill"
        case .practice: "viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: EditorChrome.accent
        case .permissions: .blue
        case .saving: .purple
        case .practice: .orange
        }
    }
}

struct OnboardingView: View {
    private static let permissionList: [OnboardingPermission] = [.screen, .accessibility]

    @State var step: OnboardingStep = .welcome
    var resourceBundle: Bundle = .main
    var isPermissionPreview = ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1"
    @State private var forward = true
    @State private var permissions = OnboardingPermissions()
    @State private var practiceStart = CaptureOrchestrator.shared.lastCaptureURL
    @State private var practiceThumbnail: NSImage?
    @State private var errorMessage: String?
    @AppStorage("bs_saveDirectory") private var saveDirectory = AppPreferences.saveDirectory
    @AppStorage(AfterCaptureAction.save.storageKey(for: .screenshot))
    private var savesScreenshots = AfterCaptureAction.save.defaultValue(for: .screenshot)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var capture: CaptureOrchestrator { .shared }
    private var regionShortcut: ShortcutService.Shortcut? { ShortcutService.shared.effectiveShortcut(for: .region) }
    private var practiceCapture: URL? { capture.lastCaptureURL == practiceStart ? nil : capture.lastCaptureURL }

    var body: some View {
        VStack(spacing: 0) {
            page
                .id(step)
                .transition(pageTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(EditorChrome.workspace)
        .tint(EditorChrome.accent)
        .frame(minWidth: 520, minHeight: 560)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
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
    }

    @ViewBuilder private var hero: some View {
        if let symbol = step.symbol {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(step.tint.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        case .saving: saving
        case .practice: practice
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(captureHint(spoken: false)).accessibilityLabel(captureHint(spoken: true))
            } icon: {
                Image(systemName: "rectangle.dashed")
            }
            Label("Add arrows, text, and a soft background", systemImage: "pencil.tip.crop.circle")
            Label("Record your screen with zoom and 3D shots", systemImage: "record.circle")
            Label {
                Text("Find everything in the clover in your menu bar")
            } icon: {
                Image("MenuBarIcon", bundle: resourceBundle)
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .labelStyle(OnboardingLabelStyle())
    }

    private var permissionSetup: some View {
        VStack(spacing: 12) {
            Form {
                ForEach(Self.permissionList) { permission in
                    OnboardingPermissionRow(permission: permission, status: permissions.status(permission),
                        attempted: permissions.attempted.contains(permission),
                        isRequesting: permissions.requesting == permission,
                        requestsDisabled: permissions.requesting != nil || isPermissionPreview,
                        errorMessage: permissions.settingsErrorPermission == permission ? permissions.settingsError : nil,
                        request: { Task { await permissions.request(permission) } },
                        openSettings: { permissions.openSettings(permission) })
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            if permissions.shortcutsNeedRestart {
                Label("Save your work and reopen BetterShot to turn on shortcuts.", systemImage: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            } else if isPermissionPreview {
                Label("Preview only. Open BetterShot to grant permissions.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var saving: some View {
        Form {
            Toggle(isOn: $savesScreenshots) {
                Text("Save screenshots automatically")
                Text(savesScreenshots ? "Each new screenshot is saved to your folder right away."
                                      : "Choose Save or Export when you want a file.")
            }
            .toggleStyle(.switch)
            LabeledContent {
                Button("Choose\u{2026}", action: chooseSaveDirectory)
            } label: {
                Text("Save folder")
                Text(URL(fileURLWithPath: saveDirectory).abbreviatedHomePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var practice: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                if let practiceThumbnail {
                    Image(nsImage: practiceThumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel("Your screenshot")
                } else {
                    Image(systemName: capture.captureInProgress ? "rectangle.dashed" : "viewfinder")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(EditorChrome.accent)
                        .accessibilityHidden(true)
                }
                Text(practiceText(spoken: false))
                    .accessibilityLabel(practiceText(spoken: true))
                    .font(practiceCapture == nil ? .body : .title3)
                    .foregroundStyle(practiceCapture == nil ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding(20)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 12) {
                Button("Capture an Area", systemImage: "rectangle.dashed", action: captureArea)
                    .disabled(capture.captureInProgress)
                Button("Open a Practice Image", systemImage: "photo") { openSample(.coast) }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { practiceStart = capture.lastCaptureURL }
        .task(id: practiceCapture) {
            guard let url = practiceCapture else {
                practiceThumbnail = nil
                return
            }
            let decoded = await Task.detached(priority: .utility) {
                HistoryStore.decodeThumbnail(.init(url: url, kind: .screenshot), maxSize: 480)
            }.value
            guard !Task.isCancelled else { return }
            practiceThumbnail = decoded
        }
    }

    private func captureHint(spoken: Bool) -> String {
        guard let regionShortcut else { return "Capture an area from the capture bar" }
        return "Press \(spoken ? regionShortcut.accessibilityDescription : regionShortcut.displayString) to capture an area"
    }

    private func practiceText(spoken: Bool) -> String {
        if practiceCapture != nil { return "Nice. Your screenshot is ready in the floating preview." }
        if capture.captureInProgress { return "Drag across any part of your screen." }
        guard let regionShortcut else { return "Click Capture an Area, then drag across any part of your screen." }
        return "Press \(spoken ? regionShortcut.accessibilityDescription : regionShortcut.displayString), then drag across any part of your screen."
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
            if step == .practice {
                Button("Done") { OnboardingWindowController.shared.finish(openCaptureBar: true) }
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
        guard let target else { return }
        forward = target.rawValue > step.rawValue
        errorMessage = nil
        withAnimation(.easeOut(duration: 0.2)) { step = target }
        OnboardingState.save(step: target.rawValue)
        permissions.refresh()
    }

    private func captureArea() {
        let screen = ActiveDisplayResolver.screenForScreenshotCapture()
        Task { await CaptureOrchestrator.shared.performCapture(.region, on: screen) }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose where BetterShot saves new screenshots and recordings."
        panel.directoryURL = URL(fileURLWithPath: saveDirectory)
        if panel.runModal() == .OK, let url = panel.url { saveDirectory = url.path }
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
            errorMessage = "Couldn’t prepare the practice image. Check that your Mac has free space, then try again."
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
