import AppKit
import SwiftUI

struct AnnotationItemView: View {
    let item: AnnotationItem
    let image: NSImage
    let originalImageSize: CGSize
    let imageFrame: CGRect
    let isSelected: Bool
    let showsResizeHandles: Bool
    let isEditingText: Bool
    let allowsRedactionPreviewCaching: Bool
    let text: Binding<String>
    let onCommitText: () -> Void
    let onTextSizeChange: (CGSize) -> Void

    private var selectionOutset: CGFloat {
        item.tool == .text ? 0 : 5
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if item.tool.isRedactionTool {
                RedactionPreview(
                    image: image,
                    item: item,
                    originalImageSize: originalImageSize,
                    imageFrame: imageFrame,
                    viewBounds: viewBounds,
                    allowsCaching: allowsRedactionPreviewCaching
                )
            } else if item.tool == .spotlight {
                SpotlightPreview(
                    item: item,
                    imageFrame: imageFrame,
                    viewBounds: viewBounds
                )
            } else if item.tool.isFilledShape {
                itemPath
                    .fill(fillStyle)
            } else if item.tool == .numberedCircle {
                NumberedCircleAnnotationView(item: item, viewBounds: viewBounds)
            } else if item.tool == .text {
                AnnotationTextItemView(
                    item: item,
                    text: text,
                    viewBounds: viewBounds,
                    imageFrameHeight: imageFrame.height,
                    isEditing: isEditingText,
                    onCommit: onCommitText,
                    onSizeChange: onTextSizeChange
                )
            } else {
                itemPath
                    .stroke(item.swatch.color, style: StrokeStyle(lineWidth: item.strokeWidth, lineCap: .round, lineJoin: .round))
            }

            if let arrowHeadPath {
                arrowHeadPath
                    .stroke(item.swatch.color, style: StrokeStyle(lineWidth: item.strokeWidth, lineCap: .round, lineJoin: .round))
            }

            if isSelected {
                selectionOverlay
            }
        }
        .allowsHitTesting(item.tool == .text && isEditingText)
    }

    private var itemPath: Path {
        let rect = viewRect(item.bounds)

        switch item.tool {
        case .select:
            return Path()

        case .rectangle:
            return Path(rect)

        case .filledRectangle:
            return Path(
                roundedRect: rect,
                cornerRadius: AnnotationFilledRectangleMetrics.cornerRadius(for: rect)
            )

        case .pixelate, .blur, .spotlight:
            return Path(rect)

        case .numberedCircle:
            return Path(ellipseIn: rect)

        case .text:
            return Path()

        case .ellipse:
            return Path(ellipseIn: rect)

        case .line:
            var path = Path()
            if let start = endpointViewPoints.first,
               let end = endpointViewPoints.last {
                path.move(to: start)
                path.addLine(to: end)
            }
            return path

        case .freehand:
            return freehandPath(points: item.points.map(viewPoint))

        case .arrow:
            var path = Path()
            guard let start = endpointViewPoints.first,
                  let geometry = arrowGeometry else {
                return path
            }

            path.move(to: start)
            path.addQuadCurve(to: geometry.tip, control: geometry.shaftControl)
            return path
        }
    }

    private var fillStyle: Color {
        item.tool.isFilledShape ? item.swatch.color : .clear
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if !showsResizeHandles {
            SelectionOutlineFrame()
                .frame(
                    width: max(viewBounds.width + selectionOutset * 2, 18),
                    height: max(viewBounds.height + selectionOutset * 2, 18)
                )
                .position(x: viewBounds.midX, y: viewBounds.midY)
        } else if item.tool.usesEndpoints {
            ForEach(endpointViewPoints.indices, id: \.self) { index in
                SelectionHandle()
                    .position(endpointViewPoints[index])
            }

            if let controlViewPoint {
                CurveControlHandle()
                    .position(controlViewPoint)
            }
        } else if item.tool == .text {
            TextSelectionFrame()
                .frame(
                    width: max(viewBounds.width, 18),
                    height: max(viewBounds.height, 18)
                )
                .position(x: viewBounds.midX, y: viewBounds.midY)
        } else {
            SelectionFrame()
                .frame(
                    width: max(viewBounds.width + selectionOutset * 2, 18),
                    height: max(viewBounds.height + selectionOutset * 2, 18)
                )
                .position(x: viewBounds.midX, y: viewBounds.midY)
        }
    }

    private var arrowHeadPath: Path? {
        guard let geometry = arrowGeometry else {
            return nil
        }

        var path = Path()
        path.move(to: geometry.firstWing)
        path.addLine(to: geometry.tip)
        path.addLine(to: geometry.secondWing)
        return path
    }

    private var arrowGeometry: AnnotationArrowGeometry? {
        guard item.tool == .arrow,
              let start = endpointViewPoints.first,
              let control = controlViewPoint,
              let end = endpointViewPoints.last else {
            return nil
        }

        return AnnotationArrowGeometry(start: start, control: control, end: end, lineWidth: item.strokeWidth)
    }

    private var endpointViewPoints: [CGPoint] {
        guard item.points.count >= 2,
              let first = item.points.first,
              let last = item.points.last else {
            return []
        }

        return [viewPoint(first), viewPoint(last)]
    }

    private var controlViewPoint: CGPoint? {
        guard let curveHandle = item.arrowCurveHandle else { return nil }
        return viewPoint(curveHandle)
    }

    private var viewBounds: CGRect {
        viewRect(item.bounds)
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + rect.minX * imageFrame.width,
            y: imageFrame.minY + rect.minY * imageFrame.height,
            width: rect.width * imageFrame.width,
            height: rect.height * imageFrame.height
        )
    }

    private func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageFrame.minX + point.x * imageFrame.width,
            y: imageFrame.minY + point.y * imageFrame.height
        )
    }

    private func freehandPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)
        guard points.count > 1 else { return path }

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            path.addQuadCurve(to: midpoint(previous, current), control: previous)
        }

        path.addLine(to: points[points.count - 1])
        return path
    }

    private func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }
}

private struct NumberedCircleAnnotationView: View {
    let item: AnnotationItem
    let viewBounds: CGRect

    var body: some View {
        let diameter = min(max(viewBounds.width, 1), max(viewBounds.height, 1))

        ZStack {
            Circle()
                .fill(item.swatch.color)
                .overlay {
                    Circle()
                        .stroke(
                            item.swatch.numberedCircleOutlineColor,
                            lineWidth: AnnotationNumberedCircleMetrics.outlineWidth(for: diameter)
                        )
                }

            Text(item.text)
                .font(.system(
                    size: AnnotationNumberedCircleMetrics.fontSize(for: diameter, text: item.text),
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(item.swatch.numberedCircleTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .monospacedDigit()
        }
        .frame(width: max(viewBounds.width, 1), height: max(viewBounds.height, 1))
        .position(x: viewBounds.midX, y: viewBounds.midY)
    }
}

private struct AnnotationTextItemView: View {
    let item: AnnotationItem
    let text: Binding<String>
    let viewBounds: CGRect
    let imageFrameHeight: CGFloat
    let isEditing: Bool
    let onCommit: () -> Void
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        AnnotationTextBoxView(
            text: text,
            font: item.resolvedFont(size: fontSize),
            textColor: item.swatch.nsColor,
            shadow: AnnotationTextMetrics.textShadow,
            isUnderline: item.isUnderline,
            alignment: item.textAlignment,
            isEditing: isEditing,
            onCommit: onCommit,
            onSizeChange: onSizeChange
        )
        .frame(width: max(viewBounds.width, 1), height: max(viewBounds.height, 1))
        .position(x: viewBounds.midX, y: viewBounds.midY)
    }

    private var fontSize: CGFloat {
        AnnotationTextMetrics.viewFontSize(lineHeight: item.textLineHeight, imageFrameHeight: imageFrameHeight)
    }
}

private struct AnnotationTextBoxView: NSViewRepresentable {
    @Binding var text: String

    let font: NSFont
    let textColor: NSColor
    let shadow: NSShadow
    let isUnderline: Bool
    let alignment: NSTextAlignment
    let isEditing: Bool
    let onCommit: () -> Void
    let onSizeChange: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onSizeChange: onSizeChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = isEditing
        textView.isSelectable = isEditing
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = CGSize(
            width: 1,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.lineBreakMode = .byClipping
        textView.autoresizingMask = [.width, .height]
        textView.insertionPointColor = NSColor.systemBlue
        textView.backgroundColor = .clear
        textView.string = text
        applyStyle(to: textView)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.autoresizesSubviews = true

        context.coordinator.textView = textView

        if isEditing {
            DispatchQueue.main.async {
                self.updateTextViewFrame(textView, in: scrollView)
                textView.window?.makeFirstResponder(textView)
                self.reportSize(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        context.coordinator.onSizeChange = onSizeChange

        textView.isEditable = isEditing
        textView.isSelectable = isEditing
        updateTextViewFrame(textView, in: scrollView)

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        applyStyle(to: textView)

        if isEditing && textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        } else if !isEditing && textView.window?.firstResponder === textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(nil)
            }
        }

        DispatchQueue.main.async {
            self.reportSize(textView)
        }
    }

    private func reportSize(_ textView: NSTextView) {
        onSizeChange(Self.measuredTextSize(for: textView))
    }

    private func updateTextViewFrame(_ textView: NSTextView, in scrollView: NSScrollView) {
        let size = CGSize(
            width: max(scrollView.bounds.width, 1),
            height: max(scrollView.bounds.height, 1)
        )
        if textView.frame.size != size {
            textView.frame = CGRect(origin: .zero, size: size)
        }
        textView.textContainer?.containerSize = CGSize(
            width: size.width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    static func measuredTextSize(for textView: NSTextView) -> CGSize {
        let font = textView.font ?? NSFont.systemFont(ofSize: AnnotationTextMetrics.minimumFontSize)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let lineCount = CGFloat(AnnotationTextMetrics.lineCount(for: textView.string))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byClipping

        var attributes = textView.typingAttributes
        attributes[.font] = font
        attributes[.paragraphStyle] = paragraphStyle

        let measuredString = textView.string.isEmpty ? " " : textView.string
        let rect = NSAttributedString(string: measuredString, attributes: attributes).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(
            width: ceil(rect.width) + 2,
            height: max(ceil(rect.height), lineHeight * lineCount)
        )
    }

    private func applyStyle(to textView: NSTextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byClipping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
        if isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        let fontChanged = textView.font != font
        let colorChanged = textView.textColor != textColor
        let alignmentChanged = textView.alignment != alignment

        textView.font = font
        textView.textColor = textColor
        textView.alignment = alignment
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = attributes
        textView.textContainer?.lineBreakMode = .byClipping

        guard !textView.string.isEmpty, fontChanged || colorChanged || alignmentChanged else { return }

        let selectedRanges = textView.selectedRanges
        textView.textStorage?.setAttributes(
            attributes,
            range: NSRange(location: 0, length: (textView.string as NSString).length)
        )
        textView.selectedRanges = selectedRanges
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onCommit: () -> Void
        var onSizeChange: (CGSize) -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, onCommit: @escaping () -> Void, onSizeChange: @escaping (CGSize) -> Void) {
            self.text = text
            self.onCommit = onCommit
            self.onSizeChange = onSizeChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            reportSize(textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            onCommit()
        }

        private func reportSize(_ textView: NSTextView) {
            onSizeChange(AnnotationTextBoxView.measuredTextSize(for: textView))
        }
    }
}

extension NSCursor {
    nonisolated(unsafe) static let annotationPlus: NSCursor = {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outline = NSBezierPath()
        outline.move(to: CGPoint(x: center.x - 6, y: center.y))
        outline.line(to: CGPoint(x: center.x + 6, y: center.y))
        outline.move(to: CGPoint(x: center.x, y: center.y - 6))
        outline.line(to: CGPoint(x: center.x, y: center.y + 6))
        NSColor.white.setStroke()
        outline.lineWidth = 5
        outline.lineCapStyle = .round
        outline.stroke()

        let plus = NSBezierPath()
        plus.move(to: CGPoint(x: center.x - 6, y: center.y))
        plus.line(to: CGPoint(x: center.x + 6, y: center.y))
        plus.move(to: CGPoint(x: center.x, y: center.y - 6))
        plus.line(to: CGPoint(x: center.x, y: center.y + 6))
        NSColor.black.setStroke()
        plus.lineWidth = 2
        plus.lineCapStyle = .round
        plus.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }()
}

private struct RedactionPreview: View {
    let image: NSImage
    let item: AnnotationItem
    let originalImageSize: CGSize
    let imageFrame: CGRect
    let viewBounds: CGRect
    let allowsCaching: Bool

    var body: some View {
        if let redactedImage = RedactionImageProcessor.previewImage(
            source: image,
            tool: item.tool,
            density: item.redactionDensity,
            normalizedBounds: item.bounds,
            originalImageSize: originalImageSize,
            allowsCaching: allowsCaching
        ) {
            Image(nsImage: redactedImage)
                .interpolation(item.tool == .pixelate ? .none : .medium)
                .resizable()
                .frame(width: max(viewBounds.width, 1), height: max(viewBounds.height, 1))
                .position(x: viewBounds.midX, y: viewBounds.midY)
        }
    }
}

private struct SelectionFrame: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .stroke(AnnotationSelectionStyle.color, lineWidth: 2)

                SelectionHandle().position(x: 0, y: 0)
                SelectionHandle().position(x: proxy.size.width, y: 0)
                SelectionHandle().position(x: 0, y: proxy.size.height)
                SelectionHandle().position(x: proxy.size.width, y: proxy.size.height)
            }
        }
    }
}

private struct TextSelectionFrame: View {
    var body: some View {
        Rectangle()
            .stroke(AnnotationSelectionStyle.color, lineWidth: 1.5)
    }
}

private struct SelectionOutlineFrame: View {
    var body: some View {
        Rectangle()
            .stroke(AnnotationSelectionStyle.color, lineWidth: 1.5)
    }
}

private struct SelectionHandle: View {
    var body: some View {
        Circle()
            .fill(AnnotationSelectionStyle.color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
    }
}

private struct CurveControlHandle: View {
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(AnnotationSelectionStyle.color, lineWidth: 2))
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
    }
}

private enum AnnotationSelectionStyle {
    static let color = Color.accentColor.opacity(0.5)
}

private struct SpotlightPreview: View {
    let item: AnnotationItem
    let imageFrame: CGRect
    let viewBounds: CGRect

    var body: some View {
        Canvas { context, size in
            let overlayRect = CGRect(origin: .zero, size: size)
            var overlayPath = Path(overlayRect)
            let cutoutRect = CGRect(
                x: viewBounds.minX - imageFrame.minX,
                y: viewBounds.minY - imageFrame.minY,
                width: viewBounds.width,
                height: viewBounds.height
            )
            overlayPath.addRect(cutoutRect)
            context.fill(overlayPath, with: .color(.black.opacity(Double(item.redactionDensity))), style: FillStyle(eoFill: true))
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .position(x: imageFrame.midX, y: imageFrame.midY)
        .allowsHitTesting(false)
    }
}
