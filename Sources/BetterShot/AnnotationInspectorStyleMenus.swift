//
//  AnnotationInspectorStyleMenus.swift
//  BetterShot
//

import AppKit
import SwiftUI

/// A compact palette shared by annotation, text, and border controls.
/// All presets and the system color-panel action stay visible without scrolling.
struct AnnotationSwatchStrip: View {
    let selectedSwatch: AnnotationSwatch
    let onSelect: (AnnotationSwatch) -> Void

    private static let swatchDiameter: CGFloat = 24

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: InspectorMetrics.rowSpacing), count: 6),
            alignment: .leading,
            spacing: InspectorMetrics.rowSpacing
        ) {
            ForEach(AnnotationSwatch.allCases) { swatch in
                swatchButton(for: swatch)
            }
            customWell
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatchButton(for swatch: AnnotationSwatch) -> some View {
        Button {
            onSelect(swatch)
        } label: {
            swatchCircle(
                fill: AnyShapeStyle(swatch.color),
                isSelected: selectedSwatch == swatch
            )
        }
        .buttonStyle(.plain)
        .help(swatch.title)
        .accessibilityLabel(swatch.title)
        .accessibilityAddTraits(selectedSwatch == swatch ? .isSelected : [])
    }

    private var customWell: some View {
        Button {
            AnnotationColorPanelBridge.shared.present(
                current: selectedSwatch.nsColor
            ) { color in
                onSelect(.custom(from: color))
            }
        } label: {
            swatchCircle(
                fill: isCustomSelected
                    ? AnyShapeStyle(selectedSwatch.color)
                    : AnyShapeStyle(AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                      )),
                isSelected: isCustomSelected
            )
        }
        .buttonStyle(.plain)
        .help("Custom color")
        .accessibilityLabel("Custom color")
        .accessibilityAddTraits(isCustomSelected ? .isSelected : [])
    }

    private func swatchCircle(fill: AnyShapeStyle, isSelected: Bool) -> some View {
        Circle()
            .fill(fill)
            .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .padding(2.5)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Circle().inset(by: -2))
    }

    private var isCustomSelected: Bool {
        !AnnotationSwatch.allCases.contains(selectedSwatch)
    }
}

/// Stroke width as a segmented dot scale, using the same segmented control as
/// every other choice picker in the inspector.
struct AnnotationStrokePicker: View {
    let strokeWidth: CGFloat
    let onSelect: (CGFloat) -> Void

    private static let widths: [CGFloat] = [2, 4, 6, 8, 12]

    var body: some View {
        InspectorSegmented(
            options: Self.widths,
            isSelected: { $0 == strokeWidth },
            onTap: onSelect,
            label: { width in
                Circle()
                    .frame(width: dotDiameter(for: width), height: dotDiameter(for: width))
                    .help("\(Int(width)) px")
                    .accessibilityLabel("\(Int(width)) pixels")
            },
            height: InspectorMetrics.controlHeight
        )
    }

    private func dotDiameter(for width: CGFloat) -> CGFloat {
        min(width + 2, 13)
    }
}

/// Routes the shared `NSColorPanel` to whichever swatch strip opened it last.
/// The panel sends continuous `changeColor` actions while the user scrubs, so
/// annotations update live just like the old popover's embedded picker.
@MainActor
final class AnnotationColorPanelBridge: NSObject {
    static let shared = AnnotationColorPanelBridge()

    private var onChange: ((NSColor) -> Void)?

    func present(current: NSColor, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = current
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
