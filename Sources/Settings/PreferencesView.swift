import SwiftUI
import AVFoundation
import Carbon
import UniformTypeIdentifiers
import ServiceManagement

enum SettingsSection: String, CaseIterable, Identifiable {
    case home, general, capture, overlay, recording, shortcuts, sharing, about

    var id: String { rawValue }

    static let sidebar: [(title: String?, sections: [SettingsSection])] = [
        (nil, [.home]),
        ("Settings", [.general, .capture, .overlay, .recording, .shortcuts, .sharing]),
        ("BetterShot", [.about]),
    ]

    var title: String {
        switch self {
        case .home: "Home"
        case .general: "General"
        case .capture: "Capture"
        case .overlay: "Overlay"
        case .recording: "Recording"
        case .shortcuts: "Shortcuts"
        case .sharing: "Sharing"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .overlay: "macwindow.on.rectangle"
        case .recording: "video"
        case .shortcuts: "keyboard"
        case .sharing: "icloud.and.arrow.up"
        case .about: "info.circle"
        }
    }
}

/// The page shown in the Settings window, shared so reopening can switch pages without rebuilding the view.
@MainActor
@Observable
final class SettingsNavigation {
    var page: SettingsSection

    init(page: SettingsSection = .home) {
        self.page = page
    }
}

struct PreferencesView: View {
    @State private var navigation: SettingsNavigation
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onSelectionChange: (SettingsSection) -> Void

    init(selection: SettingsSection = .home, onSelectionChange: @escaping (SettingsSection) -> Void = { _ in }) {
        self.init(navigation: SettingsNavigation(page: selection), onSelectionChange: onSelectionChange)
    }

    init(navigation: SettingsNavigation, onSelectionChange: @escaping (SettingsSection) -> Void = { _ in }) {
        _navigation = State(initialValue: navigation)
        self.onSelectionChange = onSelectionChange
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $navigation.page) {
                ForEach(SettingsSection.sidebar, id: \.sections) { group in
                    Section {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.icon).tag(section)
                        }
                    } header: {
                        if let title = group.title { Text(title) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Toggle Sidebar", systemImage: "sidebar.left") {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                    .help("Show or hide the sidebar")
                }
            }
        } detail: {
            ZStack {
                detail
                    .id(navigation.page)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity
                    ))
            }
            .animation(.easeOut(duration: 0.18), value: navigation.page)
            .toggleStyle(.switch)
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(navigation.page.title)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: navigation.page) { _, section in onSelectionChange(section) }
        .tint(EditorChrome.accent)
        .accentColor(EditorChrome.accent)
        .frame(minWidth: 780, minHeight: 620)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.page {
        case .home: SettingsHomeTab { navigation.page = $0 }
        case .general: GeneralSettingsTab()
        case .capture: CaptureSettingsTab()
        case .overlay: OverlaySettingsTab()
        case .recording: RecordingSettingsTab()
        case .shortcuts: ShortcutSettingsTab()
        case .sharing: SharingSettingsTab()
        case .about: AboutTab()
        }
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage(AppPreferences.showCaptureBarAtLaunchKey) private var showCaptureBarAtLaunch = true
    @AppStorage(AppPreferences.showInDockKey) private var showInDock = false
    @AppStorage(AppPreferences.showInMenuBarKey) private var showInMenuBar = true
    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String?

    @AppStorage("bs_appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("bs_saveDirectory") private var saveDir = NSHomeDirectory() + "/Desktop"
    @AppStorage("bs_copyAfterSave") private var copyAfterSave = true
    @AppStorage(AfterCaptureAction.save.storageKey(for: .screenshot)) private var automaticallySaveScreenshots = AfterCaptureAction.save.defaultValue(for: .screenshot)
    @AppStorage("bs_playSound") private var playSound = true
    @AppStorage("bs_exportFormat") private var exportFormatRaw: String = ExportFormat.png.rawValue
    @AppStorage("bs_exportQuality") private var exportQuality: Double = 0.9
    @AppStorage("bs_historyRetentionLimit") private var historyRetentionLimit = 100
    @AppStorage(ScreenshotFileNaming.templateKey) private var fileNameTemplate = ScreenshotFileNaming.defaultTemplate
    @AppStorage(ScreenshotFileNaming.counterKey) private var fileNameCounter = 1
    /// Held rather than computed in `body`: `{hex:8}` would otherwise reshuffle
    /// on every unrelated redraw and read as a glitch.
    @State private var fileNamePreview = ""

    @AppStorage(AppPreferences.editorOpensFullScreenKey) private var editorFullScreen = false
    @State private var defaultConfig = AppPreferences.defaultBeautifierConfig
    @State private var isConfirmingReset = false
    @State private var pendingRetentionLimit: Int?

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

    private var loginCaption: String {
        loginStatus == .requiresApproval
            ? "Allow BetterShot in System Settings \u{203A} General \u{203A} Login Items & Extensions."
            : "Have BetterShot ready when your Mac starts."
    }

    private var savingCaption: String {
        automaticallySaveScreenshots
            ? "Normal screenshots are saved here right away. Copying or dismissing the preview keeps the file."
            : "Choose Save or Export when you want a file."
    }

    private var formatCaption: String {
        switch ExportFormat(rawValue: exportFormatRaw) ?? .png {
        case .jpeg: "Much smaller files. A little detail is lost every time one is saved."
        case .png: "Keeps every pixel exactly as captured, the safer choice for text."
        }
    }

    var body: some View {
        SettingsPage {
            SettingsGroup("Startup") {
                VStack(alignment: .leading, spacing: 0) {
                    SettingRow("Launch at login", caption: loginCaption) {
                        HStack(spacing: 8) {
                            if loginStatus == .requiresApproval || loginError != nil {
                                Button("Open Login Items\u{2026}") { SMAppService.openSystemSettingsLoginItems() }
                            }
                            Toggle("Launch at login", isOn: Binding(
                                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                                set: setLaunchAtLogin
                            ))
                            .labelsHidden()
                            .controlSize(.small)
                        }
                    }
                    if let loginError {
                        Label(loginError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 11)
                    }
                }
                SettingsDivider()
                SettingToggle("Show the capture bar at launch", isOn: $showCaptureBarAtLaunch)
            }

            SettingsGroup("Appearance") {
                SettingRow("Theme") {
                    Picker("Theme", selection: appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingToggle("Show in Dock", caption: "Hide it to run BetterShot from the menu bar.", isOn: Binding(
                    get: { showInDock },
                    set: { enabled in
                        if !enabled { showInMenuBar = true }
                        showInDock = enabled
                        AppActivationPolicy.applyVisibility()
                    }
                ))
                SettingsDivider()
                SettingToggle("Show in menu bar", caption: showInDock ? nil : "Stays on while the Dock icon is hidden.", isOn: Binding(
                    get: { showInMenuBar || !showInDock },
                    set: { showInMenuBar = $0; AppActivationPolicy.applyVisibility() }
                ))
                .disabled(!showInDock)
                SettingsDivider()
                SettingToggle("Open editors in full screen", isOn: $editorFullScreen)
            }

            SettingsGroup("Saving") {
                SettingRow("Save folder", caption: saveDirDisplayPath) {
                    Button("Choose\u{2026}", action: chooseSaveDirectory)
                }
                .help(saveDir)
                SettingsDivider()
                SettingToggle("Save screenshots automatically", caption: savingCaption, isOn: $automaticallySaveScreenshots)
                SettingsDivider()
                fileNameRow
                if ScreenshotFileNaming.usesCounter(fileNameTemplate) {
                    SettingsDivider()
                    SettingRow("Next number", caption: "\(fileNameCounter)") {
                        Button("Reset") { fileNameCounter = 1 }
                            .disabled(fileNameCounter == 1)
                    }
                }
                SettingsDivider()
                SettingToggle("Copy to the clipboard", caption: "Every new screenshot is ready to paste.", isOn: $copyAfterSave)
                SettingsDivider()
                SettingToggle("Play a shutter sound", isOn: $playSound)
            } footer: {
                Text("Capture & Copy, Edit, and Pin shortcuts skip automatic saving.")
            }
            .onAppear(perform: refreshFileNamePreview)
            .onChange(of: fileNameTemplate) { _, _ in refreshFileNamePreview() }
            .onChange(of: exportFormatRaw) { _, _ in refreshFileNamePreview() }
            .onChange(of: fileNameCounter) { _, _ in refreshFileNamePreview() }

            SettingsGroup("File Format") {
                SettingRow("Save as", caption: formatCaption) {
                    Picker("Save as", selection: exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue.uppercased()).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if (ExportFormat(rawValue: exportFormatRaw) ?? .png).usesLossyQuality {
                    SettingsDivider()
                    InspectorSlider("Quality", value: Binding(
                        get: { CGFloat(exportQuality) },
                        set: { exportQuality = (Double($0) * 20).rounded() / 20 }
                    ), range: 0.1...1, format: .percent(step: 0.05))
                    .settingsRowPadding()
                }
            }

            SettingsGroup("Default Look") {
                DefaultConfigPreview(config: defaultConfig)
                    .frame(height: 140)
                    .padding(12)
                SettingsDivider()
                DefaultBackgroundPicker(selectedStyle: $defaultConfig.style)
                    .settingsRowPadding()
                SettingsDivider()
                VStack(spacing: 10) {
                    InspectorSlider("Padding", value: $defaultConfig.padding, range: 0...0.45, format: .percent())
                    InspectorSlider("Corner Radius", value: $defaultConfig.cornerRadius, range: 0...0.12, format: .percent(fractionDigits: 1))
                    InspectorSlider("Shadow", value: $defaultConfig.shadowStrength, range: 0...1, format: .percent())
                }
                .disabled(defaultConfig.style == .none)
                .settingsRowPadding()
            } accessory: {
                HStack(spacing: 10) {
                    Text(backgroundLabel(for: defaultConfig.style))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Reset") {
                        defaultConfig = .default
                        AppPreferences.defaultBeautifierConfig = .default
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .disabled(defaultConfig == .default)
                    .accessibilityLabel("Reset Default Look")
                }
            } footer: {
                if let preset = AnnotationBackgroundPresetStore.shared.activePreset {
                    Text("New screenshots use the \u{201C}\(preset.name)\u{201D} preset from the editor. Changing the look here replaces it.")
                } else {
                    Text("Background, padding, corner radius, and shadow for new screenshots and videos. Saved projects keep their own look.")
                }
            }
            .onChange(of: defaultConfig) { _, newValue in
                AppPreferences.defaultBeautifierConfig = newValue
                AnnotationBackgroundPresetStore.shared.setActivePreset(id: nil)
            }

            SettingsGroup("Recent Captures") {
                SettingRow("Keep the last", caption: "Older entries and their internal copies are removed. Saved files and recording projects stay.") {
                    Picker("Keep the last", selection: Binding(
                        get: { historyRetentionLimit },
                        set: { limit in
                            if limit > 0 && HistoryStore.shared.records.count > limit { pendingRetentionLimit = limit }
                            else { historyRetentionLimit = limit }
                        }
                    )) {
                        ForEach(HistoryRetention.allCases) { retention in
                            Text(retention.label).tag(retention.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingRow("Media Gallery", caption: "Browse saved screenshots, videos, and cloud share links.") {
                    Button("Open") { MediaGalleryWindowController.shared.open() }
                        .accessibilityLabel("Open Media Gallery")
                }
            }

            SettingsResetRow(caption: "Restores this page and the default look. Your Recent Captures limit is kept.") {
                isConfirmingReset = true
            }
        }
        .onAppear(perform: refreshLoginStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
        .alert("Restore General settings to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive, action: restoreDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your screenshots and recordings are left alone.")
        }
        .alert("Remove older captures?", isPresented: Binding(
            get: { pendingRetentionLimit != nil },
            set: { if !$0 { pendingRetentionLimit = nil } }
        ), presenting: pendingRetentionLimit) { limit in
            Button("Remove Older Captures", role: .destructive) {
                historyRetentionLimit = limit
                HistoryStore.shared.trimToRetentionLimit()
            }
            Button("Cancel", role: .cancel) {}
        } message: { limit in
            Text("Keeping the last \(limit) removes the \(HistoryStore.shared.records.count - limit) oldest entries from Recent Captures, along with BetterShot’s internal copies. Saved files and editable recording projects stay on your Mac.")
        }
    }

    private var fileNameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text("File name")
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    TextField("File name", text: $fileNameTemplate, prompt: Text(ScreenshotFileNaming.defaultTemplate))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minWidth: 180, idealWidth: 260, maxWidth: 300)
                    Menu {
                        ForEach(ScreenshotFileNaming.menuGroups) { group in
                            Section(group.title) {
                                ForEach(group.items) { item in
                                    Button(item.title) { fileNameTemplate += item.token }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add a date, a random string, or a counter")
                    .accessibilityLabel("Insert into the file name")
                }
            }
            HStack(spacing: 4) {
                Text("Example")
                Text(fileNamePreview)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .settingsRowPadding()
    }

    private func refreshLoginStatus() {
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        loginStatus = SMAppService.mainApp.status
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] != "1" else { return }
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "Couldn’t update Launch at Login. \(error.localizedDescription) Try again or check Login Items in System Settings."
        }
        refreshLoginStatus()
    }

    private func refreshFileNamePreview() {
        fileNamePreview = ScreenshotFileNaming.fileName(
            template: fileNameTemplate,
            extension: (ExportFormat(rawValue: exportFormatRaw) ?? .png).fileExtension,
            context: .init(counter: fileNameCounter)
        )
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
        showInMenuBar = true
        showInDock = false
        AppActivationPolicy.applyVisibility()
        if loginStatus == .enabled || loginStatus == .requiresApproval { setLaunchAtLogin(false) }
        appAppearanceRaw = AppAppearance.system.rawValue
        AppPreferences.applyAppearance()
        saveDir = NSHomeDirectory() + "/Desktop"
        copyAfterSave = true
        automaticallySaveScreenshots = AfterCaptureAction.save.defaultValue(for: .screenshot)
        playSound = true
        exportFormatRaw = ExportFormat.png.rawValue
        exportQuality = 0.9
        fileNameTemplate = ScreenshotFileNaming.defaultTemplate
        fileNameCounter = 1
        refreshFileNamePreview()
        showCaptureBarAtLaunch = true
        editorFullScreen = false
        defaultConfig = .default
        AppPreferences.defaultBeautifierConfig = .default
    }

    private func backgroundLabel(for style: BackgroundStyle) -> String {
        switch style {
        case .none: "No Background"
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
        VStack(alignment: .leading, spacing: 14) {
            noneButton

            swatchSection("Color") {
                LazyVGrid(columns: swatchColumns, spacing: 5) {
                    ForEach(SolidColor.presets) { color in
                        solidButton(color)
                    }
                }
                .fixedSize()
                HStack(spacing: 6) {
                    ColorPicker("Custom Color", selection: customColor, supportsOpacity: false)
                        .labelsHidden()
                        .controlSize(.small)
                    Text("Custom Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            swatchSection("Gradient") {
                LazyVGrid(columns: swatchColumns, spacing: 5) {
                    ForEach(GradientPreset.presets) { preset in
                        gradientButton(preset)
                    }
                }
                .fixedSize()
            }

            swatchSection("Image") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 5), count: 6), spacing: 5) {
                    ForEach(BundledBackgrounds.macAssets) { asset in
                        bundledImageButton(asset)
                    }
                }
                .fixedSize()
                customImageRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatchSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var noneButton: some View {
        Button {
            selectedStyle = .none
        } label: {
            Label("No Background", systemImage: selectedStyle == .none ? "checkmark" : "rectangle.slash")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityAddTraits(selectedStyle == .none ? .isSelected : [])
    }

    private var customColor: Binding<Color> {
        Binding(
            get: {
                guard case .solid(let color) = selectedStyle else { return AnnotationBackgroundColor.white.color }
                return color.color
            },
            set: { selectedStyle = AnnotationBackgroundStyle.solid(.custom(from: $0)).captureBackgroundStyle }
        )
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
            GradientBackgroundView(preset: preset)
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    Text("Custom Image\u{2026}").font(.caption)
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
            let pad = config.style == .none ? 0 : shortEdge * config.padding

            var canvasW = mockImageW + pad * 2
            var canvasH = mockImageH + pad * 2
            let _ = {
                if config.style != .none, let ratio = config.aspectRatio.numericValue {
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

            let cornerRadius = (config.style == .none ? 0 : config.cornerRadius) * shortEdge * min(fitted.width / canvasW, fitted.height / canvasH)
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
                        color: config.style != .none && config.shadowStrength > 0 ? .black.opacity(Double(config.shadowStrength * 0.3)) : .clear,
                        radius: config.style != .none && config.shadowStrength > 0 ? max(2, shortEdge * 0.02 * (1 + config.shadowStrength)) : 0,
                        x: 0,
                        y: config.style != .none && config.shadowStrength > 0 ? shortEdge * 0.01 * (1 + config.shadowStrength) : 0
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
            GradientBackgroundView(preset: preset)
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
    @AppStorage("bs_overlayFollowsMouse") private var overlayFollowsMouse: Bool = true
    @AppStorage("bs_overlayPinnedDisplayID") private var overlayPinnedDisplayIDRaw: Int = 0
    @AppStorage("bs_openEditorAfterCapture") private var openEditorAfterCapture = false
    @AppStorage("bs_keepInDeckUntilSaved") private var keepInDeckUntilSaved = false
    @AppStorage("bs_captureRegionOnRelease") private var captureRegionOnRelease = false
    @State private var isConfirmingReset = false

    private var selfTimerDelay: Binding<SelfTimerDelay> {
        Binding(
            get: { SelfTimerDelay(rawValue: selfTimerRaw) ?? .off },
            set: { selfTimerRaw = $0.rawValue }
        )
    }

    private var connectedScreens: [(id: CGDirectDisplayID, screen: NSScreen)] {
        NSScreen.screens.compactMap { screen in
            guard let id = ActiveDisplayResolver.displayID(for: screen) else { return nil }
            return (id, screen)
        }
    }

    private var overlayPinnedDisplayID: Binding<CGDirectDisplayID?> {
        Binding(
            get: {
                overlayPinnedDisplayIDRaw == 0 ? nil : CGDirectDisplayID(overlayPinnedDisplayIDRaw)
            },
            set: { overlayPinnedDisplayIDRaw = Int($0 ?? 0) }
        )
    }

    var body: some View {
        SettingsPage {
            SettingsGroup("Timer") {
                SettingRow("Countdown", caption: "A moment to open a menu or hover something before the shot.") {
                    Picker("Countdown", selection: selfTimerDelay) {
                        ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                            Text(delay.label).tag(delay)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsGroup("Region") {
                SettingToggle("Capture as soon as I let go", caption: captureRegionOnRelease
                    ? "The shot is taken when you release the mouse."
                    : "The area stays up with handles to adjust it. Return or a double-click takes the shot.",
                    isOn: $captureRegionOnRelease)
                SettingsDivider()
                SettingRow("Show the selector on") {
                    Picker("Show the selector on", selection: $overlayFollowsMouse) {
                        Text("The screen with the pointer").tag(true)
                        Text("A specific screen").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .onChange(of: overlayFollowsMouse) { _, followsMouse in
                    guard !followsMouse, overlayPinnedDisplayIDRaw == 0,
                          let mainScreen = NSScreen.main ?? NSScreen.screens.first,
                          let mainID = ActiveDisplayResolver.displayID(for: mainScreen) else { return }
                    overlayPinnedDisplayIDRaw = Int(mainID)
                }
                if !overlayFollowsMouse {
                    SettingsDivider()
                    SettingRow("Screen") {
                        Picker("Screen", selection: overlayPinnedDisplayID) {
                            ForEach(connectedScreens, id: \.id) { entry in
                                Text(entry.screen.localizedName).tag(Optional(entry.id))
                            }
                            if let pinned = overlayPinnedDisplayID.wrappedValue, !connectedScreens.contains(where: { $0.id == pinned }) {
                                Text("Disconnected screen (using the one with the pointer)").tag(Optional(pinned))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            } footer: {
                Text("Your last area opens already selected. Press Return to capture it again, drag its handles to adjust it, or draw a new one. Space switches to window selection, and Escape cancels.")
            }

            SettingsGroup("After Capture") {
                SettingToggle("Open the editor straight away", caption: "Otherwise a preview card appears. Automatic saving follows General \u{203A} Saving.", isOn: $openEditorAfterCapture)
                SettingsDivider()
                SettingToggle("Keep screenshot previews open", caption: "Unsaved captures stay until you act on them. Saved ones follow Overlay \u{203A} Hide After.", isOn: $keepInDeckUntilSaved)
                    .onChange(of: keepInDeckUntilSaved) { PreviewOverlay.shared.refreshSettings() }
            }

            SettingsResetRow(caption: "Keyboard shortcuts are not affected.") {
                isConfirmingReset = true
            }
        }
        .alert("Restore Capture settings to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                selfTimerRaw = 0
                overlayFollowsMouse = true
                overlayPinnedDisplayIDRaw = 0
                openEditorAfterCapture = false
                keepInDeckUntilSaved = false
                captureRegionOnRelease = false
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Recording Settings

struct RecordingSettingsTab: View {
    @AppStorage(AfterCaptureAction.save.storageKey(for: .recording)) private var saveToFolder = false
    @AppStorage(BetterShotPreferences.recordingCameraDeviceIDKey) private var cameraID: String = ""
    @AppStorage(BetterShotPreferences.recordingMicrophoneDeviceIDKey) private var microphoneID: String = ""
    @AppStorage(BetterShotPreferences.recordingSystemAudioKey) private var captureAudio: Bool = false
    @AppStorage(AppPreferences.recordingCaptureKeystrokesKey) private var captureKeystrokes: Bool = false
    @AppStorage(BetterShotPreferences.recordingStartDelaySecondsKey) private var startDelaySeconds: Int = 0
    @AppStorage(BetterShotPreferences.recordingTeleprompterEnabledKey) private var teleprompterEnabled: Bool = false
    @AppStorage(AppPreferences.openEditorAfterRecordingKey) private var openEditor = AppPreferences.openEditorAfterRecording
    @State private var isConfirmingReset = false
    @State private var exportSettings = RecordingExportPreferences.lastSettings

    private var cameras: [AVCaptureDevice] { RecordingDeviceCatalog.cameras() }
    private var microphones: [AVCaptureDevice] { RecordingDeviceCatalog.microphones() }

    /// Writes one field onto the stored settings so values changed elsewhere, such as an editor export, are kept.
    private func exportSetting<Value>(_ keyPath: WritableKeyPath<VideoCompressionSettings, Value>) -> Binding<Value> {
        Binding(
            get: { exportSettings[keyPath: keyPath] },
            set: { value in
                var settings = RecordingExportPreferences.lastSettings
                settings[keyPath: keyPath] = value
                RecordingExportPreferences.lastSettings = settings
                exportSettings = settings
            }
        )
    }

    var body: some View {
        SettingsPage {
            SettingsGroup("Include") {
                SettingRow("Camera") {
                    Picker("Camera", selection: $cameraID) {
                        Text("Off").tag("")
                        if !cameraID.isEmpty && !cameras.contains(where: { $0.uniqueID == cameraID }) {
                            Text("Selected camera (disconnected)").tag(cameraID)
                        }
                        ForEach(cameras, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingRow("Microphone", caption: ScreenRecordingCaptureOptions.supportsMicrophone ? nil : "Requires macOS 15 or later.") {
                    Picker("Microphone", selection: $microphoneID) {
                        Text("Off").tag("")
                        if !microphoneID.isEmpty && !microphones.contains(where: { $0.uniqueID == microphoneID }) {
                            Text("Selected microphone (disconnected)").tag(microphoneID)
                        }
                        ForEach(microphones, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!ScreenRecordingCaptureOptions.supportsMicrophone)
                }
                SettingsDivider()
                SettingToggle("System audio", caption: "The sound your Mac is playing.", isOn: $captureAudio)
                SettingsDivider()
                SettingToggle("Keystrokes", caption: "Shows shortcuts and special keys, never plain typing. Needs Input Monitoring.", isOn: $captureKeystrokes)
                    .onChange(of: captureKeystrokes) { _, isOn in
                        if isOn && !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
                    }
            } footer: {
                Text("The recording bar offers the same choices right before you record. The cursor is always saved separately so you can restyle it in the editor.")
            }

            SettingsGroup("Before Recording") {
                SettingRow("Countdown", caption: "Shown on screen before the capture begins.") {
                    Picker("Countdown", selection: $startDelaySeconds) {
                        Text("None").tag(0)
                        Text("1 second").tag(1)
                        Text("3 seconds").tag(3)
                        Text("5 seconds").tag(5)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingToggle("Teleprompter", caption: "Floats your script over the recording area without appearing in the capture.", isOn: $teleprompterEnabled)
            }

            SettingsGroup("After Recording") {
                SettingToggle("Open the editor when I stop", caption: "Otherwise a preview card appears with an Edit button.", isOn: $openEditor)
                SettingsDivider()
                SettingToggle("Save to the save folder", caption: "Renders a video with the cursor and camera. Longer recordings take a while.", isOn: $saveToFolder)
            }

            SettingsGroup("Default Video Export") {
                SettingRow("Frame rate", caption: "60 fps keeps motion smoother. 30 fps renders faster.") {
                    Picker("Frame rate", selection: Binding(
                        get: { exportSettings.effectiveFrameRate },
                        set: { exportSetting(\.frameRate).wrappedValue = $0 }
                    )) {
                        ForEach(VideoExportFrameRate.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingRow("Render speed") {
                    Picker("Render speed", selection: exportSetting(\.speed)) {
                        ForEach(VideoCompressionSpeed.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingRow("Resolution", caption: "Smaller resolutions render sooner.") {
                    Picker("Resolution", selection: exportSetting(\.resolution)) {
                        ForEach(VideoCompressionResolution.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingRow("Codec") {
                    Picker("Codec", selection: exportSetting(\.codec)) {
                        ForEach(VideoCompressionCodec.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } footer: {
                Text("New projects start from these, and exporting from the editor updates them.")
            }
            .onAppear { exportSettings = RecordingExportPreferences.lastSettings }

            SettingsResetRow(caption: nil) {
                isConfirmingReset = true
            }
        }
        .alert("Restore Recording settings to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                cameraID = ""
                microphoneID = ""
                captureAudio = false
                captureKeystrokes = false
                startDelaySeconds = 0
                teleprompterEnabled = false
                openEditor = false
                saveToFolder = false
                exportSettings = VideoCompressionSettings()
                RecordingExportPreferences.lastSettings = exportSettings
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Shortcut Settings

struct ShortcutSettingsTab: View {
    @State private var isConfirmingReset = false
    @State private var search = ""
    @State private var category: ShortcutService.Group?
    @State private var recordingAction: ShortcutService.Action?
    @State private var permissions = OnboardingPermissions()

    init(category: ShortcutService.Group? = nil) {
        _category = State(initialValue: category)
    }

    var body: some View {
        SettingsPage {
            HStack(spacing: 12) {
                TextField("Search shortcuts", text: $search, prompt: Text("Search shortcuts"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                Picker("Category", selection: $category) {
                    Text("All Actions").tag(ShortcutService.Group?.none)
                    ForEach(ShortcutService.Group.allCases, id: \.self) { group in
                        Text(group.title).tag(Optional(group))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingsGroup("Access") {
                SettingsPermissionRow(permission: .accessibility, permissions: permissions)
            } footer: {
                if permissions.shortcutsNeedRestart {
                    Text("Access is allowed, but shortcuts aren’t active. Save your work, then quit and reopen BetterShot.")
                } else {
                    Text("Existing shortcuts are kept. Additional actions start unassigned. Editor shortcuts take priority over global ones while that editor is open.")
                }
            }

            ForEach(ShortcutService.Group.allCases, id: \.self) { group in
                let actions = ShortcutService.Action.allCases.filter {
                    $0.group == group && (category == nil || category == group)
                        && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                            || group.title.localizedCaseInsensitiveContains(search))
                }
                if !actions.isEmpty {
                    SettingsGroup(group.title) {
                        ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                            if index > 0 { SettingsDivider() }
                            ShortcutRow(action: action, recordingAction: $recordingAction)
                        }
                    } footer: {
                        Text(actions.first?.scope == .global
                             ? "Available across macOS. Use Command, Control, or Option with a key."
                             : "Available in this editor. Single keys work when you are not typing in a text field.")
                    }
                }
            }

            SettingsResetRow(caption: nil) {
                isConfirmingReset = true
            }
        }
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
        .onChange(of: search) { recordingAction = nil }
        .onChange(of: category) { recordingAction = nil }
        .alert("Restore all shortcuts to their defaults?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                recordingAction = nil
                ShortcutService.shared.restoreDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes custom bindings and restores the original capture and editor keys. Additional actions become unassigned.")
        }
    }
}

struct ShortcutRow: View {
    let action: ShortcutService.Action
    @Binding var recordingAction: ShortcutService.Action?
    @State private var service = ShortcutService.shared
    @State private var errorMessage: String?

    private var shortcut: ShortcutService.Shortcut? {
        let _ = service.revision
        let saved = service.loadShortcut(for: action) ?? action.defaultShortcut
        return saved?.keyCode == UInt32.max ? nil : saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(action.title).frame(maxWidth: .infinity, alignment: .leading)
                if recordingAction == action {
                    ShortcutRecorderView { keyCode, modifiers in
                        persist(.init(keyCode: keyCode, modifiers: modifiers, enabled: true))
                        recordingAction = nil
                    } onCancel: {
                        recordingAction = nil
                    }
                    .frame(width: 124, height: 24)
                    Button("Cancel") { recordingAction = nil }
                } else {
                    Button {
                        errorMessage = nil
                        recordingAction = action
                    } label: {
                        Text(shortcut?.displayString ?? "Record Shortcut")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(shortcut?.enabled == false ? .secondary : .primary)
                            .frame(minWidth: 110)
                    }
                    .accessibilityLabel("Record shortcut for \(action.title)")
                    .accessibilityValue(shortcut?.accessibilityDescription ?? "Unassigned")
                    Toggle("Enable \(action.title)", isOn: Binding(
                        get: { shortcut?.enabled ?? false },
                        set: { enabled in
                            guard var updated = shortcut else { return }
                            updated.enabled = enabled
                            persist(updated)
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(shortcut == nil)
                    Menu {
                        Button("Clear Shortcut") {
                            persist(.init(keyCode: .max, modifiers: 0, enabled: false))
                        }.disabled(shortcut == nil)
                        Button("Restore Default") {
                            if let fallback = action.defaultShortcut,
                               let error = service.validationError(for: fallback, action: action) {
                                errorMessage = error
                            } else {
                                errorMessage = nil
                                service.resetShortcut(for: action)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Options for \(action.title) shortcut")
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    private func persist(_ updated: ShortcutService.Shortcut) {
        if let error = service.validationError(for: updated, action: action) {
            errorMessage = error
            return
        }
        errorMessage = nil
        service.saveShortcut(updated, for: action)
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
        ShortcutService.shared.beginRecordingShortcut()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}

    static func dismantleNSView(_ nsView: ShortcutRecorderNSView, coordinator: ()) {
        nsView.removeMonitor()
        ShortcutService.shared.endRecordingShortcut()
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
            guard let self, self.window?.isKeyWindow == true, self.window?.firstResponder === self else { return event }

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

            if keyCode == UInt32(kVK_Tab) { self.onCancel?(); return event }
            guard !event.isARepeat else { return nil }

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
        StudioChrome.accentNSColor.withAlphaComponent(0.15).setFill()
        path.fill()
        StudioChrome.accentNSColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let text = "Press shortcut..." as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: StudioChrome.accentNSColor,
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

// MARK: - About

struct AboutTab: View {
    private let updater = AppUpdater.shared
    private static let repository = URL(string: "https://github.com/KartikLabhshetwar/better-shot")!

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
        SettingsPage {
            header

            SettingsGroup("Updates") {
                SettingRow("Software update", caption: updateCaption) { updateControl }
                SettingsDivider()
                SettingRow("Release notes", caption: "See what changed in each version.") {
                    Button("What’s New…") { ReleaseNotesWindowController.shared.show() }
                }
                SettingsDivider()
                SettingRow("Tour", caption: "Walk through capturing, recording, and editing again.") {
                    Button("Take the Tour…") { OnboardingWindowController.shared.show(replay: true) }
                }
            } footer: {
                Text("Update checks contact GitHub only. Your captures never leave this Mac unless you share them.")
            }

            SettingsGroup("Open Source") {
                SettingRow("Source code", caption: "Browse the code and every release.") {
                    Link("View on GitHub", destination: Self.repository)
                }
                SettingsDivider()
                SettingRow("Feedback", caption: "Report a bug or suggest a feature.") {
                    Link("Open an Issue", destination: Self.repository.appending(path: "issues"))
                }
            } footer: {
                Text("BetterShot is free and open source under the BSD 3-Clause license. If it saves you time, a star on GitHub helps others find it.")
            }

            SettingsGroup("Credits") {
                SettingRow("Created by") {
                    Text("Kartik Labhshetwar").foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingRow("Follow along") {
                    Link("@code_kartik on X", destination: URL(string: "https://x.com/code_kartik")!)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
            }
            Text("BetterShot")
                .font(.title.weight(.semibold))
            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("One app for the whole screen. Capture, record, and edit on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var updateCaption: String {
        switch updater.state {
        case .idle: "BetterShot \(version) is installed."
        case .checking: "Checking for a new version\u{2026}"
        case .available(let newVersion, _): "Version \(newVersion) is available."
        case .downloading(let progress): "Downloading\u{2026} \(Int(progress * 100))%"
        case .readyToInstall(let newVersion, _): "Version \(newVersion) is ready to install."
        case .installing: "Installing\u{2026}"
        case .upToDate: "BetterShot \(version) is the latest version."
        case .failed(let message): message
        }
    }

    @ViewBuilder
    private var updateControl: some View {
        switch updater.state {
        case .idle, .upToDate:
            Button("Check for Updates\u{2026}") {
                Task { await updater.checkForUpdates() }
            }

        case .checking, .installing:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(updateCaption)

        case .available(let newVersion, let url):
            Button("Download and Install") {
                Task { await updater.downloadAndInstall(version: newVersion, url: url) }
            }
            .buttonStyle(.borderedProminent)

        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(width: 120)
                    .accessibilityLabel("Download progress")
                Button("Cancel") { updater.cancelDownload() }
            }

        case .readyToInstall(_, let dmgPath):
            Button("Install and Relaunch") {
                Task { await updater.installUpdate(dmgPath: dmgPath) }
            }
            .buttonStyle(.borderedProminent)

        case .failed:
            Button("Try Again") {
                Task { await updater.checkForUpdates() }
            }
        }
    }
}
