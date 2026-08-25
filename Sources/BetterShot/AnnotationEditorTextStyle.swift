//
//  AnnotationEditorTextStyle.swift
//  BetterShot
//

import AppKit
import CoreGraphics

/// The inspector's text controls. Each setter updates the style new text will use *and* whatever
/// text is selected; the engine re-measures the box from the same layout the glyphs come from, so
/// a font change reflows it without a round trip through a text view.
extension AnnotationEditorModel {
    private var selectedTextShape: AnnoShape? {
        guard engine.selectedIds.count == 1, let shape = engine.selectedShapes.first, shape.isText else {
            return nil
        }
        return shape
    }

    var isTextStyleAvailable: Bool {
        if !engine.selectedIds.isEmpty { return selectedTextShape != nil }
        return selectedTool == .text
    }

    var selectedTextFontSize: CGFloat {
        get { selectedTextShape?.textProps.map { CGFloat($0.fontSize) } ?? textFontSize }
        set { setTextFontSize(newValue) }
    }

    var selectedTextFontFamily: AnnoFontFamily {
        get { selectedTextShape?.textProps?.fontFamily ?? textFontFamily }
        set { setTextFontFamily(newValue) }
    }

    var selectedTextIsBold: Bool {
        get { selectedTextShape?.textProps?.isBold ?? textIsBold }
        set { setTextBold(newValue) }
    }

    var selectedTextIsItalic: Bool {
        get { selectedTextShape?.textProps?.isItalic ?? textIsItalic }
        set { setTextItalic(newValue) }
    }

    var selectedTextIsUnderline: Bool {
        get { selectedTextShape?.textProps?.isUnderline ?? textIsUnderline }
        set { setTextUnderline(newValue) }
    }

    var selectedTextAlignment: NSTextAlignment {
        get { selectedTextShape?.textProps?.align.nsTextAlignment ?? textAlignment }
        set { setTextAlignment(newValue) }
    }

    func setTextFontSize(_ pointSize: CGFloat) {
        let clamped = max(pointSize, 4)
        textFontSize = clamped
        engine.currentTextFontSize = Double(clamped)
        saveAnnotationPreset()
        updateSelectedText { $0.fontSize = Double(clamped) }
    }

    func setTextFontFamily(_ family: AnnoFontFamily) {
        textFontFamily = family
        engine.currentFontFamily = family
        saveAnnotationPreset()
        updateSelectedText { $0.fontFamily = family }
    }

    func setTextBold(_ bold: Bool) {
        textIsBold = bold
        engine.currentTextIsBold = bold
        saveAnnotationPreset()
        updateSelectedText { $0.isBold = bold }
    }

    func setTextItalic(_ italic: Bool) {
        textIsItalic = italic
        engine.currentTextIsItalic = italic
        saveAnnotationPreset()
        updateSelectedText { $0.isItalic = italic }
    }

    func setTextUnderline(_ underline: Bool) {
        textIsUnderline = underline
        engine.currentTextIsUnderline = underline
        saveAnnotationPreset()
        updateSelectedText { $0.isUnderline = underline }
    }

    func setTextAlignment(_ alignment: NSTextAlignment) {
        textAlignment = alignment
        engine.currentTextAlign = TextAlign(alignment)
        saveAnnotationPreset()
        updateSelectedText { $0.align = TextAlign(alignment) }
    }

    private func updateSelectedText(_ mutate: (inout TextProps) -> Void) {
        guard selectedTextShape != nil else { return }
        engine.applyStyleToSelection { shape in
            guard case var .text(props) = shape.kind else { return }
            mutate(&props)
            shape.kind = .text(props)
        }
    }
}
