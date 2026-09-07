import AppKit
import SwiftUI

// Visible names make every inspector discoverable without hover-only tooltips.
// AppKit owns menu navigation, focus, and accessibility.
struct StudioInspectorTabs: NSViewRepresentable {
    @Binding var selection: StudioInspectorTab
    let isAvailable: (StudioInspectorTab) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let control = NSPopUpButton(frame: .zero, pullsDown: false)
        control.controlSize = .large
        control.bezelStyle = .rounded
        control.autoenablesItems = false
        for tab in StudioInspectorTab.allCases {
            control.addItem(withTitle: tab.title)
            control.lastItem?.image = NSImage(systemSymbolName: tab.systemImage,
                                              accessibilityDescription: nil)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        control.setAccessibilityLabel("Video inspector")
        return control
    }

    func updateNSView(_ control: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        for (index, tab) in StudioInspectorTab.allCases.enumerated() {
            control.item(at: index)?.isEnabled = isAvailable(tab)
        }
        control.selectItem(at: StudioInspectorTab.allCases.firstIndex(of: selection) ?? 0)
    }

    final class Coordinator: NSObject {
        var selection: Binding<StudioInspectorTab>
        init(selection: Binding<StudioInspectorTab>) { self.selection = selection }
        @objc func select(_ sender: NSPopUpButton) {
            guard StudioInspectorTab.allCases.indices.contains(sender.indexOfSelectedItem),
                  sender.selectedItem?.isEnabled == true else { return }
            selection.wrappedValue = StudioInspectorTab.allCases[sender.indexOfSelectedItem]
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
            InspectorSlider("Amount", value: $value, range: range, format: .percent())
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
}
