import SwiftUI
import Carbon

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            CaptureSettingsTab()
                .tabItem {
                    Label("Capture", systemImage: "camera.viewfinder")
                }

            HistoryTab()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("bs_saveDirectory") private var saveDir = NSHomeDirectory() + "/Desktop"
    @AppStorage("bs_copyAfterSave") private var copyAfterSave = true
    @AppStorage("bs_playSound") private var playSound = true
    @AppStorage("bs_showOverlay") private var showOverlay = true
    @AppStorage("bs_autoApplyBackground") private var autoApply = false

    var body: some View {
        Form {
            Section("Save") {
                TextField("Save directory", text: $saveDir)
                    .textFieldStyle(.roundedBorder)

                Toggle("Copy to clipboard after saving", isOn: $copyAfterSave)
            }

            Section("Capture") {
                Toggle("Play shutter sound", isOn: $playSound)
                Toggle("Show floating preview after capture", isOn: $showOverlay)
                Toggle("Auto-apply default background", isOn: $autoApply)
            }

            Section("Export") {
                Picker("Format", selection: Binding(
                    get: { AppPreferences.exportFormat },
                    set: { AppPreferences.exportFormat = $0 }
                )) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if AppPreferences.exportFormat == .jpeg {
                    Slider(
                        value: Binding(
                            get: { AppPreferences.exportQuality },
                            set: { AppPreferences.exportQuality = $0 }
                        ),
                        in: 0.1...1.0,
                        step: 0.05
                    ) {
                        Text("Quality: \(Int(AppPreferences.exportQuality * 100))%")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Capture Settings

struct CaptureSettingsTab: View {
    var body: some View {
        Form {
            Section("Self Timer") {
                Picker("Delay", selection: Binding(
                    get: { AppPreferences.selfTimerDelay },
                    set: { AppPreferences.selfTimerDelay = $0 }
                )) {
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
                }
            }

            Section("Overlay") {
                Picker("Position", selection: Binding(
                    get: { AppPreferences.overlayPosition },
                    set: { AppPreferences.overlayPosition = $0 }
                )) {
                    Text("Bottom Right").tag(OverlayPosition.bottomRight)
                    Text("Bottom Left").tag(OverlayPosition.bottomLeft)
                }

                Stepper(
                    "Dismiss after \(Int(AppPreferences.overlayDismissDelay))s",
                    value: Binding(
                        get: { AppPreferences.overlayDismissDelay },
                        set: { AppPreferences.overlayDismissDelay = $0 }
                    ),
                    in: 2...30,
                    step: 1
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutRow: View {
    let label: String
    let action: ShortcutService.Action

    @State private var shortcut: ShortcutService.Shortcut?

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

            Text(shortcutDisplayString)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
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
}

// MARK: - History

struct HistoryTab: View {
    var body: some View {
        List {
            if HistoryStore.shared.records.isEmpty {
                ContentUnavailableView("No captures yet", systemImage: "photo.on.rectangle.angled")
            } else {
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
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)

            Text("BetterShot")
                .font(.title2.weight(.semibold))

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("A local-first screenshot tool for macOS.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
