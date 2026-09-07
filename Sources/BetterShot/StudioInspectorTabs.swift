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
