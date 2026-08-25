import AppKit
import Foundation

/// A text view laid over the canvas while a text shape is being edited.
///
/// The canvas skips drawing the shape while this is up, so what you see is the live text view.
/// Using a real `NSTextView` means selection, arrow keys, IME and system text services all work,
/// rather than reimplementing them against a hand-rolled caret.
///
/// Ported from the drawing-app's `UI/TextEditorOverlay.swift`.
@MainActor
final class AnnoTextEditorOverlay: NSTextView {
    private weak var editor: AnnoEditor?
    private var shapeId: AnnoShapeID?

    /// Which shape this caret belongs to, so the canvas can tell a retarget from a no-op.
    var editedShapeId: AnnoShapeID? { shapeId }

    /// `NSTextView.init(frame:)` is a convenience initializer that builds the text network and then
    /// routes through this designated one, so a subclass has to implement it - otherwise the
    /// runtime traps on an unimplemented initializer.
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    convenience init(editor: AnnoEditor, shapeId: AnnoShapeID) {
        // Build the text network by hand rather than going through `init(frame:)`, which Swift no
        // longer inherits now that the designated initializer above is overridden.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)

        self.init(frame: .zero, textContainer: container)
        self.editor = editor
        self.shapeId = shapeId
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = true
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        // The shape owns wrapping: it measures the text and sets the frame, so the container must
        // not impose a width of its own.
        textContainer?.widthTracksTextView = false
        allowsUndo = false
        focusRingType = .none
        delegate = self
    }

    /// Style and position the overlay to sit exactly where the shape is drawn.
    func sync() {
        guard let editor, let shapeId,
              let shape = editor.document.shape(shapeId),
              let props = shape.textProps else { return }

        let zoom = editor.viewport.scale
        // The overlay lays out in view points, so scale the shape's page-space type up by the
        // camera before styling.
        var viewProps = props
        viewProps.fontSize = Swift.max(1, props.fontSize * zoom)
        viewProps.w = props.w * zoom

        let fontSize = CGFloat(viewProps.fontSize)
        let font = TextMeasure.font(viewProps, opticalSize: props.fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = props.align.nsTextAlignment
        paragraph.minimumLineHeight = TextMeasure.lineHeight(viewProps)
        paragraph.maximumLineHeight = TextMeasure.lineHeight(viewProps)
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: props.swatch.nsColor,
        ]
        if props.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        typingAttributes = attributes
        defaultParagraphStyle = paragraph
        self.font = font
        textColor = props.swatch.nsColor
        alignment = paragraph.alignment
        insertionPointColor = props.swatch.nsColor
        if let storage = textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }

        // The shape's box in view space. The frame origin is the shape's local origin, which is
        // also what `frameRotation` turns about.
        let bounds = editor.document.geometry(shape).bounds
        let origin = editor.pageToScreen(Vec(shape.x, shape.y))
        var width = Swift.max(bounds.w * zoom, Double(fontSize) * 0.6)
        var height = Swift.max(bounds.h * zoom, Double(TextMeasure.lineHeight(viewProps)))

        if props.autoSize, let container = textContainer, let layoutManager {
            // Auto-sizing text must never wrap. Sizing the container from the shape's measured
            // width wraps the moment a keystroke outgrows it - the shape only re-measures *after*
            // the text view has already laid out. Worse, the shape is measured at the page font
            // size while the overlay lays out at `fontSize * zoom`, and those don't scale exactly.
            //
            // So: lay out unconstrained to find the text's natural width, then set the container to
            // exactly that. Nothing can wrap, and alignment still has a real width to work in.
            container.size = CGSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            let natural = ceil(used.width)
            container.size = CGSize(width: natural + 2, height: CGFloat.greatestFiniteMagnitude)
            // Leave room for the caret past the last glyph.
            width = Swift.max(width, Double(natural + fontSize * 0.5))
            height = Swift.max(height, Double(ceil(used.height)))
        } else {
            textContainer?.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }

        frameRotation = 0
        frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        // The canvas is flipped, so a positive rotation reads clockwise on screen - the same
        // direction a positive `shape.rotation` turns the drawn shape.
        frameRotation = shape.rotation * 180 / .pi
    }

    func loadText() {
        guard let editor, let shapeId,
              let props = editor.document.shape(shapeId)?.textProps else { return }
        string = props.text
        sync()
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    }

    /// Draw the caret's text the way the canvas draws committed text: plain antialiasing, no font
    /// smoothing. AppKit stem-darkens light text on a dark background, which made type look
    /// noticeably heavier while editing than it did the moment it committed - and heavier than the
    /// exported PNG, which is the side that has to be right.
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        super.draw(dirtyRect)
    }

    override func cancelOperation(_ sender: Any?) {
        editor?.stopEditingText()
    }
}

extension AnnoTextEditorOverlay: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let shapeId else { return }
        editor?.updateEditingText(shapeId, to: string)
        // The shape may have grown or moved to keep its alignment anchor; follow it.
        sync()
    }
}
