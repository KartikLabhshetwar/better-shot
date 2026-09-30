import SwiftUI

struct OverlaySettingsTab: View {
    var resourceBundle: Bundle = .main
    @AppStorage("bs_overlayPosition") private var position = OverlayPosition.bottomRight.rawValue
    @AppStorage("bs_overlayCardSize") private var size = OverlayCardSize.small.rawValue
    @AppStorage("bs_overlayEdgeMargin") private var margin = AppPreferences.overlayEdgeMarginDefault
    @AppStorage("bs_overlayDismissDelay") private var delay = 5.0
    @AppStorage(AppPreferences.overlayAlwaysShowActionsKey) private var alwaysShowActions = false
    @AppStorage(AppPreferences.overlayToolLayoutKey) private var layoutData = Data()
    @State private var confirmingReset = false

    private var layout: OverlayToolLayout { OverlayToolLayout(data: layoutData) }

    var body: some View {
        Form {
            Section {
                Picker("Layout preset", selection: Binding(
                    get: { layout.preset },
                    set: { if let preset = $0.layout { layoutData = preset.data } }
                )) {
                    ForEach(OverlayLayoutPreset.allCases) { preset in
                        Text(preset.title).tag(preset).disabled(preset == .custom)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Screen position", selection: $position) {
                    Text("Bottom Right").tag(OverlayPosition.bottomRight.rawValue)
                    Text("Bottom Left").tag(OverlayPosition.bottomLeft.rawValue)
                }
                Picker("Card size", selection: $size) {
                    ForEach(OverlayCardSize.allCases) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Quick Setup")
            } footer: {
                Text("Standard keeps every action. Sharing puts cloud sharing in the center. Minimal keeps Copy, Save, and Dismiss; click the image to edit.")
            }

            Section {
                VStack(spacing: 12) {
                    OverlayLayoutEditor(layout: Binding(
                        get: { layout }, set: { layoutData = $0.data }
                    ), resourceBundle: resourceBundle)
                    Text("Click a position to choose its tool")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } header: {
                Text("Tool Positions")
            } footer: {
                Text("Move Pin, Copy, Save, Edit, Cloud Share, or Dismiss to any of the six positions. Choosing a tool already on the card swaps positions. Choose Empty to hide a tool. Dismiss always stays available.")
            }

            Section {
                Toggle("Always show actions", isOn: $alwaysShowActions)
                InspectorSlider("Edge Margin", value: Binding(
                    get: { CGFloat(margin) }, set: { margin = (Double($0) / 4).rounded() * 4 }
                ), range: CGFloat(AppPreferences.overlayEdgeMarginRange.lowerBound)...CGFloat(AppPreferences.overlayEdgeMarginRange.upperBound),
                   format: .points)
                InspectorSlider("Hide After", value: Binding(
                    get: { CGFloat(delay) }, set: { delay = Double($0.rounded()) }
                ), range: CGFloat(AppPreferences.overlayDismissRange.lowerBound)...CGFloat(AppPreferences.overlayDismissRange.upperBound),
                   format: .seconds(never: CGFloat(AppPreferences.overlayDismissNever)))
            } header: {
                Text("Advanced")
            } footer: {
                Text("Actions otherwise appear on hover or keyboard focus. Choose Never to keep previews visible. Unsaved captures, sharing progress, errors, and finished links stay available until you act on them. Changes apply immediately.")
            }

            Section {
                Button("Restore Overlay Defaults…", role: .destructive) { confirmingReset = true }
            } footer: {
                Text("Resets only the overlay. Your captures, cloud links, and other settings are kept.")
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .onChange(of: position) { PreviewOverlay.shared.refreshSettings() }
        .onChange(of: size) { PreviewOverlay.shared.refreshSettings() }
        .onChange(of: margin) { PreviewOverlay.shared.refreshSettings() }
        .onChange(of: delay) { PreviewOverlay.shared.refreshSettings() }
        .alert("Restore overlay defaults?", isPresented: $confirmingReset) {
            Button("Restore Defaults", role: .destructive) {
                AppPreferences.resetOverlaySettings()
                PreviewOverlay.shared.refreshSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The standard tool layout, size, position, timing, and visibility will be restored.")
        }
    }
}

struct OverlayLayoutEditor: View {
    @Binding var layout: OverlayToolLayout
    var resourceBundle: Bundle = .main
    @State private var selectedSlot: OverlayToolSlot?
    private let size = OverlayCardSize.large.thumbnailSize

    var body: some View {
        ZStack {
            if let url = OnboardingSample.coast.sourceURL(in: resourceBundle),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
            } else {
                Rectangle().fill(Color(nsColor: .darkGray))
            }
            Color.black.opacity(0.45)
            OverlayToolArrangement(scale: OverlayCardSize.large.controlScale) { slot in
                Button { selectedSlot = slot } label: {
                    if let tool = layout.assignments[slot] {
                        OverlayToolLabel(tool: tool, slot: slot, scale: OverlayCardSize.large.controlScale)
                    } else {
                        Image(systemName: "plus.circle.dashed")
                            .font(.system(size: 24)).foregroundStyle(.white)
                            .frame(width: 33, height: 33)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(slot.title): \(layout.assignments[slot]?.title ?? "Empty")")
                .accessibilityHint("Choose a tool for this position")
                .help("\(slot.title): \(layout.assignments[slot]?.title ?? "Empty") — click to change")
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        .popover(item: $selectedSlot) { slot in
            VStack(alignment: .leading, spacing: 12) {
                Text(slot.title).font(.headline)
                Picker("Tool", selection: Binding<OverlayTool?>(
                    get: { layout.assignments[slot] },
                    set: { layout.assign($0, to: slot); selectedSlot = nil }
                )) {
                    ForEach(OverlayTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(Optional(tool))
                    }
                    Text("Empty").tag(Optional<OverlayTool>.none)
                        .disabled(layout.assignments[slot] == .dismiss)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            .padding(16)
            .frame(width: 200, alignment: .leading)
        }
    }
}
