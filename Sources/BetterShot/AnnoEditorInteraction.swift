import AppKit
import Foundation

/// The pointer state machine: which interaction a press starts, how a drag updates it, and what a
/// release commits. Ported from the drawing-app's `Editor/EditorInteraction.swift`.
extension AnnoEditor {
    // MARK: - Down

    func pointerDown(_ pointer: PointerInfo) {
        // A press anywhere commits whatever is being typed, unless it lands on that same shape.
        if let editingId = editingTextId, hitShape(at: pointer.pagePoint)?.id != editingId {
            stopEditingText()
        }

        switch tool {
        case .select:
            beginSelectInteraction(pointer)
        case .freehand:
            beginDrawing(pointer)
        case .text:
            // Clicking existing text edits it; clicking empty canvas starts a new one.
            if let shape = hitShape(at: pointer.pagePoint), shape.isText {
                startEditingText(shape.id)
            } else {
                createText(at: pointer.pagePoint)
            }
        case .rectangle, .filledRectangle, .ellipse, .highlight, .blur, .pixelate:
            beginBoxShape(pointer)
        case .numberedCircle:
            createNumberedCircle(at: pointer.pagePoint)
        case .line, .arrow:
            beginArrow(pointer)
        }
        notifyChanged()
    }

    private func beginSelectInteraction(_ pointer: PointerInfo) {
        // A selection handle takes priority over the shapes under it.
        if let handle = handle(at: pointer.screenPoint), let bounds = selectionBounds {
            switch handle {
            case .arrowStart, .arrowMiddle, .arrowEnd:
                guard let shape = selectedShapes.first else { return }
                markUndo()
                setInteraction(.draggingArrowHandle(id: shape.id, handle: handle))
            case .rotate:
                markUndo()
                let center = bounds.pageCenter
                setInteraction(.rotating(
                    center: center,
                    startAngle: Vec.angle(center, pointer.pagePoint),
                    initial: document.snapshot()
                ))
            default:
                markUndo()
                setInteraction(.resizing(handle: handle, bounds: bounds, initial: document.snapshot()))
            }
            return
        }

        if let shape = hitShape(at: pointer.pagePoint) {
            if pointer.shift {
                if selectedIds.contains(shape.id) {
                    selectedIds.remove(shape.id)
                } else {
                    selectedIds.insert(shape.id)
                }
            } else if !selectedIds.contains(shape.id) {
                selectedIds = [shape.id]
            }
            guard !selectedIds.isEmpty else { return }
            markUndo()
            setInteraction(.translating(origin: pointer.pagePoint, initial: initialPositions()))
            return
        }

        // Nothing under the pointer - but the selection's own bounds act as a drag handle, so a
        // hollow shape can be moved from its empty middle. Ported from
        // `isPointInRotatedSelectionBounds`, which tests the *rotated* bounds as a polygon.
        if canDragSelectionBackground,
           let bounds = selectionBounds,
           pointInPolygon(pointer.pagePoint, bounds.pageCorners) {
            markUndo()
            setInteraction(.translating(origin: pointer.pagePoint, initial: initialPositions()))
            return
        }

        if !pointer.shift { selectedIds.removeAll() }
        setInteraction(.brushing(origin: pointer.pagePoint))
        setBrush(Box(pointer.pagePoint.x, pointer.pagePoint.y, 0, 0))
    }

    private func initialPositions() -> [AnnoShapeID: Vec] {
        var initial: [AnnoShapeID: Vec] = [:]
        for id in selectedIds {
            if let shape = document.shape(id) { initial[id] = Vec(shape.x, shape.y) }
        }
        return initial
    }

    /// Whether the inside of the selection box can be dragged. Arrows and lines opt out, because
    /// their bounding box is mostly empty space and dragging from it would feel wrong.
    private var canDragSelectionBackground: Bool {
        if selectedIds.isEmpty { return false }
        if selectedIds.count > 1 { return true }
        guard let shape = selectedShapes.first else { return false }
        return !shape.isArrow
    }

    // MARK: - Creation

    private func beginDrawing(_ pointer: PointerInfo) {
        markUndo()
        var props = DrawProps()
        props.swatch = currentSwatch
        props.strokeWidth = pageStrokeWidth(currentStrokeWidth)
        props.isPen = pointer.isPen
        props.points = [Vec(0, 0, pointer.isPen ? pointer.pressure : 0.5)]
        let shape = AnnoShape(x: pointer.pagePoint.x, y: pointer.pagePoint.y, kind: .draw(props))
        document.add(shape)
        setInteraction(.drawing(id: shape.id, origin: pointer.pagePoint))
    }

    /// Rectangles, ellipses, redactions and the spotlight highlight all create by dragging a box.
    private func beginBoxShape(_ pointer: PointerInfo) {
        markUndo()
        let kind: AnnoShapeKind
        switch tool {
        case .rectangle, .filledRectangle, .ellipse:
            var props = GeoProps()
            props.geo = tool == .ellipse ? .ellipse : .rectangle
            props.fill = tool == .filledRectangle ? .solid : .none
            props.swatch = currentSwatch
            props.strokeWidth = pageStrokeWidth(currentStrokeWidth)
            props.w = 1
            props.h = 1
            kind = .geo(props)
        case .highlight:
            kind = .highlight(HighlightProps(w: 1, h: 1))
        default:
            var props = RedactionProps()
            props.kind = tool == .blur ? .blur : .pixelate
            props.density = currentRedactionDensity
            props.w = 1
            props.h = 1
            kind = .redaction(props)
        }

        let shape = AnnoShape(x: pointer.pagePoint.x, y: pointer.pagePoint.y, kind: kind)
        document.add(shape)
        setInteraction(.creatingGeo(id: shape.id, origin: pointer.pagePoint))
    }

    private func beginArrow(_ pointer: PointerInfo) {
        markUndo()
        var props = ArrowProps()
        props.swatch = currentSwatch
        props.strokeWidth = pageStrokeWidth(currentStrokeWidth)
        props.arrowheadStart = tool == .line ? .none : currentArrowheadStart
        props.arrowheadEnd = tool == .line ? .none : currentArrowheadEnd
        props.start = Vec(0, 0)
        props.end = Vec(0, 0)
        let shape = AnnoShape(x: pointer.pagePoint.x, y: pointer.pagePoint.y, kind: .arrow(props))
        document.add(shape)
        // If the arrow starts on a shape, bind its start to that shape right away.
        bindTerminal(arrowId: shape.id, terminal: .start, at: pointer.pagePoint, precise: pointer.alt)
        setInteraction(.creatingArrow(id: shape.id))
    }

    /// A numbered callout is placed with a click rather than dragged, and auto-numbers itself.
    func createNumberedCircle(at pagePoint: Vec) {
        markUndo()
        var props = NumberedProps()
        props.swatch = currentSwatch
        props.value = nextNumberedValue
        props.diameter = Swift.max(24, Double(Swift.max(viewport.imageSize.width, viewport.imageSize.height)) * 0.039)
        let shape = AnnoShape(
            x: pagePoint.x - props.diameter / 2,
            y: pagePoint.y - props.diameter / 2,
            kind: .numbered(props)
        )
        document.add(shape)
        selectedIds = [shape.id]
        setInteraction(.idle)
    }

    var nextNumberedValue: Int {
        (document.shapes.compactMap { $0.numberedProps?.value }.max() ?? 0) + 1
    }

    // MARK: - Move

    func pointerMove(_ pointer: PointerInfo) {
        switch interaction {
        case .idle:
            return
        case let .drawing(id, origin):
            appendDrawPoint(id: id, origin: origin, pointer: pointer)
        case let .creatingGeo(id, origin):
            resizeBoxWhileCreating(id: id, origin: origin, pointer: pointer)
        case let .creatingArrow(id):
            updateArrowEnd(id: id, pointer: pointer)
        case let .brushing(origin):
            setBrush(Box.fromPoints([origin, pointer.pagePoint]))
        case let .translating(origin, initial):
            translate(origin: origin, initial: initial, pointer: pointer)
        case let .resizing(handle, bounds, initial):
            resize(handle: handle, bounds: bounds, initial: initial, pointer: pointer)
        case let .rotating(center, startAngle, initial):
            rotate(center: center, startAngle: startAngle, initial: initial, pointer: pointer)
        case let .draggingArrowHandle(id, handle):
            dragArrowHandle(id: id, handle: handle, pointer: pointer)
        }
        notifyChanged()
    }

    // MARK: - Up

    func pointerUp(_ pointer: PointerInfo) {
        switch interaction {
        case let .drawing(id, _):
            document.update(id) { shape in
                if case var .draw(props) = shape.kind {
                    props.isComplete = true
                    // A stroke that returns near its own start closes, so it can be filled.
                    if props.points.count > 3,
                       Vec.distMin(props.points[0], props.points[props.points.count - 1], props.strokeWidth * 2) {
                        props.isClosed = true
                    }
                    shape.kind = .draw(props)
                }
            }
            normalizeDrawOrigin(id)
            if let shape = document.shape(id), (shape.drawProps?.points.count ?? 0) < 2 {
                document.delete([id])
            }

        case let .creatingGeo(id, _):
            // A click without a drag gets a sensibly sized shape rather than a degenerate one.
            if let shape = document.shape(id), let size = boxSize(of: shape), size.width <= 2, size.height <= 2 {
                let fallback = Swift.max(48, Double(Swift.max(viewport.imageSize.width, viewport.imageSize.height)) * 0.08)
                setBoxSize(id, width: fallback, height: fallback)
            }
            selectedIds = [id]
            tool = .select

        case let .creatingArrow(id):
            if let shape = document.shape(id), let props = shape.arrowProps,
               Vec.distMin(props.start, props.end, 4) {
                // Too short to be an arrow.
                document.delete([id])
            } else {
                selectedIds = [id]
                tool = .select
            }

        case let .brushing(origin):
            let box = Box.fromPoints([origin, pointer.pagePoint])
            let hits = shapes(in: box).map { $0.id }
            if pointer.shift {
                selectedIds.formUnion(hits)
            } else {
                selectedIds = Set(hits)
            }

        default:
            break
        }

        setInteraction(.idle)
        setBrush(nil)
        setHintedBinding(nil)
        notifyChanged()
    }

    // MARK: - Drawing

    private func appendDrawPoint(id: AnnoShapeID, origin: Vec, pointer: PointerInfo) {
        document.update(id) { shape in
            guard case var .draw(props) = shape.kind else { return }
            let local = Vec(
                pointer.pagePoint.x - origin.x,
                pointer.pagePoint.y - origin.y,
                pointer.isPen ? pointer.pressure : 0.5
            )
            // Skip points that land on top of the previous one; they add nothing and cost a full
            // re-run of the stroke pipeline.
            if let last = props.points.last, Vec.distMin(last, local, 0.5) { return }
            props.points.append(local)
            shape.kind = .draw(props)
        }
    }

    /// Move a draw shape's origin to its first point's page position, so its local points start at
    /// (0, 0) and its bounds behave.
    private func normalizeDrawOrigin(_ id: AnnoShapeID) {
        document.update(id) { shape in
            guard case var .draw(props) = shape.kind, let first = props.points.first else { return }
            guard first.x != 0 || first.y != 0 else { return }
            let dx = first.x
            let dy = first.y
            props.points = props.points.map { Vec($0.x - dx, $0.y - dy, $0.z) }
            shape.x += dx
            shape.y += dy
            shape.kind = .draw(props)
        }
    }

    // MARK: - Box creation

    private func boxSize(of shape: AnnoShape) -> CGSize? {
        switch shape.kind {
        case let .geo(p): CGSize(width: p.w, height: p.h)
        case let .redaction(p): CGSize(width: p.w, height: p.h)
        case let .highlight(p): CGSize(width: p.w, height: p.h)
        default: nil
        }
    }

    private func setBoxSize(_ id: AnnoShapeID, width: Double, height: Double) {
        document.update(id) { shape in
            switch shape.kind {
            case var .geo(p):
                p.w = Swift.max(1, width)
                p.h = Swift.max(1, height)
                shape.kind = .geo(p)
            case var .redaction(p):
                p.w = Swift.max(1, width)
                p.h = Swift.max(1, height)
                shape.kind = .redaction(p)
            case var .highlight(p):
                p.w = Swift.max(1, width)
                p.h = Swift.max(1, height)
                shape.kind = .highlight(p)
            default:
                break
            }
        }
    }

    private func resizeBoxWhileCreating(id: AnnoShapeID, origin: Vec, pointer: PointerInfo) {
        var minX = Swift.min(origin.x, pointer.pagePoint.x)
        var minY = Swift.min(origin.y, pointer.pagePoint.y)
        var w = abs(pointer.pagePoint.x - origin.x)
        var h = abs(pointer.pagePoint.y - origin.y)

        if pointer.shift {
            // Constrain to a square, growing away from the origin corner.
            let side = Swift.max(w, h)
            minX = pointer.pagePoint.x < origin.x ? origin.x - side : origin.x
            minY = pointer.pagePoint.y < origin.y ? origin.y - side : origin.y
            w = side
            h = side
        }

        document.update(id) { shape in
            shape.x = minX
            shape.y = minY
        }
        setBoxSize(id, width: w, height: h)
    }

    // MARK: - Arrow creation

    private func updateArrowEnd(id: AnnoShapeID, pointer: PointerInfo) {
        guard let shape = document.shape(id) else { return }
        var local = document.pointInShapeSpace(shape, pointer.pagePoint)
        if pointer.shift, let props = shape.arrowProps {
            local = axisSnapped(from: props.start, to: local)
        }
        document.update(id) { shape in
            guard case var .arrow(props) = shape.kind else { return }
            props.end = local
            shape.kind = .arrow(props)
        }
        bindTerminal(arrowId: id, terminal: .end, at: pointer.pagePoint, precise: pointer.alt)
    }

    /// Snap to the nearest 15° from the anchor, the way holding shift on a line should behave.
    private func axisSnapped(from anchor: Vec, to point: Vec) -> Vec {
        let delta = Vec.sub(point, anchor)
        guard delta.len > 0 else { return point }
        let step = PI / 12
        let angle = (atan2(delta.y, delta.x) / step).rounded() * step
        return Vec.add(anchor, Vec.fromAngle(angle, delta.len))
    }

    /// Bind an arrow terminal to whatever shape is under the pointer, or clear the binding.
    private func bindTerminal(arrowId: AnnoShapeID, terminal: ArrowTerminal, at pagePoint: Vec, precise: Bool) {
        // Arrows don't bind to arrows, to themselves, or to the tools that aren't really objects.
        let target = document.shapes.reversed().first { shape in
            guard shape.id != arrowId, !shape.isArrow, !shape.isHighlight, !shape.isRedaction else { return false }
            let local = document.pointInShapeSpace(shape, pagePoint)
            return document.geometry(shape).hitTestPoint(
                local,
                margin: Swift.max(4, pageDistance(forScreen: 8)),
                hitInside: true
            )
        }

        guard let target else {
            document.removeBinding(arrowId: arrowId, terminal: terminal)
            setHintedBinding(nil)
            return
        }

        let localPoint = document.pointInShapeSpace(target, pagePoint)
        let bounds = document.geometry(target).bounds
        let normalizedAnchor = Vec(
            bounds.w == 0 ? 0.5 : (localPoint.x - bounds.x) / bounds.w,
            bounds.h == 0 ? 0.5 : (localPoint.y - bounds.y) / bounds.h
        )

        document.setBinding(ArrowBinding(
            arrowId: arrowId,
            toId: target.id,
            terminal: terminal,
            normalizedAnchor: normalizedAnchor,
            // Holding alt pins the arrow to the exact point rather than the shape's center.
            isPrecise: precise,
            isExact: false
        ))
        setHintedBinding(target.id)
    }

    // MARK: - Translate

    private func translate(origin: Vec, initial: [AnnoShapeID: Vec], pointer: PointerInfo) {
        var dx = pointer.pagePoint.x - origin.x
        var dy = pointer.pagePoint.y - origin.y
        if pointer.shift {
            // Lock to whichever axis has moved further.
            if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
        }
        for (id, start) in initial {
            document.update(id) { shape in
                shape.x = start.x + dx
                shape.y = start.y + dy
            }
        }
    }

    // MARK: - Resize

    /// Scale the selection about the handle's opposite corner. Work happens in the selection's own
    /// space, so a rotated single shape resizes along its own axes.
    private func resize(
        handle: AnnoSelectionHandle,
        bounds: AnnoSelectionBounds,
        initial: AnnoDocument.Snapshot,
        pointer: PointerInfo
    ) {
        guard let anchorNormalized = handle.anchor else { return }
        document.restore(initial)

        let pointerInSelection = bounds.transform.inverse.applyToPoint(pointer.pagePoint)
        let anchor = Vec(
            bounds.box.x + bounds.box.w * anchorNormalized.x,
            bounds.box.y + bounds.box.h * anchorNormalized.y
        )

        var scaleX = 1.0
        var scaleY = 1.0
        if handle.scalesX, bounds.box.w != 0 {
            let origin = bounds.box.x + bounds.box.w * (anchorNormalized.x > 0.5 ? 0 : 1)
            if origin != anchor.x { scaleX = (pointerInSelection.x - anchor.x) / (origin - anchor.x) }
        }
        if handle.scalesY, bounds.box.h != 0 {
            let origin = bounds.box.y + bounds.box.h * (anchorNormalized.y > 0.5 ? 0 : 1)
            if origin != anchor.y { scaleY = (pointerInSelection.y - anchor.y) / (origin - anchor.y) }
        }

        if pointer.shift, handle.isCorner {
            // Preserve the aspect ratio from the larger of the two scales.
            let s = abs(scaleX) > abs(scaleY) ? abs(scaleX) : abs(scaleY)
            scaleX = s * (scaleX < 0 ? -1 : 1)
            scaleY = s * (scaleY < 0 ? -1 : 1)
        }

        // Don't let a shape collapse to nothing; flipping is fine, zero isn't.
        if abs(scaleX) < 0.01 { scaleX = scaleX < 0 ? -0.01 : 0.01 }
        if abs(scaleY) < 0.01 { scaleY = scaleY < 0 ? -0.01 : 0.01 }

        for id in selectedIds {
            applyScale(
                to: id, scaleX: scaleX, scaleY: scaleY,
                anchor: anchor, selectionTransform: bounds.transform,
                isWidthOnly: !handle.scalesY
            )
        }
    }

    /// Scale one shape about `anchor`, expressed in the selection's space.
    private func applyScale(
        to id: AnnoShapeID,
        scaleX: Double,
        scaleY: Double,
        anchor: Vec,
        selectionTransform: Mat,
        isWidthOnly: Bool
    ) {
        guard let shape = document.shape(id) else { return }
        let toSelection = Mat.multiply(selectionTransform.inverse, shape.pageTransform)
        let originInSelection = toSelection.applyToPoint(Vec(0, 0))
        let scaledOrigin = Vec(
            anchor.x + (originInSelection.x - anchor.x) * scaleX,
            anchor.y + (originInSelection.y - anchor.y) * scaleY
        )
        let newPageOrigin = selectionTransform.applyToPoint(scaledOrigin)

        // The shape's own axes, expressed in selection space, tell us how much of each scale
        // factor lands on its width and height.
        let relativeRotation = toSelection.rotation
        let cosr = abs(cos(relativeRotation))
        let sinr = abs(sin(relativeRotation))
        let sx = scaleX * cosr + scaleY * sinr
        let sy = scaleY * cosr + scaleX * sinr

        document.update(id) { shape in
            shape.x = newPageOrigin.x
            shape.y = newPageOrigin.y
            switch shape.kind {
            case var .geo(props):
                props.w = Swift.max(1, abs(props.w * sx))
                props.h = Swift.max(1, abs(props.h * sy))
                shape.kind = .geo(props)
            case var .redaction(props):
                props.w = Swift.max(1, abs(props.w * sx))
                props.h = Swift.max(1, abs(props.h * sy))
                shape.kind = .redaction(props)
            case var .highlight(props):
                props.w = Swift.max(1, abs(props.w * sx))
                props.h = Swift.max(1, abs(props.h * sy))
                shape.kind = .highlight(props)
            case var .numbered(props):
                // A callout stays a circle, so it takes the average of the two scales.
                props.diameter = Swift.max(8, abs(props.diameter * (abs(sx) + abs(sy)) / 2))
                shape.kind = .numbered(props)
            case var .draw(props):
                props.points = props.points.map { Vec($0.x * sx, $0.y * sy, $0.z) }
                shape.kind = .draw(props)
            case var .arrow(props):
                props.start = Vec(props.start.x * sx, props.start.y * sy)
                props.end = Vec(props.end.x * sx, props.end.y * sy)
                props.bend *= (abs(sx) + abs(sy)) / 2
                shape.kind = .arrow(props)
            case var .text(props):
                if isWidthOnly {
                    // A side handle sets the width text wraps into, rather than scaling the type.
                    let width = props.autoSize ? Double(TextMeasure.measure(props).width) : props.w
                    props.w = Swift.max(TextMeasure.minWidth, abs(width * sx))
                    props.autoSize = false
                } else {
                    // Corners scale the type itself, uniformly - text can't stretch on one axis.
                    let uniform = (abs(sx) + abs(sy)) / 2
                    props.fontSize = Swift.max(4, props.fontSize * uniform)
                    if !props.autoSize {
                        props.w = Swift.max(TextMeasure.minWidth, props.w * uniform)
                    }
                }
                shape.kind = .text(props)
            }
        }
    }

    // MARK: - Rotate

    private func rotate(center: Vec, startAngle: Double, initial: AnnoDocument.Snapshot, pointer: PointerInfo) {
        document.restore(initial)
        var delta = Vec.angle(center, pointer.pagePoint) - startAngle
        if pointer.shift {
            // Snap to 15° increments.
            delta = (delta / (PI / 12)).rounded() * (PI / 12)
        }
        for id in selectedIds {
            document.update(id) { shape in
                let rotated = Vec.rotWith(Vec(shape.x, shape.y), center, delta)
                shape.x = rotated.x
                shape.y = rotated.y
                shape.rotation += delta
            }
        }
    }

    // MARK: - Arrow handles

    private func dragArrowHandle(id: AnnoShapeID, handle: AnnoSelectionHandle, pointer: PointerInfo) {
        guard let shape = document.shape(id) else { return }
        let local = document.pointInShapeSpace(shape, pointer.pagePoint)

        switch handle {
        case .arrowStart:
            document.update(id) { shape in
                guard case var .arrow(p) = shape.kind else { return }
                p.start = local
                shape.kind = .arrow(p)
            }
            bindTerminal(arrowId: id, terminal: .start, at: pointer.pagePoint, precise: pointer.alt)
        case .arrowEnd:
            document.update(id) { shape in
                guard case var .arrow(p) = shape.kind else { return }
                p.end = local
                shape.kind = .arrow(p)
            }
            bindTerminal(arrowId: id, terminal: .end, at: pointer.pagePoint, precise: pointer.alt)
        case .arrowMiddle:
            // Bend is the signed distance from the straight line between the terminals to where the
            // middle handle has been dragged.
            let bindings = document.arrowBindings(id)
            let terminals = ArrowShared.terminalsInArrowSpace(document, shape, bindings)
            let mid = Vec.med(terminals.start, terminals.end)
            let delta = Vec.sub(terminals.end, terminals.start)
            guard delta.len > 0 else { return }
            let perpendicular = delta.uni.per
            var bend = -Vec.sub(local, mid).x * perpendicular.x - Vec.sub(local, mid).y * perpendicular.y
            // Snap back to straight near zero.
            if abs(bend) < ArrowConstants.minArrowBend / 2 { bend = 0 }
            document.update(id) { shape in
                guard case var .arrow(p) = shape.kind else { return }
                p.bend = bend
                shape.kind = .arrow(p)
            }
        default:
            break
        }
    }
}

// MARK: - Text

extension AnnoEditor {
    /// Create an empty text shape at a page point and start typing into it.
    ///
    /// The shape is placed so the click lands on the vertical middle of the first line, and
    /// horizontally according to the alignment - which is the anchor `updateEditingText` then keeps
    /// fixed as the text grows.
    func createText(at pagePoint: Vec) {
        markUndo()
        var props = TextProps()
        props.swatch = currentSwatch
        props.fontSize = currentTextFontSize
        props.fontFamily = currentFontFamily
        props.isBold = currentTextIsBold
        props.isItalic = currentTextIsItalic
        props.isUnderline = currentTextIsUnderline
        props.align = currentTextAlign

        let size = TextMeasure.measure(props)
        let x: Double
        switch props.align {
        case .start: x = pagePoint.x
        case .middle: x = pagePoint.x - Double(size.width) / 2
        case .end: x = pagePoint.x - Double(size.width)
        }
        let shape = AnnoShape(x: x, y: pagePoint.y - Double(size.height) / 2, kind: .text(props))
        document.add(shape)
        selectedIds = [shape.id]
        startEditingText(shape.id)
    }

    func startEditingText(_ id: AnnoShapeID) {
        guard let shape = document.shape(id), shape.isText else { return }
        editingTextId = id
        selectedIds = [id]
        onEditingTextChanged?(id)
        notifyChanged()
    }

    /// Finish editing. An empty text shape is thrown away.
    func stopEditingText() {
        guard let id = editingTextId else { return }
        editingTextId = nil
        if let shape = document.shape(id), let props = shape.textProps,
           props.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.delete([id])
            selectedIds.remove(id)
        }
        onEditingTextChanged?(nil)
        // Fall back to select once the text is committed, the same as finishing a geo or an arrow.
        // Safe against the `tool` observer calling back into here: `editingTextId` is already nil,
        // so the guard at the top returns immediately.
        if tool == .text { tool = .select }
        notifyChanged()
    }

    /// Apply typed text and move the shape so its alignment anchor stays put.
    ///
    /// Centred text grows evenly to both sides, end-aligned text grows leftwards, and start-aligned
    /// text grows rightwards and downwards.
    func updateEditingText(_ id: AnnoShapeID, to text: String) {
        guard let shape = document.shape(id), let props = shape.textProps, props.text != text else { return }

        let before = TextMeasure.measure(props)
        var next = props
        next.text = text
        let after = TextMeasure.measure(next)

        let widthDelta = Double(after.width - before.width)
        let delta: Vec?
        switch props.align {
        case .middle: delta = Vec(widthDelta / 2, 0)
        case .end: delta = Vec(widthDelta, 0)
        case .start: delta = nil
        }

        document.update(id) { shape in
            if let delta {
                // The shift happens in the shape's own frame, so rotated text still grows the
                // right way.
                let rotated = Vec.rot(delta, shape.rotation)
                shape.x -= rotated.x
                shape.y -= rotated.y
            }
            shape.kind = .text(next)
        }
        notifyChanged()
    }
}
