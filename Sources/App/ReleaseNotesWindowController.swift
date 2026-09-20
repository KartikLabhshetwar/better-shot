import AppKit
import SwiftUI

@MainActor
final class ReleaseNotesWindowController: NSObject, NSWindowDelegate {
    static let shared = ReleaseNotesWindowController()
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    private var window: NSWindow?
    private var presentedVersion: String?
    private var opensCaptureBarOnClose = false

    static func load(in bundle: Bundle = .main) throws -> [ReleaseNotes] {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md") else { throw CocoaError(.fileNoSuchFile) }
        return ReleaseNotes.parse(try String(contentsOf: url, encoding: .utf8))
    }

    @discardableResult
    func show(onlyIfNew: Bool = false, opensCaptureBarOnClose: Bool = true) -> Bool {
        if let window { window.makeKeyAndOrderFront(nil); return true }
        let version = Self.currentVersion
        let releases = (try? Self.load()) ?? []
        let notes = onlyIfNew ? ReleaseNotes.pending(in: releases, current: version)
            : releases.filter { $0.version == version }
        if onlyIfNew && notes.isEmpty { return false }
        let view = ReleaseNotesView(version: version, notes: notes) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "What’s New in BetterShot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 660))
        window.contentMinSize = NSSize(width: 420, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        presentedVersion = notes.isEmpty ? nil : version
        self.opensCaptureBarOnClose = onlyIfNew && opensCaptureBarOnClose
        AppActivationPolicy.enter()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if let presentedVersion { ReleaseNotes.markSeen(presentedVersion) }
        presentedVersion = nil
        window = nil
        AppActivationPolicy.leave()
        let opensCaptureBar = opensCaptureBarOnClose
        opensCaptureBarOnClose = false
        if opensCaptureBar, !ScreenRecordingManager.shared.isActive,
           UserDefaults.standard.object(forKey: AppPreferences.showCaptureBarAtLaunchKey) as? Bool ?? true {
            RecordingBarPresenter.shared.showPicker(activate: false)
        }
    }
}

struct ReleaseNotesView: View {
    let version: String
    let notes: [ReleaseNotes]
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable().frame(width: 48, height: 48).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("What’s new in BetterShot").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Version \(version)").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if notes.isEmpty {
                        Text("Release notes couldn’t be loaded. Read them on GitHub using the link below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, release in
                        if notes.count > 1 {
                            Text("Version \(release.version)").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                        }
                        ForEach(Array(release.body.replacingOccurrences(of: "\n- ", with: "\n\n- ").components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            if paragraph.hasPrefix("### ") {
                                Text(String(paragraph.dropFirst(4))).font(.headline).accessibilityAddTraits(.isHeader)
                            } else {
                                Text((try? AttributedString(markdown: paragraph,
                                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
                                    baseURL: URL(string: "https://github.com/KartikLabhshetwar/better-shot/blob/main/"))) ?? AttributedString(paragraph))
                                    .font(.callout).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.scrollIndicators(.hidden)
            Divider()
            HStack {
                Link("All Release Notes", destination: URL(string: "https://github.com/KartikLabhshetwar/better-shot/blob/main/CHANGELOG.md")!)
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(EditorButtonStyle(selected: true, horizontalPadding: 20))
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .background(EditorChrome.workspace).tint(EditorChrome.accent)
        .onExitCommand(perform: onClose)
    }
}
