import AppKit
import SwiftUI

// NSSegmentedControl owns keyboard navigation and exposes native per-segment tooltips.
struct StudioInspectorTabs: NSViewRepresentable {
    @Binding var selection: StudioInspectorTab
    let isAvailable: (StudioInspectorTab) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = StudioInspectorTab.allCases.count
        control.trackingMode = .selectOne
        control.segmentStyle = .rounded
        control.controlSize = .large
        control.selectedSegmentBezelColor = StudioChrome.accentNSColor
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        control.setAccessibilityLabel("Video inspector")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        for (index, tab) in StudioInspectorTab.allCases.enumerated() {
            control.setImage(NSImage(systemSymbolName: tab.systemImage,
                                     accessibilityDescription: tab.title), forSegment: index)
            control.setWidth(44, forSegment: index)
            control.setEnabled(isAvailable(tab), forSegment: index)
            control.setToolTip(isAvailable(tab) ? tab.title : tab.unavailableHelp, forSegment: index)
        }
        control.selectedSegment = StudioInspectorTab.allCases.firstIndex(of: selection) ?? 0
    }

    final class Coordinator: NSObject {
        var selection: Binding<StudioInspectorTab>
        init(selection: Binding<StudioInspectorTab>) { self.selection = selection }
        @objc func select(_ sender: NSSegmentedControl) {
            guard StudioInspectorTab.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = StudioInspectorTab.allCases[sender.selectedSegment]
        }
    }
}

/// A native disclosure keeps keyboard and accessibility behavior consistent across effects.
struct StudioEffectSection<Content: View, Accessory: View>: View {
    let title: String
    var systemImage = "slider.horizontal.3"
    @Binding var isExpanded: Bool
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                accessory()
            }
            .frame(minHeight: 28)
        }
        .padding(12)
        .studioEffectCard()
    }
}

/// These effects already use zero for off; keep the last amount when toggled back on.
struct StudioAmountEffect: View {
    let title: String
    let systemImage: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let defaultValue: CGFloat
    let presets: [CGFloat]
    @State private var isExpanded = false
    @State private var toggleState = StudioEffectToggleState()

    var body: some View {
        StudioEffectSection(title: title, systemImage: systemImage, isExpanded: $isExpanded) {
            Toggle(title, isOn: Binding(
                get: { value > 0 },
                set: { enabled in
                    value = toggleState.amount(enabled: enabled, current: value, defaultValue: defaultValue)
                    if enabled { isExpanded = true }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Enable \(title.lowercased())")
        } content: {
            StudioEffectSlider("Amount", value: $value, range: range, format: .percent())
            HStack(spacing: 4) {
                ForEach(presets, id: \.self) { amount in
                    Button(InspectorValueFormat.percent().displayString(for: amount)) {
                        value = amount
                    }
                    .buttonStyle(EditorButtonStyle(selected: abs(value - amount) < 0.001))
                }
            }
        }
    }
}

struct StudioEffectToggleState {
    private var previousAmount: CGFloat?

    mutating func amount(enabled: Bool, current: CGFloat, defaultValue: CGFloat) -> CGFloat {
        if enabled { return previousAmount ?? defaultValue }
        if current > 0 { previousAmount = current }
        return 0
    }
}

/// Keep the existing editable numeric field and add a visible native slider below it.
struct StudioEffectSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: InspectorValueFormat

    init(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, format: InspectorValueFormat) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        VStack(spacing: 6) {
            InspectorSlider(title, value: $value, range: range, format: format)
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(format.displayString(for: value))
        }
    }
}

enum StudioInspectorTab: String, CaseIterable, Identifiable {
    case background, camera, audio, cursor, keyboard, captions, zoom
    var id: Self { self }
    var title: String {
        switch self {
        case .background: "Background"
        case .camera: "Camera"
        case .audio: "Audio"
        case .cursor: "Cursor"
        case .keyboard: "Keystrokes"
        case .captions: "Captions"
        case .zoom: "Zoom & Clips"
        }
    }
    var systemImage: String {
        switch self {
        case .background: "photo"
        case .camera: "web.camera"
        case .audio: "speaker.wave.2"
        case .cursor: "cursorarrow"
        case .keyboard: "keyboard"
        case .captions: "captions.bubble"
        case .zoom: "plus.magnifyingglass"
        }
    }
    var unavailableHelp: String {
        switch self {
        case .camera: "Camera — this recording has no camera track"
        case .cursor: "Cursor — this recording has no captured cursor"
        case .keyboard: "Keystrokes — this recording has no captured keystrokes"
        case .captions: "Captions — no speech track is available"
        default: title
        }
    }
}
