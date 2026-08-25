import Foundation

/// The shape store: shapes in z-order (back to front), arrow bindings, and the derived geometry
/// every other system reads. This plays the role of old-apps's `Editor` for the parts the ported
/// engines need - `getShape`, `getShapeGeometry`, `getShapePageTransform`, `getShapePageBounds`.
final class AnnoDocument {
    private(set) var shapes: [AnnoShape] = []
    private(set) var bindings: [ArrowBinding] = []

    private var indexById: [AnnoShapeID: Int] = [:]
    private var geometryCache: [AnnoShapeID: Geometry2d] = [:]
    private var arrowInfoCache: [AnnoShapeID: ArrowInfo] = [:]
    private var renderCache: [AnnoShapeID: [RenderElement]] = [:]

    // MARK: - Reading

    func shape(_ id: AnnoShapeID) -> AnnoShape? {
        guard let i = indexById[id] else { return nil }
        return shapes[i]
    }

    func index(of id: AnnoShapeID) -> Int? { indexById[id] }

    func pageTransform(_ shape: AnnoShape) -> Mat { shape.pageTransform }

    func pageTransform(_ id: AnnoShapeID) -> Mat? { shape(id)?.pageTransform }

    /// A point in page space expressed in the shape's local space.
    func pointInShapeSpace(_ shape: AnnoShape, _ pagePoint: Vec) -> Vec {
        shape.pageTransform.inverse.applyToPoint(pagePoint)
    }

    /// The shape's geometry in its own local space.
    func geometry(_ id: AnnoShapeID) -> Geometry2d? {
        if let cached = geometryCache[id] { return cached }
        guard let shape = shape(id) else { return nil }
        let geometry = AnnoShapeGeometry.build(shape, in: self)
        geometryCache[id] = geometry
        return geometry
    }

    func geometry(_ shape: AnnoShape) -> Geometry2d {
        geometry(shape.id) ?? AnnoShapeGeometry.build(shape, in: self)
    }

    /// The shape's bounds in page space, as the bounds of its transformed geometry.
    func pageBounds(_ id: AnnoShapeID) -> Box? {
        guard let shape = shape(id), let geometry = geometry(id) else { return nil }
        return Box.fromPoints(shape.pageTransform.applyToPoints(geometry.vertices))
    }

    /// The shape's local bounds transformed into page space, kept as a rotated quad.
    func pageCorners(_ id: AnnoShapeID) -> [Vec]? {
        guard let shape = shape(id), let geometry = geometry(id) else { return nil }
        return shape.pageTransform.applyToPoints(geometry.bounds.corners)
    }

    // MARK: - Arrow info

    /// The resolved geometry of an arrow: where its body actually starts and ends once bindings,
    /// intersections and arrowhead offsets are taken into account.
    func arrowInfo(_ id: AnnoShapeID) -> ArrowInfo? {
        if let cached = arrowInfoCache[id] { return cached }
        guard let shape = shape(id), case .arrow = shape.kind else { return nil }
        let info = ArrowEngine.getArrowInfo(self, shape)
        arrowInfoCache[id] = info
        return info
    }

    /// What to draw for a shape, cached until the shape itself changes.
    ///
    /// Rebuilding this per frame meant panning re-ran the whole freehand pipeline for strokes whose
    /// pixels hadn't moved. old-apps sidesteps it by giving each shape its own DOM node and only
    /// touching its transform; the cache is the same idea.
    func renderElements(_ id: AnnoShapeID) -> [RenderElement] {
        if let cached = renderCache[id] { return cached }
        guard let shape = shape(id) else { return [] }
        let elements = AnnoShapeRenderer.elements(for: shape, in: self)
        renderCache[id] = elements
        return elements
    }

    func arrowBindings(_ arrowId: AnnoShapeID) -> ArrowBindings {
        ArrowBindings(
            start: bindings.first { $0.arrowId == arrowId && $0.terminal == .start },
            end: bindings.first { $0.arrowId == arrowId && $0.terminal == .end }
        )
    }

    func bindings(from arrowId: AnnoShapeID) -> [ArrowBinding] {
        bindings.filter { $0.arrowId == arrowId }
    }

    func bindings(to shapeId: AnnoShapeID) -> [ArrowBinding] {
        bindings.filter { $0.toId == shapeId }
    }

    // MARK: - Writing

    /// Drop the derived state for specific shapes.
    ///
    /// An arrow's shape depends on whatever it's bound to, so moving a shape also invalidates the
    /// arrows attached to it - but nothing else. Clearing every cache on every edit meant dragging
    /// one shape recomputed the geometry of all the others.
    private func invalidate(_ ids: Set<AnnoShapeID>) {
        var stale = ids
        for binding in bindings where ids.contains(binding.toId) {
            stale.insert(binding.arrowId)
        }
        for id in stale {
            geometryCache.removeValue(forKey: id)
            arrowInfoCache.removeValue(forKey: id)
            renderCache.removeValue(forKey: id)
        }
    }

    /// For edits that can touch anything: undo, restoring a snapshot, loading a scratchpad.
    private func invalidateAll() {
        geometryCache.removeAll(keepingCapacity: true)
        arrowInfoCache.removeAll(keepingCapacity: true)
        renderCache.removeAll(keepingCapacity: true)
    }

    private func reindex() {
        indexById.removeAll(keepingCapacity: true)
        for (i, shape) in shapes.enumerated() { indexById[shape.id] = i }
    }

    func add(_ shape: AnnoShape) {
        shapes.append(shape)
        reindex()
        invalidate([shape.id])
    }

    func update(_ shape: AnnoShape) {
        guard let i = indexById[shape.id] else { return }
        shapes[i] = shape
        invalidate([shape.id])
    }

    func update(_ id: AnnoShapeID, _ transform: (inout AnnoShape) -> Void) {
        guard let i = indexById[id] else { return }
        transform(&shapes[i])
        invalidate([id])
    }

    func delete(_ ids: Set<AnnoShapeID>) {
        shapes.removeAll { ids.contains($0.id) }
        // Bindings that point at a deleted shape, or belong to a deleted arrow, go with it.
        // Read the arrows off the doomed shapes before the bindings go.
        let stale = ids.union(bindings.filter { ids.contains($0.toId) }.map(\.arrowId))
        bindings.removeAll { ids.contains($0.arrowId) || ids.contains($0.toId) }
        reindex()
        invalidate(stale)
    }

    func bringToFront(_ ids: Set<AnnoShapeID>) {
        let moved = shapes.filter { ids.contains($0.id) }
        shapes.removeAll { ids.contains($0.id) }
        shapes.append(contentsOf: moved)
        reindex()
    }

    func sendToBack(_ ids: Set<AnnoShapeID>) {
        let moved = shapes.filter { ids.contains($0.id) }
        shapes.removeAll { ids.contains($0.id) }
        shapes.insert(contentsOf: moved, at: 0)
        reindex()
    }

    func setBinding(_ binding: ArrowBinding) {
        bindings.removeAll { $0.arrowId == binding.arrowId && $0.terminal == binding.terminal }
        bindings.append(binding)
        invalidate([binding.arrowId])
    }

    func removeBinding(arrowId: AnnoShapeID, terminal: ArrowTerminal) {
        bindings.removeAll { $0.arrowId == arrowId && $0.terminal == terminal }
        invalidate([arrowId])
    }

    // MARK: - Snapshots (undo/redo)

    struct Snapshot: Codable {
        var shapes: [AnnoShape]
        var bindings: [ArrowBinding]
    }

    func snapshot() -> Snapshot {
        Snapshot(shapes: shapes, bindings: bindings)
    }

    func restore(_ snapshot: Snapshot) {
        shapes = snapshot.shapes
        bindings = snapshot.bindings
        reindex()
        invalidateAll()
    }
}

/// Builds the local-space geometry for a shape, mirroring each shape util's `getGeometry`.
enum AnnoShapeGeometry {
    static func build(_ shape: AnnoShape, in document: AnnoDocument) -> Geometry2d {
        switch shape.kind {
        case let .draw(props):
            return drawGeometry(props)
        case let .geo(props):
            // The geometry flattens the same path that gets drawn, so hit-testing, selection
            // bounds and arrow intersections all follow exactly what's on screen.
            let isFilled = props.fill != .none
            switch props.geo {
            case .rectangle:
                guard props.cornerRadius > 0.5 else {
                    return Rectangle2d(width: props.w, height: props.h, isFilled: isFilled)
                }
                let vertices = GeoPaths.path(for: props).vertices()
                guard vertices.count >= 3 else {
                    return Rectangle2d(width: props.w, height: props.h, isFilled: isFilled)
                }
                return Polygon2d(points: vertices, isFilled: isFilled)
            case .ellipse:
                return Ellipse2d(width: props.w, height: props.h, isFilled: isFilled)
            }
        case .arrow:
            return arrowGeometry(shape, in: document)
        case let .text(props):
            let size = TextMeasure.measure(props)
            return Rectangle2d(
                width: Double(size.width),
                height: Double(size.height),
                isFilled: true
            )
        case let .redaction(props):
            return Rectangle2d(width: props.w, height: props.h, isFilled: true)
        case let .highlight(props):
            return Rectangle2d(width: props.w, height: props.h, isFilled: true)
        case let .numbered(props):
            return Ellipse2d(width: props.diameter, height: props.diameter, isFilled: true)
        }
    }

    /// The drawing app's `DrawShapeUtil.getGeometry`: the streamlined centerline, or a circle for
    /// a dot.
    private static func drawGeometry(_ props: DrawProps) -> Geometry2d {
        let points = props.points
        let sw = props.strokeWidth + 1

        guard !points.isEmpty else {
            return Circle2d(x: -sw, y: -sw, radius: sw, isFilled: true)
        }

        // A dot: a stroke small enough that it's really just a blob.
        let box = Box.fromPoints(points)
        if box.width < sw * 2 && box.height < sw * 2 {
            return Circle2d(x: -sw, y: -sw, radius: sw, isFilled: true)
        }

        let options = FreehandSettings.forDrawShape(
            isPen: props.isPen,
            isComplete: props.isComplete,
            strokeWidth: sw,
            forceComplete: true,
            forceSolid: true
        )
        let strokePoints = StrokeOutline.getStrokePoints(points, options).map { $0.point }

        if props.isClosed && strokePoints.count > 2 {
            return Polygon2d(points: strokePoints, isFilled: false)
        }
        if strokePoints.count < 2 {
            return Circle2d(x: -sw, y: -sw, radius: sw, isFilled: true)
        }
        return Polyline2d(points: strokePoints)
    }

    /// An arrow's geometry is its resolved body: a segment or an arc.
    private static func arrowGeometry(_ shape: AnnoShape, in document: AnnoDocument) -> Geometry2d {
        guard let info = ArrowEngine.getArrowInfo(document, shape) else {
            return Polyline2d(points: [Vec(0, 0), Vec(1, 1)])
        }
        switch info.body {
        case let .straight(start, end):
            if Vec.equals(start, end) {
                return Polyline2d(points: [start, Vec.addXY(end, 1, 1)])
            }
            return Edge2d(start: start, end: end)
        case let .arc(arc):
            guard arc.radius.isFinite, arc.radius > 0, !Vec.equals(info.start.point, info.end.point) else {
                return Edge2d(start: info.start.point, end: info.end.point)
            }
            return Arc2d(
                center: arc.center,
                start: info.start.point,
                end: info.end.point,
                sweepFlag: arc.sweepFlag,
                largeArcFlag: arc.largeArcFlag
            )
        }
    }
}
