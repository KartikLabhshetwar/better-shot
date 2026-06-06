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
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 170)

            Divider()

            ZStack {
                GeneralSettingsTab()
                    .opacity(selectedSection == .general ? 1 : 0)
                    .allowsHitTesting(selectedSection == .general)
                CaptureSettingsTab()
                    .opacity(selectedSection == .capture ? 1 : 0)
                    .allowsHitTesting(selectedSection == .capture)
                HistoryTab()
                    .opacity(selectedSection == .history ? 1 : 0)
                    .allowsHitTesting(selectedSection == .history)
                AboutTab()
                    .opacity(selectedSection == .about ? 1 : 0)
                    .allowsHitTesting(selectedSection == .about)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("bs_saveDirectory") private var saveDir = NSHomeDirectory() + "/Desktop"
    @AppStorage("bs_copyAfterSave") private var copyAfterSave = true
    @AppStorage("bs_playSound") private var playSound = true
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
            }

            Section("Default Effects") {
                DefaultConfigPreview(config: defaultConfig)
                    .frame(height: 120)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

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

                Button("Reset Effects to Defaults") {
                    defaultConfig = .default
                    AppPreferences.defaultBeautifierConfig = .default
                }
                .controlSize(.small)
                .foregroundStyle(.secondary)
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

            Section {
                Button("Reset All General Settings to Defaults") {
                    saveDir = NSHomeDirectory() + "/Desktop"
                    copyAfterSave = true
                    playSound = true
                    exportFormatRaw = ExportFormat.png.rawValue
                    exportQuality = 0.9
                    defaultConfig = .default
                    AppPreferences.defaultBeautifierConfig = .default
                }
                .controlSize(.small)
                .foregroundStyle(.red)
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
        case .bundledImage: return "macOS Wallpaper"
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

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 5), count: 6), spacing: 5) {
                ForEach(BundledBackgrounds.macAssets) { asset in
                    bundledImageButton(asset)
                }
            }

            customImageRow
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

    private func bundledImageButton(_ asset: BundledBackgrounds.ImageAsset) -> some View {
        let isSelected: Bool = {
            if case .bundledImage(let id) = selectedStyle { return id == asset.id }
            return false
        }()

        return Button {
            selectedStyle = .bundledImage(asset.id)
        } label: {
            Group {
                if let image = asset.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 38, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var customImageRow: some View {
        if case .wallpaper(let source) = selectedStyle {
            HStack(spacing: 8) {
                if let img = NSImage(contentsOfFile: source.path) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        )
                }
                Text(URL(fileURLWithPath: source.path).lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change") { pickCustomImage() }
                    .controlSize(.mini)
            }
        } else {
            Button { pickCustomImage() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.caption2)
                    Text("Custom Image...").font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func pickCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Background Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedStyle = .wallpaper(WallpaperSource(path: url.path))
    }
}

// MARK: - Default Config Preview

private struct DefaultConfigPreview: View {
    let config: BeautifierConfig

    var body: some View {
        GeometryReader { proxy in
            let mockImageW: CGFloat = 160
            let mockImageH: CGFloat = 100
            let shortEdge = min(mockImageW, mockImageH)
            let pad = shortEdge * config.padding

            var canvasW = mockImageW + pad * 2
            var canvasH = mockImageH + pad * 2
            let _ = {
                if let ratio = config.aspectRatio.numericValue {
                    let current = canvasW / canvasH
                    if current < ratio { canvasW = canvasH * ratio }
                    else { canvasH = canvasW / ratio }
                }
            }()

            let canvasSize = CGSize(width: canvasW, height: canvasH)
            let fitted = aspectFitRect(imageSize: canvasSize, in: proxy.size)

            let totalHPad = canvasW - mockImageW
            let totalVPad = canvasH - mockImageH
            let imgX = fitted.minX + config.alignment.xFactor * totalHPad / canvasW * fitted.width
            let imgY = fitted.minY + config.alignment.yFactor * totalVPad / canvasH * fitted.height
            let imgW = mockImageW / canvasW * fitted.width
            let imgH = mockImageH / canvasH * fitted.height

            let cornerRadius = config.cornerRadius * shortEdge * min(fitted.width / canvasW, fitted.height / canvasH)
            let m = config.alignment.cornerMultipliers

            ZStack {
                previewBackground(config.style)
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .position(x: fitted.midX, y: fitted.midY)

                mockScreenshot
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius * m.tl,
                        bottomLeadingRadius: cornerRadius * m.bl,
                        bottomTrailingRadius: cornerRadius * m.br,
                        topTrailingRadius: cornerRadius * m.tr,
                        style: .continuous
                    ))
                    .shadow(
                        color: config.shadowStrength > 0 ? .black.opacity(Double(config.shadowStrength * 0.3)) : .clear,
                        radius: config.shadowStrength > 0 ? max(2, shortEdge * 0.02 * (1 + config.shadowStrength)) : 0,
                        x: 0,
                        y: config.shadowStrength > 0 ? shortEdge * 0.01 * (1 + config.shadowStrength) : 0
                    )
                    .frame(width: imgW, height: imgH)
                    .position(x: imgX + imgW / 2, y: imgY + imgH / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var mockScreenshot: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.96), Color(white: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Circle().fill(.red.opacity(0.7)).frame(width: 5, height: 5)
                    Circle().fill(.yellow.opacity(0.7)).frame(width: 5, height: 5)
                    Circle().fill(.green.opacity(0.7)).frame(width: 5, height: 5)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.82))
                    .frame(height: 6)
                    .padding(.horizontal, 8)

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.78))
                        .frame(width: 30, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.84))
                        .frame(height: 4)
                }
                .padding(.horizontal, 8)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func previewBackground(_ style: BackgroundStyle) -> some View {
        switch style {
        case .none:
            TransparencyGrid()
        case .solid(let color):
            Rectangle().fill(color.color)
        case .gradient(let preset):
            Rectangle().fill(preset.swiftUIGradient)
        case .wallpaper(let source):
            if let nsImage = NSImage(contentsOfFile: source.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        case .bundledImage(let assetID):
            if let asset = BundledBackgrounds.asset(byID: assetID),
               let nsImage = asset.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Capture Settings

struct CaptureSettingsTab: View {
    @AppStorage("bs_selfTimerDelay") private var selfTimerRaw: Int = 0
    @AppStorage("bs_overlayPosition") private var overlayPositionRaw: String = OverlayPosition.bottomRight.rawValue
    @AppStorage("bs_overlayDismissDelay") private var overlayDismissDelay: Double = 5.0
    @State private var shortcutResetID = UUID()

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

            Section("Preview Overlay") {
                Picker("Position", selection: overlayPosition) {
                    Text("Bottom Right").tag(OverlayPosition.bottomRight)
                    Text("Bottom Left").tag(OverlayPosition.bottomLeft)
                }

                HStack {
                    Text("Dismiss after")
                    Spacer()
                    Text("\(Int(overlayDismissDelay))s")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $overlayDismissDelay, in: 2...15, step: 1)
                    .controlSize(.small)
            }

            Section("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRow(label: "Region", action: .region)
                    ShortcutRow(label: "Fullscreen", action: .fullscreen)
                    ShortcutRow(label: "OCR Region", action: .ocr)
                    ShortcutRow(label: "Color Picker", action: .colorPicker)
                }
                .id(shortcutResetID)

                Button("Reset Shortcuts to Defaults") {
                    for action in ShortcutService.Action.allCases {
                        let def: ShortcutService.Shortcut? = switch action {
                        case .region: .defaultRegion
                        case .fullscreen: .defaultFullscreen
                        case .ocr: .defaultOCR
                        case .colorPicker: .defaultColorPicker
                        case .window: nil
                        }
                        if let def {
                            ShortcutService.shared.saveShortcut(def, for: action)
                        }
                    }
                    ShortcutService.shared.registerAll()
                    shortcutResetID = UUID()
                }
                .controlSize(.small)
            }

            Section {
                Button("Reset All Capture Settings to Defaults") {
                    selfTimerRaw = 0
                    overlayPositionRaw = OverlayPosition.bottomRight.rawValue
                    overlayDismissDelay = 5.0
                    for action in ShortcutService.Action.allCases {
                        let def: ShortcutService.Shortcut? = switch action {
                        case .region: .defaultRegion
                        case .fullscreen: .defaultFullscreen
                        case .ocr: .defaultOCR
                        case .colorPicker: .defaultColorPicker
                        case .window: nil
                        }
                        if let def {
                            ShortcutService.shared.saveShortcut(def, for: action)
                        }
                    }
                    ShortcutService.shared.registerAll()
                    shortcutResetID = UUID()
                }
                .controlSize(.small)
                .foregroundStyle(.red)
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
        case .window: return ShortcutService.Shortcut(keyCode: 0, modifiers: 0, enabled: false)
        case .ocr: return .defaultOCR
        case .colorPicker: return .defaultColorPicker
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
        ShortcutService.shared.unregisterAll()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}

    static func dismantleNSView(_ nsView: ShortcutRecorderNSView, coordinator: ()) {
        nsView.removeMonitor()
        ShortcutService.shared.registerAll()
    }
}

final class ShortcutRecorderNSView: NSView {
    var onRecord: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?
    private var eventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitor()
        }
    }

    private func installMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let keyCode = UInt32(event.keyCode)

            if keyCode == 53 {
                self.onCancel?()
                return nil
            }

            let flags = event.modifierFlags
            var carbonMods: UInt32 = 0
            if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

            guard carbonMods != 0 else { return event }

            self.onRecord?(keyCode, carbonMods)
            return nil
        }
    }

    func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

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

    override func keyDown(with event: NSEvent) {}
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
    @State private var thumbnails: [String: NSImage] = [:]

    var body: some View {
        if HistoryStore.shared.records.isEmpty {
            ContentUnavailableView("No captures yet", systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(HistoryStore.shared.records) { record in
                    HStack(spacing: 12) {
                        if let thumb = thumbnails[record.id.uuidString] {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(width: 64, height: 48)
                                .onAppear {
                                    loadThumbnail(for: record)
                                }
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
                            thumbnails.removeValue(forKey: record.id.uuidString)
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

    private func loadThumbnail(for record: CaptureRecord) {
        Task.detached {
            let thumb = await HistoryStore.shared.thumbnail(for: record, maxSize: 80)
            await MainActor.run {
                if let thumb {
                    thumbnails[record.id.uuidString] = thumb
                }
            }
        }
    }
}

// MARK: - About

struct AboutTab: View {
    private let updater = AppUpdater.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.4"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var appIcon: NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header: icon + name
                HStack(spacing: 14) {
                    if let icon = appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("BetterShot")
                            .font(.system(size: 20, weight: .bold))

                        Text("Version \(version)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("A native screenshot and editor tool for macOS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 20)

                // Updates section
                aboutSection("Updates") {
                    updateContent
                }

                // Project section
                aboutSection("Project") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BetterShot is an open-source screenshot tool for capturing, editing and beautifying screenshots on macOS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)

                        Link("GitHub", destination: URL(string: "https://github.com/KartikLabhshetwar/better-shot")!)
                            .font(.system(size: 12))
                    }
                }

                // Credits section
                aboutSection("Credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Built by Kartik Labhshetwar")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Link(destination: URL(string: "https://x.com/code_kartik")!) {
                            HStack(spacing: 2) {
                                Text("Follow on X")
                                    .font(.system(size: 12))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func aboutSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.bottom, 10)

            content()
                .padding(.leading, 2)
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        switch updater.state {
        case .idle:
            Button("Check for Updates...") {
                Task { await updater.checkForUpdates() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

        case .available(let newVersion, let url):
            VStack(alignment: .leading, spacing: 6) {
                Text("Version \(newVersion) is available!")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)

                Button("Download & Install") {
                    Task { await updater.downloadAndInstall(version: newVersion, url: url) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)

                Text("Downloading… \(Int(progress * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("Cancel") {
                    updater.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

        case .readyToInstall(let newVersion, let dmgPath):
            VStack(alignment: .leading, spacing: 6) {
                Text("Version \(newVersion) downloaded")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)

                Button("Install & Relaunch") {
                    Task { await updater.installUpdate(dmgPath: dmgPath) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing update…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Update failed: \(message)")
                    .font(.system(size: 12))
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
