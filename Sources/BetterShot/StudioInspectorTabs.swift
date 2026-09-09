import AppKit
import SwiftUI

struct StudioInspectorTabs: View {
    @Binding var selection: StudioInspectorTab
    let isAvailable: (StudioInspectorTab) -> Bool

    var body: some View {
        VStack(spacing: 12) {
            ForEach(StudioInspectorTab.allCases) { tab in
                Button { selection = tab } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(EditorButtonStyle(selected: selection == tab))
                .disabled(!isAvailable(tab))
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("video-inspector-\(tab.rawValue)")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .frame(width: 56)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video inspector")
    }
}

/// Keep each effect visible in its existing card without a collapse control.
struct StudioEffectSection<Content: View, Accessory: View>: View {
    let title: String
    var systemImage = "slider.horizontal.3"
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                accessory()
            }
            .frame(minHeight: 28)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var toggleState = StudioEffectToggleState()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Toggle(title, isOn: Binding(
                    get: { value > 0 },
                    set: { enabled in
                        value = toggleState.amount(enabled: enabled, current: value, defaultValue: defaultValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Enable \(title.lowercased())")
            }
            InspectorSlider("Amount", value: $value, range: range, format: .percent())
        }
        .padding(10)
        .studioEffectCard()
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
    case background, cursor, camera, effects, zoom
    var id: Self { self }
    var title: String {
        switch self {
        case .background: "Background"
        case .cursor: "Cursor"
        case .camera: "Camera"
        case .effects: "Effects"
        case .zoom: "Zoom & Clips"
        }
    }
    var systemImage: String {
        switch self {
        case .background: "photo"
        case .cursor: "cursorarrow"
        case .camera: "web.camera"
        case .effects: "slider.horizontal.3"
        case .zoom: "plus.magnifyingglass"
        }
    }
}
