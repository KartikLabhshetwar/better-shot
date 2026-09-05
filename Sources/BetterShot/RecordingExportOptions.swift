//
//  RecordingExportOptions.swift
//  BetterShot
//
//  Export settings are asked for at the moment of export rather than parked
//  in a collapsed inspector section nobody opens. Mirrors the share flow in
//  CloudUploadOptions.swift: a button opens a small options popover, and
//  confirming remembers the choice as the default for next time.
//

import SwiftUI

/// Remembers the last-confirmed export settings so a recording that has never
/// been exported starts from what the user picked previously instead of the
/// factory defaults. Projects that already saved their own settings keep them.
enum RecordingExportPreferences {
    private static let settingsKey = "recordingExportDefaultSettings"

    static var lastSettings: VideoCompressionSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: settingsKey),
                  let decoded = try? JSONDecoder().decode(
                    VideoCompressionSettings.self,
                    from: data
                  ) else {
                return VideoCompressionSettings()
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}

/// The options form shown from the Export button: quality, codec, resolution,
/// container, and whether to keep audio. Confirming hands back the settings
/// and remembers them.
struct RecordingExportOptionsPopover: View {
    let initialSettings: VideoCompressionSettings
    let onConfirm: (VideoCompressionSettings) -> Void

    @State private var settings: VideoCompressionSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(
        initialSettings: VideoCompressionSettings,
        onConfirm: @escaping (VideoCompressionSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.onConfirm = onConfirm
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            Text("Export Options")
                .font(.inspectorSectionHeader)
                .padding(.bottom, 2)

            segmented("Render Speed", options: VideoCompressionSpeed.allCases, selection: $settings.speed)
            Text("Fast keeps 60 fps with lighter motion blur. Slow uses more blur samples during zooms.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            segmented("Quality", options: VideoCompressionQuality.allCases, selection: $settings.quality)
            segmented("Codec", options: VideoCompressionCodec.allCases, selection: $settings.codec)
            segmented("Resolution", options: VideoCompressionResolution.allCases, selection: $settings.resolution)

            // `container` is optional on disk for backwards compatibility,
            // but the control always shows a concrete choice.
            segmented(
                "Format",
                options: VideoExportContainer.allCases,
                selection: Binding(
                    get: { settings.effectiveContainer },
                    set: { settings.container = $0 }
                )
            )

            Text(formatHint)
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("Include audio")
                    .font(.inspectorLabel)
                    .foregroundStyle(.primary.opacity(0.82))

                Spacer(minLength: 8)

                Toggle("Include audio", isOn: Binding(
                    get: { !settings.removeAudio },
                    set: { settings.removeAudio = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.top, 2)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Export") {
                    let confirmed = settings
                    RecordingExportPreferences.lastSettings = confirmed
                    dismiss()
                    onConfirm(confirmed)
                }
                .keyboardShortcut(.defaultAction)
                .tint(.accentColor)
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(InspectorMetrics.horizontalPadding)
        // Matches the Studio inspector's ideal column width, so the controls
        // keep the exact proportions they had in the sidebar.
        .frame(width: 280)
        // Replaces the popover's vibrancy with the panel surface these
        // controls are drawn for; without it their low-opacity track and
        // selection fills composite over the desktop and disappear.
        .presentationBackground(InspectorControlPalette.panelBackground(for: colorScheme))
    }

    private var formatHint: String {
        switch settings.effectiveContainer {
        case .mov:
            "QuickTime format. Edited recordings still need rendering."
        case .mp4:
            "Plays on more platforms, including Windows, browsers, and Slack."
        }
    }

    /// Segmented row matching the inspector's group-label-above-control
    /// rhythm, so the popover reads as the same control system as the panel.
    private func segmented<Option: Hashable & RawRepresentable>(
        _ title: String,
        options: [Option],
        selection: Binding<Option>
    ) -> some View where Option.RawValue == String {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
            InspectorGroupLabel(title)
            InspectorSegmented(
                options: options,
                isSelected: { $0 == selection.wrappedValue },
                onTap: { selection.wrappedValue = $0 },
                label: { Text($0.rawValue).font(.inspectorLabel) }
            )
        }
    }
}

/// Wraps any trigger content in a button that opens the export options
/// popover before firing `onExport`. Drop-in replacement for a plain
/// `Button(action: model.export) { ... }` at an export call site.
struct RecordingExportButton<Label: View>: View {
    let currentSettings: VideoCompressionSettings
    let onExport: (VideoCompressionSettings) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showingOptions = false

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            label()
        }
        .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
            RecordingExportOptionsPopover(
                initialSettings: currentSettings,
                onConfirm: onExport
            )
        }
    }
}
