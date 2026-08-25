import SwiftUI
import Carbon

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, capture, recording, shortcuts, sharing, screenshots, recordings, about

    var id: String { rawValue }

    static let preferenceGroup: [SettingsSection] = [.general, .capture, .recording, .shortcuts, .sharing]
    static let libraryGroup: [SettingsSection] = [.screenshots, .recordings]

    var title: String {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .recording: "Recording"
        case .shortcuts: "Shortcuts"
        case .sharing: "Sharing"
        case .screenshots: "Screenshots"
        case .recordings: "Recordings"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .recording: "record.circle"
        case .shortcuts: "command"
        case .sharing: "link"
        case .screenshots: "photo.on.rectangle.angled"
        case .recordings: "film"
        case .about: "info.circle"
        }
    }
}

struct PreferencesView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Preferences") {
                    ForEach(SettingsSection.preferenceGroup, content: row)
                }
                Section("Library") {
                    ForEach(SettingsSection.libraryGroup, content: row)
                }
                Section {
                    row(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 184, ideal: 196, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 620)
    }

    private func row(_ section: SettingsSection) -> some View {
        Label(section.title, systemImage: section.icon)
            .tag(section)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralSettingsTab()
        case .capture: CaptureSettingsTab()
        case .recording: RecordingSettingsTab()
        case .shortcuts: ShortcutSettingsTab()
        case .sharing: SharingSettingsTab()
        case .screenshots: CaptureLibraryTab(kind: .screenshot)
        case .recordings: CaptureLibraryTab(kind: .recording)
        case .about: AboutTab()
        }
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("bs_appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("bs_saveDirectory") private var saveDir = NSHomeDirectory() + "/Desktop"
    @AppStorage("bs_copyAfterSave") private var copyAfterSave = true
    @AppStorage("bs_playSound") private var playSound = true
    @AppStorage("bs_exportFormat") private var exportFormatRaw: String = ExportFormat.png.rawValue
    @AppStorage("bs_exportQuality") private var exportQuality: Double = 0.9
    @AppStorage("bs_historyRetentionLimit") private var historyRetentionLimit = 100

    @State private var defaultConfig = AppPreferences.defaultBeautifierConfig
    @State private var isConfirmingReset = false

    private var appAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appAppearanceRaw) ?? .system },
            set: { newValue in
                appAppearanceRaw = newValue.rawValue
                AppPreferences.applyAppearance()
            }
        )
    }

    private var exportFormat: Binding<ExportFormat> {
        Binding(
            get: { ExportFormat(rawValue: exportFormatRaw) ?? .png },
            set: { exportFormatRaw = $0.rawValue }
        )
    }

    private var saveDirDisplayPath: String {
        URL(fileURLWithPath: saveDir).abbreviatedHomePath
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows whatever macOS is set to.")
            }

            Section {
                LabeledContent("Save screenshots to") {
                    HStack(spacing: 8) {
                        Text(saveDirDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(saveDir)
                        Button("Choose\u{2026}", action: chooseSaveDirectory)
                            .controlSize(.small)
                    }
                }

                Toggle("Copy to the clipboard after saving", isOn: $copyAfterSave)
                Toggle("Play a shutter sound when capturing", isOn: $playSound)
            } header: {
                Text("Saving")
            }

            Section {
                Picker("Save as", selection: exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if exportFormatRaw == ExportFormat.jpeg.rawValue {
                    LabeledContent("Quality") {
                        HStack(spacing: 12) {
                            Slider(value: $exportQuality, in: 0.1...1.0, step: 0.05)
                            Text("\(Int(exportQuality * 100))%")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("File Format")
            } footer: {
                Text(exportFormatRaw == ExportFormat.jpeg.rawValue
                     ? "JPEG files are much smaller, and a little detail is lost every time one is saved."
                     : "PNG keeps every pixel exactly as captured, which is the safer default for screenshots of text.")
            }

            Section {
                DefaultConfigPreview(config: defaultConfig)
                    .frame(height: 140)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))

                DefaultBackgroundPicker(selectedStyle: $defaultConfig.style)

                defaultSlider(label: "Padding", value: $defaultConfig.padding, range: 0.0...0.45) {
                    "\(Int($0 * 100))%"
                }
                defaultSlider(label: "Corner Radius", value: $defaultConfig.cornerRadius, range: 0.0...0.12) {
                    "\(Int($0 * 1000))"
                }
                defaultSlider(label: "Shadow", value: $defaultConfig.shadowStrength, range: 0.0...1.0) {
                    "\(Int($0 * 100))%"
                }

                Button("Reset Default Look") {
                    defaultConfig = .default
                    AppPreferences.defaultBeautifierConfig = .default
                }
                .controlSize(.small)
            } header: {
                HStack {
                    Text("Default Look")
                    Spacer()
                    Text(backgroundLabel(for: defaultConfig.style))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
            } footer: {
                Text("How every new screenshot is framed. You can still change any of it per screenshot in the editor.")
            }
            .onChange(of: defaultConfig) { _, newValue in
                AppPreferences.defaultBeautifierConfig = newValue
            }

            Section {
                Picker("Keep the last", selection: $historyRetentionLimit) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.label).tag(retention.rawValue)
                    }
                }
                .onChange(of: historyRetentionLimit) { _, _ in
                    HistoryStore.shared.trimToRetentionLimit()
                }
            } header: {
                Text("History")
            } footer: {
                Text("Older entries leave the Library along with the copies BetterShot keeps in Application Support. The files in your save folder are never touched.")
            }

            Section {
                Button("Restore Defaults\u{2026}", role: .destructive) {
                    isConfirmingReset = true
                }
            } footer: {
                Text("Puts everything on this page, including the default look, back the way BetterShot shipped.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore General settings to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive, action: restoreDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your screenshots and recordings are left alone.")
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.message = "Choose where BetterShot saves new screenshots and recordings."
        panel.directoryURL = URL(fileURLWithPath: saveDir)
        if panel.runModal() == .OK, let url = panel.url {
            saveDir = url.path
        }
    }

    private func restoreDefaults() {
        appAppearanceRaw = AppAppearance.system.rawValue
        AppPreferences.applyAppearance()
        saveDir = NSHomeDirectory() + "/Desktop"
        copyAfterSave = true
        playSound = true
        exportFormatRaw = ExportFormat.png.rawValue
        exportQuality = 0.9
        historyRetentionLimit = 100
        defaultConfig = .default
        AppPreferences.defaultBeautifierConfig = .default
    }

    private func defaultSlider(label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, format: @escaping (CGFloat) -> String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 12) {
                Slider(value: value, in: range)
                Text(format(value.wrappedValue))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func backgroundLabel(for style: BackgroundStyle) -> String {
        switch style {
        case .none: "Transparent"
        case .solid(let c): c.name
        case .gradient(let g): g.name
        case .wallpaper: "Custom Image"
        case .bundledImage: "macOS Wallpaper"
        }
    }
}

extension URL {
    /// `~/Desktop/Shots` rather than the full `/Users/name/...`, which is what the Finder shows people.
    var abbreviatedHomePath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
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
                if let img = ImageCache.shared.image(atPath: source.path) {
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
            if let nsImage = ImageCache.shared.image(atPath: source.path) {
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
    @AppStorage("bs_openEditorAfterCapture") private var openEditorAfterCapture = false
    @State private var isConfirmingReset = false

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
            Section {
                Picker("Count down before capturing", selection: selfTimerDelay) {
                    ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                        Text(delay.label).tag(delay)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Timer")
            } footer: {
                Text("Buys you a moment to open a menu or hover something before the shot is taken.")
            }

            Section {
                Picker("Show it in the", selection: overlayPosition) {
                    Text("Bottom Right").tag(OverlayPosition.bottomRight)
                    Text("Bottom Left").tag(OverlayPosition.bottomLeft)
                }

                LabeledContent("Hide it after") {
                    HStack(spacing: 12) {
                        Slider(value: $overlayDismissDelay, in: AppPreferences.overlayDismissRange, step: 1)
                        Text(AppPreferences.overlayDismisses(after: overlayDismissDelay) ? "\(Int(overlayDismissDelay))s" : "Never")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Preview Thumbnail")
            } footer: {
                Text("Every capture drops a thumbnail on screen. Click it to edit, drag it straight into another app, or leave it and it fades away on its own.")
            }

            Section {
                Toggle("Open the editor straight away", isOn: $openEditorAfterCapture)
            } header: {
                Text("After Capture")
            } footer: {
                Text("Off by default: the screenshot is saved and copied immediately, and the thumbnail is there if you want to edit it.")
            }

            Section {
                Button("Restore Defaults\u{2026}", role: .destructive) {
                    isConfirmingReset = true
                }
            } footer: {
                Text("Keyboard shortcuts live on their own page and are not affected.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore Capture settings to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                selfTimerRaw = 0
                overlayPositionRaw = OverlayPosition.bottomRight.rawValue
                overlayDismissDelay = 5.0
                openEditorAfterCapture = false
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Recording Settings

struct RecordingSettingsTab: View {
    @AppStorage("bs_recordingFPS") private var recordingFPS: Int = 30
    @AppStorage("bs_recordingShowCursor") private var showCursor: Bool = true
    @AppStorage(AppPreferences.recordingCaptureAudioKey) private var captureAudio: Bool = false
    @AppStorage(AppPreferences.recordingCaptureKeystrokesKey) private var captureKeystrokes: Bool = false
    @AppStorage("bs_recordingOpenEditor") private var openEditor: Bool = true
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                Picker("Frame rate", selection: $recordingFPS) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Quality")
            } footer: {
                Text("30 fps suits demos and walkthroughs. Go to 60 for fast motion, and expect roughly twice the file size.")
            }

            Section {
                Toggle("The mouse cursor", isOn: $showCursor)
                Toggle("System audio", isOn: $captureAudio)
                Toggle("The keys I type", isOn: $captureKeystrokes)
                    .onChange(of: captureKeystrokes) { _, isOn in
                        if isOn && !KeystrokeRecorder.isPermitted { KeystrokeRecorder.requestPermission() }
                    }
            } header: {
                Text("Include")
            } footer: {
                Text("Microphone input is picked separately from the recording bar, so you can decide right before you hit record. Leaving the mouse cursor out lets the editor draw a smoothed one in its place. Recording keys needs Input Monitoring, saves what you type beside the recording, and stays off until you turn it on.")
            }

            Section {
                Toggle("Open the trim editor when I stop", isOn: $openEditor)
            } header: {
                Text("After Recording")
            } footer: {
                Text("Turn this off to have recordings saved straight to your save folder.")
            }

            Section {
                Button("Restore Defaults\u{2026}", role: .destructive) {
                    isConfirmingReset = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore Recording settings to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                recordingFPS = 30
                showCursor = true
                captureAudio = false
                captureKeystrokes = false
                openEditor = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Shortcut Settings

struct ShortcutSettingsTab: View {
    @State private var resetID = UUID()
    @State private var isConfirmingReset = false

    private static let rows: [(label: String, help: String, action: ShortcutService.Action)] = [
        ("Capture Region", "Drag out the area you want", .region),
        ("Capture Screen", "Grab the whole display at once", .fullscreen),
        ("OCR", "Read the text out of any region", .ocr),
        ("Pick Color", "Sample a color from anywhere on screen", .colorPicker),
        ("Record Screen", "Open the recording bar", .recording),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.rows, id: \.action) { row in
                    ShortcutRow(label: row.label, help: row.help, action: row.action)
                }
                .id(resetID)
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("These work anywhere in macOS, whichever app is in front. Click a shortcut to record a new one, or switch one off to give the keys back to another app.")
            }

            Section {
                Button("Restore Defaults\u{2026}", role: .destructive) {
                    isConfirmingReset = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Restore all shortcuts to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                ShortcutService.shared.restoreDefaults()
                resetID = UUID()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct ShortcutRow: View {
    let label: String
    let help: String
    let action: ShortcutService.Action

    @State private var shortcut: ShortcutService.Shortcut?
    @State private var isRecording = false

    private var isEnabled: Bool { shortcut?.enabled ?? false }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                if isRecording {
                    ShortcutRecorderView { keyCode, modifiers in
                        persist(ShortcutService.Shortcut(keyCode: keyCode, modifiers: modifiers, enabled: true))
                        isRecording = false
                    } onCancel: {
                        isRecording = false
                    }
                    .frame(width: 132, height: 24)
                } else {
                    Button {
                        isRecording = true
                    } label: {
                        Text(shortcut?.displayString ?? "\u{2014}")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(isEnabled ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .frame(width: 132)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Click to record a new shortcut")
                    .accessibilityLabel("\(label) shortcut")
                    .accessibilityValue(shortcut?.accessibilityDescription ?? "None")
                    .accessibilityHint("Records a new shortcut")
                }

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { enabled in
                        guard var updated = shortcut else { return }
                        updated.enabled = enabled
                        persist(updated)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Enable the \(label) shortcut")
            }
        } label: {
            Text(label)
            Text(help)
        }
        .onAppear {
            shortcut = ShortcutService.shared.loadShortcut(for: action) ?? action.defaultShortcut
        }
    }

    private func persist(_ updated: ShortcutService.Shortcut) {
        shortcut = updated
        ShortcutService.shared.saveShortcut(updated, for: action)
        ShortcutService.shared.registerAll()
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

// MARK: - Library

struct CaptureLibraryTab: View {
    let kind: CaptureKind

    @State private var thumbnails: [String: NSImage] = [:]
    @State private var isConfirmingClear = false

    private var records: [CaptureRecord] {
        HistoryStore.shared.records.filter { $0.kind == kind }
    }

    var body: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Remove \(records.count) \(records.count == 1 ? noun : plural) from the Library?",
            isPresented: $isConfirmingClear
        ) {
            Button("Remove", role: .destructive) {
                thumbnails.removeAll()
                records.forEach { HistoryStore.shared.deleteRecord($0) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the copies BetterShot keeps. The files already in your save folder stay where they are.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(kind == .screenshot ? "No Screenshots Yet" : "No Recordings Yet", systemImage: icon)
        } description: {
            Text(kind == .screenshot
                 ? "Everything you capture shows up here, ready to reopen, edit or drag somewhere else."
                 : "Everything you record shows up here, ready to reopen and trim.")
        } actions: {
            Button(kind == .screenshot ? "Capture a Region" : "Start Recording", action: startCapture)
                .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List {
                ForEach(records) { record in
                    row(record)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text("\(records.count) \(records.count == 1 ? noun : plural)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Clear \(plural.capitalized)\u{2026}", role: .destructive) {
                    isConfirmingClear = true
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func row(_ record: CaptureRecord) -> some View {
        HStack(spacing: 14) {
            thumbnail(record)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(record.pixelWidth) \u{00D7} \(record.pixelHeight)  \u{00B7}  \(record.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: { open(record) }) {
                Image(systemName: kind == .screenshot ? "eye" : "slider.horizontal.below.rectangle")
            }
            .buttonStyle(.borderless)
            .help(kind == .screenshot ? "Preview this screenshot" : "Open in the trim editor")
            .accessibilityLabel(kind == .screenshot ? "Preview \(record.filename)" : "Edit \(record.filename)")

            Button(role: .destructive) {
                thumbnails.removeValue(forKey: record.id.uuidString)
                HistoryStore.shared.deleteRecord(record)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove from the Library")
            .accessibilityLabel("Remove \(record.filename)")
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func thumbnail(_ record: CaptureRecord) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let thumb = thumbnails[record.id.uuidString] {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .onAppear { loadThumbnail(for: record) }
            }
        }
        .frame(width: 72, height: 48)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var noun: String { kind == .screenshot ? "screenshot" : "recording" }
    private var plural: String { noun + "s" }
    private var icon: String { kind == .screenshot ? "photo.on.rectangle.angled" : "film" }

    private func open(_ record: CaptureRecord) {
        if kind == .screenshot {
            PreviewOverlay.shared.show(url: HistoryStore.shared.displayURLForRecord(record))
        } else {
            VideoEditorWindowController.shared.open(url: HistoryStore.shared.urlForRecord(record))
        }
    }

    private func startCapture() {
        let screen = NSApp.keyWindow?.screen
        SettingsWindowController.shared.close()
        if kind == .screenshot {
            Task { await CaptureOrchestrator.shared.performCapture(.region, on: screen) }
        } else {
            RecordingBarPresenter.shared.showPicker(on: screen)
        }
    }

    private func loadThumbnail(for record: CaptureRecord) {
        let source = HistoryStore.shared.thumbnailSource(for: record)
        Task.detached {
            let thumb = HistoryStore.decodeThumbnail(source, maxSize: 96)
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var appIcon: NSImage? {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("Updates") {
                    updateContent
                }

                section("Project") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BetterShot is open source. Issues, ideas and pull requests are all welcome.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Link("View on GitHub", destination: URL(string: "https://github.com/KartikLabhshetwar/better-shot")!)
                    }
                }

                section("Credits") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Built by Kartik Labhshetwar.")
                            .foregroundStyle(.secondary)

                        Link(destination: URL(string: "https://x.com/code_kartik")!) {
                            HStack(spacing: 3) {
                                Text("Follow on X")
                                Image(systemName: "arrow.up.forward")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("BetterShot")
                    .font(.title.weight(.semibold))

                Text("Version \(version) (\(build))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Capture, annotate and beautify screenshots on macOS.")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        switch updater.state {
        case .idle:
            Button("Check for Updates\u{2026}") {
                Task { await updater.checkForUpdates() }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking\u{2026}")
                    .foregroundStyle(.secondary)
            }

        case .available(let newVersion, let url):
            VStack(alignment: .leading, spacing: 8) {
                Label("Version \(newVersion) is available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.green)

                Button("Download and Install") {
                    Task { await updater.downloadAndInstall(version: newVersion, url: url) }
                }
                .buttonStyle(.borderedProminent)
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress) {
                    Text("Downloading\u{2026} \(Int(progress * 100))%")
                        .font(.caption)
                }
                .frame(maxWidth: 260)

                Button("Cancel") { updater.cancelDownload() }
                    .controlSize(.small)
            }

        case .readyToInstall(let newVersion, let dmgPath):
            VStack(alignment: .leading, spacing: 8) {
                Label("Version \(newVersion) is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Button("Install and Relaunch") {
                    Task { await updater.installUpdate(dmgPath: dmgPath) }
                }
                .buttonStyle(.borderedProminent)
            }

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing\u{2026}")
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Label("BetterShot is up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try Again") {
                    Task { await updater.checkForUpdates() }
                }
            }
        }
    }
}
