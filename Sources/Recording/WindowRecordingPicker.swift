import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
struct WindowRecordingPicker {
    static func pick(from windows: [SCWindow]) async -> SCWindow? {
        let windowID: CGWindowID? = await withCheckedContinuation { (continuation: CheckedContinuation<CGWindowID?, Never>) in
            var resumed = false
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Choose a Window to Record"
            panel.isReleasedWhenClosed = false

            let items = windows.map { WindowItem(id: $0.windowID, title: $0.title ?? "Untitled", appName: $0.owningApplication?.applicationName ?? "", bundleID: $0.owningApplication?.bundleIdentifier, width: Int($0.frame.width), height: Int($0.frame.height)) }

            let view = WindowPickerListView(windows: items) { selectedID in
                guard !resumed else { return }
                resumed = true
                panel.close()
                continuation.resume(returning: selectedID)
            }
            panel.contentView = NSHostingView(rootView: view)
            panel.center()
            panel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }

        guard let windowID else { return nil }
        return windows.first { $0.windowID == windowID }
    }
}

private struct WindowItem: Identifiable, Sendable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleID: String?
    let width: Int
    let height: Int
}

private struct WindowPickerListView: View {
    let windows: [WindowItem]
    let onSelect: @MainActor (CGWindowID?) -> Void

    @State private var selectedID: CGWindowID?

    var body: some View {
        VStack(spacing: 0) {
            List(windows, selection: $selectedID) { window in
                HStack(spacing: 10) {
                    if let icon = iconForApp(window.bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "macwindow")
                            .frame(width: 24, height: 24)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(window.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(window.appName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(window.width) x \(window.height)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .tag(window.id)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onSelect(nil)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Record") {
                    if let id = selectedID {
                        onSelect(id)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedID == nil)
            }
            .padding(12)
        }
    }

    private func iconForApp(_ bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
