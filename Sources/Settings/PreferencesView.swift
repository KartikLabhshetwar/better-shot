import SwiftUI
import Carbon

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case capture = "Capture"
    case history = "History"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .capture: return "camera.viewfinder"
        case .history: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesView: View {
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsTab()
                case .capture:
                    CaptureSettingsTab()
                case .history:
                    HistoryTab()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 620, height: 440)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("bs_saveDirectory") private var saveDir = NSHomeDirectory() + "/Desktop"
    @AppStorage("bs_copyAfterSave") private var copyAfterSave = true
    @AppStorage("bs_playSound") private var playSound = true
    @AppStorage("bs_showOverlay") private var showOverlay = true
    @AppStorage("bs_autoApplyBackground") private var autoApply = false
    @AppStorage("bs_exportFormat") private var exportFormatRaw: String = ExportFormat.png.rawValue
    @AppStorage("bs_exportQuality") private var exportQuality: Double = 0.9

    @State private var defaultConfig = AppPreferences.defaultBeautifierConfig

    private var exportFormat: Binding<ExportFormat> {
        Binding(
            get: { ExportFormat(rawValue: exportFormatRaw) ?? .png },
            set: { exportFormatRaw = $0.rawValue }
        )
    }

    private var saveDirDisplayName: String {
        let url = URL(fileURLWithPath: saveDir)
        return url.lastPathComponent
    }

    var body: some View {
        Form {
            Section("Save") {
                HStack {
                    Text("Save to")
                    Spacer()
                    Text(saveDirDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: saveDir)
                        if panel.runModal() == .OK, let url = panel.url {
                            saveDir = url.path
                        }
                    }
                    .controlSize(.small)
                }

                Toggle("Copy to clipboard after saving", isOn: $copyAfterSave)
            }

            Section("Capture") {
                Toggle("Play shutter sound", isOn: $playSound)
                Toggle("Show floating preview after capture", isOn: $showOverlay)
                Toggle("Auto-apply default background", isOn: $autoApply)
            }

            Section("Default Effects") {
                defaultSlider(label: "Padding", value: $defaultConfig.padding, range: 0.0...0.45) {
                    "\(Int($0 * 100))%"
                }
                defaultSlider(label: "Corner Radius", value: $defaultConfig.cornerRadius, range: 0.0...0.12) {
                    "\(Int($0 * 1000))"
                }
                defaultSlider(label: "Shadow", value: $defaultConfig.shadowStrength, range: 0.0...1.0) {
                    "\(Int($0 * 100))%"
                }
            }
            .onChange(of: defaultConfig) { _, newValue in
                AppPreferences.defaultBeautifierConfig = newValue
            }

            Section {
                DefaultBackgroundPicker(selectedStyle: $defaultConfig.style)
            } header: {
                HStack {
                    Text("Default Background")
                    Spacer()
                    Text(backgroundLabel(for: defaultConfig.style))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
            }

            Section("Export") {
                Picker("Format", selection: exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if exportFormatRaw == ExportFormat.jpeg.rawValue {
                    Slider(value: $exportQuality, in: 0.1...1.0, step: 0.05) {
                        Text("Quality: \(Int(exportQuality * 100))%")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func defaultSlider(label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, format: @escaping (CGFloat) -> String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }

    private func backgroundLabel(for style: BackgroundStyle) -> String {
        switch style {
        case .none: return "Transparent"
        case .solid(let c): return c.name
        case .gradient(let g): return g.name
        case .wallpaper: return "Custom Image"
        case .bundledImage(let id):
            if let asset = BundledBackgrounds.asset(byID: id) {
                return asset.category.displayName
            }
            return "Bundled"
        }
    }
}

// MARK: - Default Background Picker (compact for settings)

private struct DefaultBackgroundPicker: View {
    @Binding var selectedStyle: BackgroundStyle

    private let swatchColumns = Array(repeating: GridItem(.fixed(24), spacing: 5), count: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: swatchColumns, spacing: 5) {
                noneButton
                ForEach(SolidColor.presets) { color in
                    solidButton(color)
                }
            }

            LazyVGrid(columns: swatchColumns, spacing: 5) {
                ForEach(GradientPreset.presets) { preset in
                    gradientButton(preset)
                }
            }
        }
    }

    private var noneButton: some View {
        Button {
            selectedStyle = .none
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                Path { path in
                    path.move(to: CGPoint(x: 22, y: 2))
                    path.addLine(to: CGPoint(x: 2, y: 22))
                }
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(selectedStyle == .none ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selectedStyle == .none ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("No background")
    }

    private func solidButton(_ color: SolidColor) -> some View {
        let isSelected: Bool = {
            if case .solid(let c) = selectedStyle { return c.id == color.id }
            return false
        }()

        return Button {
            selectedStyle = .solid(color)
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.color)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(color.name)
    }

    private func gradientButton(_ preset: GradientPreset) -> some View {
        let isSelected: Bool = {
            if case .gradient(let g) = selectedStyle { return g.id == preset.id }
            return false
        }()

        return Button {
            selectedStyle = .gradient(preset)
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(preset.swiftUIGradient)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(preset.name)
    }
}

// MARK: - Capture Settings

struct CaptureSettingsTab: View {
    @AppStorage("bs_selfTimerDelay") private var selfTimerRaw: Int = 0
    @AppStorage("bs_overlayPosition") private var overlayPositionRaw: String = OverlayPosition.bottomRight.rawValue
    @AppStorage("bs_overlayDismissDelay") private var overlayDismissDelay: Double = 5.0

    private var selfTimerDelay: Binding<SelfTimerDelay> {
        Binding(
            get: { SelfTimerDelay(rawValue: selfTimerRaw) ?? .off },
            set: { selfTimerRaw = $0.rawValue }
        )
    }

    private var overlayPosition: Binding<OverlayPosition> {
        Binding(
            get: { OverlayPosition(rawValue: overlayPositionRaw) ?? .bottomRight },
            set: { overlayPositionRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Self Timer") {
                Picker("Delay", selection: selfTimerDelay) {
                    ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                        Text(delay.label).tag(delay)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRow(label: "Region", action: .region)
                    ShortcutRow(label: "Fullscreen", action: .fullscreen)
                    ShortcutRow(label: "Window", action: .window)
                    ShortcutRow(label: "OCR Region", action: .ocr)
                    ShortcutRow(label: "Color Picker", action: .colorPicker)
                    ShortcutRow(label: "Repeat Region", action: .repeatRegion)
                }
            }

            Section("Overlay") {
                Picker("Position", selection: overlayPosition) {
                    Text("Bottom Right").tag(OverlayPosition.bottomRight)
                    Text("Bottom Left").tag(OverlayPosition.bottomLeft)
                }

                Stepper(
                    "Dismiss after \(Int(overlayDismissDelay))s",
                    value: $overlayDismissDelay,
                    in: 2...30,
                    step: 1
                )
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let label: String
    let action: ShortcutService.Action

    @State private var shortcut: ShortcutService.Shortcut?
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { shortcut?.enabled ?? false },
                set: { enabled in
                    shortcut?.enabled = enabled
                    if let s = shortcut {
                        ShortcutService.shared.saveShortcut(s, for: action)
                        ShortcutService.shared.registerAll()
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Spacer()

            if isRecording {
                ShortcutRecorderView { keyCode, modifiers in
                    shortcut = ShortcutService.Shortcut(
                        keyCode: keyCode,
                        modifiers: modifiers,
                        enabled: shortcut?.enabled ?? true
                    )
                    if let s = shortcut {
                        ShortcutService.shared.saveShortcut(s, for: action)
                        ShortcutService.shared.registerAll()
                    }
                    isRecording = false
                } onCancel: {
                    isRecording = false
                }
                .frame(width: 120, height: 24)
            } else {
                Button {
                    isRecording = true
                } label: {
                    Text(shortcutDisplayString)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minWidth: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            shortcut = ShortcutService.shared.loadShortcut(for: action) ?? defaultShortcut
        }
    }

    private var defaultShortcut: ShortcutService.Shortcut {
        switch action {
        case .region: return .defaultRegion
        case .fullscreen: return .defaultFullscreen
        case .window: return .defaultWindow
        case .ocr: return .defaultOCR
        case .colorPicker: return .defaultColorPicker
        case .repeatRegion: return .defaultRepeatRegion
        }
    }

    private var shortcutDisplayString: String {
        guard let s = shortcut else { return "—" }
        var parts: [String] = []
        if s.modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        if s.modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if s.modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if s.modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        parts.append(keyCodeToString(s.keyCode))
        return parts.joined()
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: NSViewRepresentable {
    let onRecord: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}
}

final class ShortcutRecorderNSView: NSView {
    var onRecord: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let text = "Press shortcut..." as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attrs)
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)

        if keyCode == 53 {
            onCancel?()
            return
        }

        let flags = event.modifierFlags
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

        guard carbonMods != 0 else { return }

        onRecord?(keyCode, carbonMods)
    }

    override func flagsChanged(with event: NSEvent) {}
}

private func keyCodeToString(_ code: UInt32) -> String {
    let map: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F",
        0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
        0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K",
        0x2C: "/", 0x2D: "N", 0x2E: "M",
    ]
    return map[code] ?? "?"
}

// MARK: - History

struct HistoryTab: View {
    var body: some View {
        if HistoryStore.shared.records.isEmpty {
            ContentUnavailableView("No captures yet", systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(HistoryStore.shared.records) { record in
                    HStack(spacing: 12) {
                        if let thumb = HistoryStore.shared.thumbnail(for: record, maxSize: 80) {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.filename)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text("\(record.pixelWidth) x \(record.pixelHeight)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(record.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button {
                            HistoryStore.shared.deleteRecord(record)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - About

struct AboutTab: View {
    private let updater = AppUpdater.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.3"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("BetterShot")
                .font(.title2.weight(.semibold))

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Open-source screenshot tool for macOS. Fast, native, local-first.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            updateSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updater.state {
        case .idle:
            Button("Check for Updates") {
                Task { await updater.checkForUpdates() }
            }
            .buttonStyle(.bordered)

        case .checking:
            ProgressView()
                .controlSize(.small)
            Text("Checking for updates...")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .available(let newVersion, let url):
            VStack(spacing: 8) {
                Text("Version \(newVersion) is available!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)

                Button("Download & Install") {
                    Task { await updater.downloadAndInstall(version: newVersion, url: url) }
                }
                .buttonStyle(.borderedProminent)
            }

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text("Downloading update… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Cancel") {
                    updater.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .readyToInstall(let newVersion, let dmgPath):
            VStack(spacing: 8) {
                Text("Version \(newVersion) downloaded")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)

                Text("The app will quit and relaunch after installing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Install & Relaunch") {
                    Task { await updater.installUpdate(dmgPath: dmgPath) }
                }
                .buttonStyle(.borderedProminent)
            }

        case .installing:
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Installing update…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(spacing: 6) {
                Text("Update failed: \(message)")
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Retry") {
                    Task { await updater.checkForUpdates() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
