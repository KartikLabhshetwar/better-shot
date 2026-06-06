import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 2) {
            // Capture actions
            Group {
                MenuBarButton(
                    title: "Capture Region",
                    icon: "rectangle.dashed",
                    shortcut: "4",
                    modifiers: [.command, .shift]
                ) {
                    Task { await CaptureOrchestrator.shared.performCapture(.region) }
                }

                MenuBarButton(
                    title: "Full Screen",
                    icon: "desktopcomputer",
                    shortcut: "3",
                    modifiers: [.command, .shift]
                ) {
                    Task { await CaptureOrchestrator.shared.performCapture(.fullscreen) }
                }

                Button {
                    Task { await CaptureOrchestrator.shared.performCapture(.window) }
                } label: {
                    Label("Window", systemImage: "macwindow")
                }
            }

            MenuBarSeparator()

            // Utilities
            Group {
                MenuBarButton(
                    title: "Copy Text (OCR)",
                    icon: "doc.text.viewfinder",
                    shortcut: "o",
                    modifiers: [.command, .shift]
                ) {
                    Task { await CaptureOrchestrator.shared.performCapture(.ocr) }
                }

                MenuBarButton(
                    title: "Pick Color",
                    icon: "eyedropper",
                    shortcut: "c",
                    modifiers: [.command, .shift]
                ) {
                    Task { await CaptureOrchestrator.shared.performCapture(.colorPicker) }
                }
            }

            if PinnedScreenshotController.shared.hasPinnedWindows {
                MenuBarSeparator()

                MenuBarButton(
                    title: "Unpin All",
                    icon: "pin.slash"
                ) {
                    PinnedScreenshotController.shared.unpinAll()
                }
            }

            MenuBarSeparator()

            // Recent captures
            Menu {
                if HistoryStore.shared.records.isEmpty {
                    Text("No captures yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(HistoryStore.shared.records.prefix(8)) { record in
                        Button {
                            let url = HistoryStore.shared.urlForRecord(record)
                            EditorWindowController.shared.open(url: url)
                        } label: {
                            Label(record.filename, systemImage: "photo")
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Recent Captures")
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)

            MenuBarSeparator()

            // Footer
            Group {
                MenuBarButton(
                    title: "Settings",
                    icon: "gearshape",
                    shortcut: ",",
                    modifiers: .command
                ) {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }

                MenuBarButton(
                    title: "Quit BetterShot",
                    icon: "power",
                    shortcut: "q",
                    modifiers: .command
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Menu Bar Components

private struct MenuBarButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var modifiers: EventModifiers = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .modifier(ShortcutModifier(shortcut: shortcut, modifiers: modifiers))
    }
}

private struct ShortcutModifier: ViewModifier {
    let shortcut: String?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let key = shortcut {
            content.keyboardShortcut(KeyEquivalent(Character(key)), modifiers: modifiers)
        } else {
            content
        }
    }
}

private struct MenuBarSeparator: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }
}
