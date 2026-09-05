import SwiftUI

// MARK: - Panel Root (Arrow + Body)

struct MenuBarPanelView: View {
    var dismissPopover: @MainActor () -> Void
    @State private var isVisible = false

    private static let arrowHeight: CGFloat = 9

    var body: some View {
        MenuBarContentView(dismissPopover: dismissPopover)
            .padding(.top, Self.arrowHeight)
            .glassSurface(in: MenuBarPanelShape(arrowHeight: Self.arrowHeight), depth: .raised)
            .scaleEffect(isVisible ? 1 : 0.94, anchor: .top)
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 4)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .onAppear {
                withAnimation(RecordingMotion.showHideSpring) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Panel Shape

/// One continuous outline for the arrow and the body: two adjacent shapes would show a seam where their strokes meet.
private struct MenuBarPanelShape: Shape {
    var arrowHeight: CGFloat
    var arrowWidth: CGFloat = 22
    var cornerRadius: CGFloat = 12
    var tipRadius: CGFloat = 2.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.minY + arrowHeight
        let r = cornerRadius
        let half = arrowWidth / 2

        path.move(to: CGPoint(x: rect.minX + r, y: top))
        path.addLine(to: CGPoint(x: rect.midX - half, y: top))
        path.addLine(to: CGPoint(x: rect.midX - tipRadius, y: rect.minY + tipRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + tipRadius, y: rect.minY + tipRadius),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.midX + half, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: top + r), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: top + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: top + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Panel Content

struct MenuBarContentView: View {
    var dismissPopover: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 10) {
            captureGrid

            utilityStack

            if PinnedScreenshotController.shared.hasPinnedWindows {
                TrayFullWidthButton(title: "Unpin All Windows", icon: "pin.slash") {
                    PinnedScreenshotController.shared.unpinAll()
                    dismissPopover()
                }
            }

            TrayDivider()

            footerGrid

            versionLabel
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 296)
    }

    // MARK: - Capture Grid

    private static let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    private var captureGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            TrayGridButton(title: "Region", icon: "rectangle.dashed", action: .region) {
                dismissAndRun(.region)
            }

            TrayGridButton(title: "Screen", icon: "desktopcomputer", action: .fullscreen) {
                dismissAndRun(.fullscreen)
            }

            TrayGridButton(title: "Window", icon: "macwindow", action: .window) {
                dismissAndRun(.window)
            }

            TrayGridButton(title: "Record", icon: "record.circle", action: .recording) {
                dismissPopover()
                RecordingBarPresenter.shared.showPicker()
            }
        }
    }

    // MARK: - Utility Grid

    private var recentScreenshots: [CaptureRecord] {
        HistoryStore.shared.records.filter { $0.kind == .screenshot }
    }

    private var recentRecordings: [CaptureRecord] {
        HistoryStore.shared.records.filter { $0.kind == .recording }
    }

    private var utilityStack: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: Self.columns, spacing: 6) {
                TrayGridButton(title: "OCR", icon: "doc.text.viewfinder", action: .ocr) {
                    dismissAndRun(.ocr)
                }

                TrayGridButton(title: "Pick Color", icon: "eyedropper", action: .colorPicker) {
                    dismissAndRun(.colorPicker)
                }
            }

            TrayGridMenu(title: "Recent Captures", icon: "clock.arrow.circlepath", menuItems: recentMenuItems())
                .frame(height: 32)
        }
    }

    // MARK: - Footer

    private var footerGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            TrayGridButton(title: "Settings", icon: "gearshape") {
                openSettings()
            }

            TrayGridButton(title: "Quit", icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Version

    private var versionLabel: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let update = AppUpdater.shared.latestAvailableVersion

        return HStack(spacing: 5) {
            Text("Version \(version)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            if let update {
                Text("\u{00B7}")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text("\(update) available in Settings")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private var originScreen: NSScreen? {
        MenuBarPopoverController.shared.originScreen
    }

    private func dismissAndRun(_ action: ShortcutService.Action) {
        nonisolated(unsafe) let screen = ActiveDisplayResolver.screenForScreenshotCapture()
        dismissPopover()
        Task.detached {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await CaptureOrchestrator.shared.performCapture(action, on: screen)
        }
    }

    private func recentMenuItems() -> [TrayMenuItem] {
        var items: [TrayMenuItem] = []

        var screenshotItems: [TrayMenuItem] = []
        if recentScreenshots.isEmpty {
            screenshotItems.append(TrayMenuItem(title: "No screenshots yet", icon: "photo", action: {}, isDisabled: true))
        } else {
            for record in recentScreenshots.prefix(8) {
                screenshotItems.append(TrayMenuItem(title: record.filename, icon: "photo") { [record] in
                    let screen = ActiveDisplayResolver.screenForScreenshotCapture()
                    dismissPopover()
                    let url = HistoryStore.shared.displayURLForRecord(record)
                    PreviewOverlay.shared.show(url: url, on: screen)
                })
            }
            screenshotItems.append(.separator())
            screenshotItems.append(TrayMenuItem(title: "Clear Screenshots", icon: "trash", action: {
                HistoryStore.shared.records
                    .filter { $0.kind == .screenshot }
                    .forEach { HistoryStore.shared.deleteRecord($0) }
            }, isDestructive: true))
        }
        items.append(TrayMenuItem(title: "Screenshots", icon: "photo.on.rectangle", action: {}, submenu: screenshotItems))

        var recordingItems: [TrayMenuItem] = []
        if recentRecordings.isEmpty {
            recordingItems.append(TrayMenuItem(title: "No recordings yet", icon: "video", action: {}, isDisabled: true))
        } else {
            for record in recentRecordings.prefix(8) {
                recordingItems.append(TrayMenuItem(title: record.filename, icon: "video") { [record] in
                    let screen = ActiveDisplayResolver.screenForScreenshotCapture()
                    dismissPopover()
                    let url = HistoryStore.shared.displayURLForRecord(record)
                    PreviewOverlay.shared.show(url: url, on: screen)
                })
            }
            recordingItems.append(.separator())
            recordingItems.append(TrayMenuItem(title: "Clear Recordings", icon: "trash", action: {
                HistoryStore.shared.records
                    .filter { $0.kind == .recording }
                    .forEach { HistoryStore.shared.deleteRecord($0) }
            }, isDestructive: true))
        }
        items.append(TrayMenuItem(title: "Recordings", icon: "video.circle", action: {}, submenu: recordingItems))

        return items
    }

    private func openSettings() {
        let screen = originScreen
        dismissPopover()
        SettingsWindowController.shared.open(on: screen)
    }

}

// MARK: - Grid Button

struct TrayGridButton: View {
    let title: String
    let icon: String
    var action: ShortcutService.Action? = nil
    let perform: () -> Void

    @State private var isHovered = false

    private var shortcut: ShortcutService.Shortcut? {
        action.flatMap { ShortcutService.shared.effectiveShortcut(for: $0) }
    }

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize()

                Spacer(minLength: 2)

                if let shortcut {
                    Text(shortcut.displayString)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(TrayButtonBackground(isHovered: isHovered))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(TrayButtonStyle())
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(shortcut?.accessibilityDescription ?? "")
    }
}

private struct TrayButtonBackground: View {
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(isHovered ? 0.14 : 0.06))
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct TrayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Grid Menu (dropdown matching grid button style via NSMenu)

struct TrayGridMenu: NSViewRepresentable {
    let title: String
    let icon: String
    let menuItems: [TrayMenuItem]

    func makeNSView(context: Context) -> TrayGridMenuButton {
        let button = TrayGridMenuButton(title: title, icon: icon, menuItems: menuItems)
        return button
    }

    func updateNSView(_ nsView: TrayGridMenuButton, context: Context) {
        nsView.menuItems = menuItems
    }
}

struct TrayMenuItem {
    let title: String
    let icon: String
    let action: () -> Void
    var isDestructive: Bool = false
    var isSeparator: Bool = false
    var isDisabled: Bool = false
    var submenu: [TrayMenuItem]? = nil

    static func separator() -> TrayMenuItem {
        TrayMenuItem(title: "", icon: "", action: {}, isSeparator: true)
    }
}

final class TrayGridMenuButton: NSView {
    var menuItems: [TrayMenuItem]
    private let titleText: String
    private let iconName: String
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(title: String, icon: String, menuItems: [TrayMenuItem]) {
        self.titleText = title
        self.iconName = icon
        self.menuItems = menuItems
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for item in menuItems {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            if let submenuItems = item.submenu {
                let parentItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                if let img = NSImage(systemSymbolName: item.icon, accessibilityDescription: nil) {
                    parentItem.image = img
                }
                let sub = NSMenu()
                for subItem in submenuItems {
                    if subItem.isSeparator {
                        sub.addItem(.separator())
                        continue
                    }
                    let mi = NSMenuItem(title: subItem.title, action: #selector(menuAction(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = subItem.action
                    if let img = NSImage(systemSymbolName: subItem.icon, accessibilityDescription: nil) {
                        mi.image = img
                    }
                    if subItem.isDestructive {
                        mi.attributedTitle = NSAttributedString(string: subItem.title, attributes: [.foregroundColor: NSColor.systemRed])
                    }
                    mi.isEnabled = !subItem.isDisabled
                    sub.addItem(mi)
                }
                parentItem.submenu = sub
                menu.addItem(parentItem)
            } else {
                let mi = NSMenuItem(title: item.title, action: #selector(menuAction(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.action
                if let img = NSImage(systemSymbolName: item.icon, accessibilityDescription: nil) {
                    mi.image = img
                }
                if item.isDestructive {
                    mi.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.systemRed])
                }
                mi.isEnabled = !item.isDisabled
                menu.addItem(mi)
            }
        }
        let point = NSPoint(x: 0, y: bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? () -> Void {
            action()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor = isHovered
            ? NSColor.labelColor.withAlphaComponent(0.14)
            : NSColor.labelColor.withAlphaComponent(0.06)

        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        bgColor.setFill()
        path.fill()

        let iconColor = NSColor.secondaryLabelColor
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

        let iconX: CGFloat = 9
        let textX: CGFloat = 31
        let chevronWidth: CGFloat = 20
        let centerY = bounds.midY

        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) {
            let tinted = tintImage(img, color: iconColor)
            let imgSize = tinted.size
            let imgRect = NSRect(x: iconX, y: centerY - imgSize.height / 2, width: imgSize.width, height: imgSize.height)
            tinted.draw(in: imgRect)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = (titleText as NSString).size(withAttributes: attrs)
        let textPoint = NSPoint(x: textX, y: centerY - textSize.height / 2)
        (titleText as NSString).draw(at: textPoint, withAttributes: attrs)

        let chevronColor = NSColor.tertiaryLabelColor
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronConfig) {
            let tinted = tintImage(chevron, color: chevronColor)
            let chevronSize = tinted.size
            let chevronRect = NSRect(
                x: bounds.maxX - chevronWidth,
                y: centerY - chevronSize.height / 2,
                width: chevronSize.width,
                height: chevronSize.height
            )
            tinted.draw(in: chevronRect)
        }
    }

    private func tintImage(_ image: NSImage, color: NSColor) -> NSImage {
        let tinted = image.copy() as! NSImage
        tinted.isTemplate = false
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: tinted.size)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
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
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .medium))

                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(TrayButtonBackground(isHovered: isHovered))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(TrayButtonStyle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Divider

private struct TrayDivider: View {
    var body: some View {
        Divider()
            .opacity(0.6)
    }
}
