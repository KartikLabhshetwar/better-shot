//
//  AnnotationTextStyleControls.swift
//  BetterShot
//

import AppKit
import SwiftUI

struct AnnotationTextStyleControls: View {
    @Bindable var model: AnnotationEditorModel
    @State private var fontSizeText = ""
    @FocusState private var isFontSizeFieldFocused: Bool

    var body: some View {
        VStack(spacing: InspectorMetrics.rowSpacing) {
            fontFamilyMenu
                .frame(minWidth: 0, maxWidth: .infinity)

            AnnotationSwatchStrip(selectedSwatch: model.selectedSwatch) { swatch in
                model.setSwatch(swatch)
            }

            HStack(spacing: 6) {
                fontSizeStepper

                Spacer()

                InspectorSegmented(
                    options: TextStyleSegment.allCases,
                    isSelected: { segment in
                        switch segment {
                        case .bold: model.selectedTextIsBold
                        case .italic: model.selectedTextIsItalic
                        case .underline: model.selectedTextIsUnderline
                        }
                    },
                    onTap: { segment in
                        switch segment {
                        case .bold: model.selectedTextIsBold.toggle()
                        case .italic: model.selectedTextIsItalic.toggle()
                        case .underline: model.selectedTextIsUnderline.toggle()
                        }
                    },
                    label: { segment in
                        Text(segment.title)
                            .font(segment.font)
                            .underline(segment == .underline)
                    }
                )
                .frame(width: 90)
            }

            InspectorSegmented(
                options: TextAlignmentSegment.allCases,
                isSelected: { $0 == TextAlignmentSegment(model.selectedTextAlignment) },
                onTap: { model.selectedTextAlignment = $0.nsTextAlignment },
                label: { segment in
                    Image(systemName: segment.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
            )
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: syncFontSizeText)
        .onDisappear(perform: commitFontSizeText)
        .onChange(of: model.selectedTextFontSize) { _, _ in
            guard !isFontSizeFieldFocused else { return }
            syncFontSizeText()
        }
        .onChange(of: model.selectionCount) { _, _ in
            guard !isFontSizeFieldFocused else { return }
            syncFontSizeText()
        }
        .onChange(of: isFontSizeFieldFocused) { _, isFocused in
            if isFocused {
                syncFontSizeText()
            } else {
                commitFontSizeText()
            }
        }
    }

    private var fontFamilyMenu: some View {
        Menu {
            ForEach(AnnoFontFamily.allCases) { family in
                Button {
                    model.selectedTextFontFamily = family
                } label: {
                    if model.selectedTextFontFamily == family {
                        Label(family.title, systemImage: "checkmark")
                    } else {
                        Text(family.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.selectedTextFontFamily.title)
                    .font(.inspectorValue)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .inspectorField()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Font family")
    }

    private var fontSizeStepper: some View {
        HStack(spacing: 0) {
            Button {
                adjustFontSize(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 24, height: InspectorMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Divider().frame(height: 13)

            TextField("", text: $fontSizeText)
                .focused($isFontSizeFieldFocused)
                .onSubmit(commitFontSizeText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.inspectorNumeric)
                .frame(width: 30)

            Divider().frame(height: 13)

            Button {
                adjustFontSize(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 24, height: InspectorMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .inspectorField()
    }

    private func syncFontSizeText() {
        fontSizeText = String(Int(model.selectedTextFontSize.rounded()))
    }

    private func commitFontSizeText() {
        let trimmedText = fontSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let size = Double(trimmedText) else {
            syncFontSizeText()
            return
        }

        let clampedSize = max(size.rounded(), Double(AnnotationTextMetrics.minimumFontSize))
        model.selectedTextFontSize = CGFloat(clampedSize)
        fontSizeText = String(Int(clampedSize))
    }

    private func adjustFontSize(by delta: CGFloat) {
        commitFontSizeText()
        let size = max(model.selectedTextFontSize + delta, AnnotationTextMetrics.minimumFontSize)
        model.selectedTextFontSize = size
        syncFontSizeText()
    }
}

private enum TextStyleSegment: CaseIterable, Hashable {
    case bold
    case italic
    case underline

    var title: String {
        switch self {
        case .bold: "B"
        case .italic: "I"
        case .underline: "U"
        }
    }

    var font: Font {
        switch self {
        case .bold:
            .system(size: 12, weight: .bold)
        case .italic:
            .system(size: 12, weight: .regular, design: .serif).italic()
        case .underline:
            .system(size: 12, weight: .regular)
        }
    }
}

private enum TextAlignmentSegment: CaseIterable, Hashable {
    case left
    case center
    case right
    case justified

    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .center:
            self = .center
        case .right:
            self = .right
        case .justified:
            self = .justified
        default:
            self = .left
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
    }

    var systemImage: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        case .justified: "text.justify.leading"
        }
    }
}
