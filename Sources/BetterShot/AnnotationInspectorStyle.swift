//
//  AnnotationInspectorStyle.swift
//  BetterShot
//
//  Shared design system for the annotation editor inspector. Every section is
//  built from these primitives so the panel reads as one consistent control:
//  a single control height, a single corner radius, one label style, one
//  section-header style, and a consistent spacing rhythm. Inspired by the
//  density and precision of pro creative tools (Sketch).
//

import AppKit
import SwiftUI

// MARK: - Tokens

enum InspectorMetrics {
    /// Horizontal inset applied to every section's content.
    static let horizontalPadding: CGFloat = 12
    /// Vertical padding above/below each section's content.
    static let sectionVerticalPadding: CGFloat = 12
    /// Gap between a section header and its content.
    static let headerSpacing: CGFloat = 10
    /// Gap between stacked rows inside a section.
    static let rowSpacing: CGFloat = 8
    /// Gap between a group sub-label and its content.
    static let groupLabelSpacing: CGFloat = 7

    /// The one true height for every interactive field (menus, steppers,
    /// pickers, segmented controls).
    static let controlHeight: CGFloat = 24
    /// Taller scrubber rows give the embedded label and editable value enough
    /// breathing room without making the inspector feel loose.
    static let sliderHeight: CGFloat = 32
    static let sliderValueWidth: CGFloat = 60
    /// Corner radius for fields and segmented tracks.
    static let fieldRadius: CGFloat = 5
    static let sliderRadius: CGFloat = 8
    /// Shared inner inset for compound controls such as segmented pickers,
    /// tool grids, and placement surfaces.
    static let controlInset: CGFloat = 2
    /// Corner radius for square tiles (swatches, tool cells, wallpapers).
    static let tileRadius: CGFloat = 6

    /// Fixed width for left-aligned row labels so values line up.
    static let labelColumnWidth: CGFloat = 58
}

enum InspectorControlPalette {
    /// The opaque surface every fill below is tuned against. Track and
    /// selection fills sit at 4–10% opacity, so they only read as a control
    /// when something solid is behind them - over a popover's vibrancy they
    /// wash out to nothing. Any presentation hosting these controls has to
    /// paint this itself.
    static func panelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .white
    }

    static func trackFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.04)
    }

    static func selectionFill(for colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.075)
    }

    static var hoverFill: Color { Color.primary.opacity(0.04) }
    static var border: Color { Color.primary.opacity(0.10) }
    static var selectedForeground: Color { Color.primary.opacity(0.92) }
}

// MARK: - Typography

extension Font {
    /// Section title, e.g. "Background". Title-case, quietly prominent.
    static let inspectorSectionHeader = Font.system(size: 11, weight: .semibold)
    /// Field / row label, e.g. "Color".
    static let inspectorLabel = Font.system(size: 11, weight: .regular)
    /// Value text rendered inside or beside a field.
    static let inspectorValue = Font.system(size: 11, weight: .medium)
    /// Numeric readout for sliders/steppers.
    static let inspectorNumeric = Font.system(size: 11, weight: .medium).monospacedDigit()
}

// MARK: - Field chrome

/// The uniform "field" background - a subtly filled, hairline-stroked rounded
/// rectangle at the standard control height. Used by every input affordance so
/// menus, steppers and pickers share one silhouette.
private struct InspectorFieldChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat?
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }

    private var stroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}

extension View {
    /// Applies the standard inspector field chrome.
    func inspectorField(
        height: CGFloat? = InspectorMetrics.controlHeight,
        cornerRadius: CGFloat = InspectorMetrics.fieldRadius
    ) -> some View {
        modifier(InspectorFieldChrome(height: height, cornerRadius: cornerRadius))
    }
}

// MARK: - Section

/// A titled section with consistent padding. An optional trailing accessory
/// (reset, add, info) sits opposite the title, the way Sketch decorates its
/// inspector groups.
struct InspectorSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.headerSpacing) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.inspectorSectionHeader)
                    .foregroundStyle(.primary.opacity(0.85))

                Spacer(minLength: 0)

                accessory()
            }

            content()
        }
        .padding(.horizontal, InspectorMetrics.horizontalPadding)
        .padding(.vertical, InspectorMetrics.sectionVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension InspectorSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

/// A compact accordion section for the inspector's heavier control groups.
/// The title and chevron toggle expansion while header accessories keep their
/// own independent hit targets.
struct InspectorDisclosureSection<Content: View, Accessory: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    @State private var isHeaderHovering = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: toggleExpansion) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.inspectorSectionHeader)
                            .foregroundStyle(.primary.opacity(0.88))

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")

                accessory()

                Button(action: toggleExpansion) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, InspectorMetrics.horizontalPadding)
            .frame(height: 38)
            .background(isHeaderHovering ? Color.primary.opacity(0.025) : .clear)
            .onHover { isHeaderHovering = $0 }

            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    content()
                        .padding(.horizontal, InspectorMetrics.horizontalPadding)
                        .padding(.top, 4)
                        .padding(.bottom, InspectorMetrics.sectionVerticalPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // SwiftUI can paint a moving transition beyond its interpolated
            // layout height. Keep the disclosure body inside its own animated
            // bounds so it never overlaps the header or neighboring sections.
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 0.5)
                .padding(.horizontal, InspectorMetrics.horizontalPadding)
        }
    }

    private func toggleExpansion() {
        withAnimation(accessibilityReduceMotion ? nil : .snappy(duration: 0.18)) {
            isExpanded.toggle()
        }
    }
}

extension InspectorDisclosureSection where Accessory == EmptyView {
    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            isExpanded: isExpanded,
            accessory: { EmptyView() },
            content: content
        )
    }
}

/// A small, restrained "clear" affordance for a section header's accessory
/// slot - an X that reads as an action without competing with the title.
struct InspectorClearButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(isHovering ? Color.primary.opacity(0.10) : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// A muted secondary label introducing a sub-group inside a section
/// (e.g. "Color", "Gradient", "Wallpaper").
struct InspectorGroupLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.inspectorLabel)
            .foregroundStyle(.secondary)
    }
}

/// A label + content row with a fixed-width label column so values align.
struct InspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .frame(width: InspectorMetrics.labelColumnWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Hairline divider between sections, matching the panel inset.
struct InspectorSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.45))
            .frame(height: 0.5)
            .padding(.horizontal, InspectorMetrics.horizontalPadding)
    }
}

// MARK: - Segmented control

/// One unified segmented control used for every segmented picker in the panel.
/// It shares the slider's height, radius, neutral track and value fill so choice
/// controls and numeric controls read as one inspector system.
struct InspectorSegmented<Option: Hashable, Label: View>: View {
    let options: [Option]
    let isSelected: (Option) -> Bool
    let onTap: (Option) -> Void
    @ViewBuilder let label: (Option) -> Label

    var height: CGFloat = InspectorMetrics.sliderHeight
    var equalWidths: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredOption: Option?

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: InspectorMetrics.sliderRadius,
            style: .continuous
        )

        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(InspectorMetrics.controlInset)
        .frame(height: height)
        .background(shape.fill(trackFill))
        .overlay(shape.stroke(InspectorControlPalette.border, lineWidth: 0.5))
        .clipShape(shape)
    }

    private func segment(for option: Option) -> some View {
        let selected = isSelected(option)
        let isHovering = hoveredOption == option
        let segmentRadius = InspectorMetrics.sliderRadius - InspectorMetrics.controlInset

        return Button {
            onTap(option)
        } label: {
            label(option)
                .frame(maxWidth: equalWidths ? .infinity : nil)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, equalWidths ? 0 : 11)
                .contentShape(RoundedRectangle(cornerRadius: segmentRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? InspectorControlPalette.selectedForeground : Color.secondary)
        .background {
            RoundedRectangle(cornerRadius: segmentRadius, style: .continuous)
                .fill(segmentFill(isSelected: selected, isHovering: isHovering))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: segmentRadius, style: .continuous)
                            .stroke(InspectorControlPalette.border, lineWidth: 0.5)
                    }
                }
        }
        .onHover { isHovering in
            if isHovering {
                hoveredOption = option
            } else if hoveredOption == option {
                hoveredOption = nil
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var trackFill: Color {
        InspectorControlPalette.trackFill(for: colorScheme)
    }

    private func segmentFill(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected {
            return InspectorControlPalette.selectionFill(for: colorScheme)
        }
        return isHovering ? InspectorControlPalette.hoverFill : .clear
    }
}

// MARK: - Selectable tile

/// A square (or aspect-ratioed) tile with one consistent selection treatment:
/// a hairline border at rest, an accent ring when selected. Used for color,
/// gradient and wallpaper swatches so every picker tile reads identically.
struct InspectorTile<Content: View>: View {
    var aspectRatio: CGFloat = 1
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    private let cornerRadius = InspectorMetrics.tileRadius

    var body: some View {
        Button(action: action) {
            content()
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .padding(2.5)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius + 2.5, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
