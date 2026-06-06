import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        VStack(spacing: 0) {
            captureGrid
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            TrayDivider()

            utilityGrid
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if PinnedScreenshotController.shared.hasPinnedWindows {
                TrayDivider()

                TrayFullWidthButton(title: "Unpin All", icon: "pin.slash") {
                    PinnedScreenshotController.shared.unpinAll()
                    dismiss()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            TrayDivider()

            footerGrid
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            versionLabel
                .padding(.bottom, 8)
        }
        .frame(width: 290)
    }

    // MARK: - Capture Grid

    private var captureGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            TrayGridButton(title: "Region", icon: "rectangle.dashed", shortcut: "\u{2318}4") {
                dismissAndRun(.region)
            }

            TrayGridButton(title: "Screen", icon: "desktopcomputer", shortcut: "\u{2318}3") {
                dismissAndRun(.fullscreen)
            }

            TrayGridButton(title: "Window", icon: "macwindow") {
                dismissAndRun(.window)
            }

            TrayGridButton(title: "Pick Color", icon: "eyedropper") {
                dismissAndRun(.colorPicker)
            }
        }
    }

    // MARK: - Utility Grid

    private var utilityGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            TrayGridButton(title: "OCR", icon: "doc.text.viewfinder", shortcut: "\u{2318}O") {
                dismissAndRun(.ocr)
            }

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
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 16)

                    Text("Recent")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.25))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer

    private var footerGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            TrayGridButton(title: "Settings", icon: "gearshape", shortcut: "\u{2318},") {
                openSettings()
            }

            TrayGridButton(title: "Quit", icon: "power", shortcut: "\u{2318}Q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Version

    private var versionLabel: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.3"
        return Text("Version \(version)")
            .font(.system(size: 10))
            .foregroundStyle(.quaternary)
    }

    // MARK: - Actions

    private func dismissAndRun(_ action: ShortcutService.Action) {
        dismiss()
        Task.detached {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await CaptureOrchestrator.shared.performCapture(action)
        }
    }

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction()
        dismiss()
    }
}

// MARK: - Grid Button

private struct TrayGridButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.25))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Full Width Button

private struct TrayFullWidthButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .medium))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Divider

private struct TrayDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}
