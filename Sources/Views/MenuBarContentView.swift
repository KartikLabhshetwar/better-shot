import SwiftUI

// MARK: - Panel Root (Arrow + Body)

struct MenuBarPanelView: View {
    var dismissPopover: @MainActor () -> Void
    @State private var isVisible = false

    private let arrowWidth: CGFloat = 22
    private let arrowHeight: CGFloat = 10
    private let panelRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            PopoverArrow()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: arrowWidth, height: arrowHeight)

            MenuBarContentView(dismissPopover: dismissPopover)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .scaleEffect(isVisible ? 1 : 0.92, anchor: .top)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 4)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Arrow Shape

private struct PopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 2.5
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - radius, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + radius, y: rect.minY + radius),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Panel Content

struct MenuBarContentView: View {
    var dismissPopover: @MainActor () -> Void
    @State private var screenshotMode = AppPreferences.screenshotMode

    var body: some View {
        VStack(spacing: 0) {
            captureGrid
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            TrayDivider()

            screenshotModeRow
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            TrayDivider()

            utilityGrid
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if PinnedScreenshotController.shared.hasPinnedWindows {
                TrayDivider()

                TrayFullWidthButton(title: "Unpin All", icon: "pin.slash") {
                    PinnedScreenshotController.shared.unpinAll()
                    dismissPopover()
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

    // MARK: - Screenshot Mode

    private var screenshotModeRow: some View {
        HStack(spacing: 0) {
            Text("Screenshot mode")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $screenshotMode) {
                Text("Editor").tag(ScreenshotMode.editor)
                Text("Gallery").tag(ScreenshotMode.gallery)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .onChange(of: screenshotMode) { _, newValue in
                AppPreferences.screenshotMode = newValue
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
                            dismissPopover()
                            let url = HistoryStore.shared.urlForRecord(record)
                            PreviewOverlay.shared.show(url: url)
                        } label: {
                            Label(record.filename, systemImage: "photo")
                        }
                    }
                }
            } label: {
                TrayMenuLabel(title: "Recent", icon: "clock.arrow.circlepath")
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
        dismissPopover()
        Task.detached {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await CaptureOrchestrator.shared.performCapture(action)
        }
    }

    private func openSettings() {
        dismissPopover()
        SettingsWindowController.shared.open()
    }
}

// MARK: - Grid Button

struct TrayGridButton: View {
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

// MARK: - Menu Label (matches grid button style)

struct TrayMenuLabel: View {
    let title: String
    let icon: String

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 16)

            Text(title)
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
                .fill(isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.08))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
