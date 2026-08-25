import Foundation

/// The path for each geo shape, ported from the drawing-app's `Paths/GeoPaths.swift`.
///
/// BetterShot only draws rectangles and ellipses, so the polygon/star/cloud family is left behind;
/// what matters is that the path is built once here and used for stroking, filling and flattening
/// to hit-test vertices, so those three can never disagree about where an edge is.
enum GeoPaths {
    static func path(for props: GeoProps) -> PathBuilder {
        let w = Swift.max(1, props.w)
        let h = Swift.max(1, props.h)

        switch props.geo {
        case .rectangle:
            let radius = Swift.min(props.cornerRadius, Swift.min(w, h) / 2)
            guard radius > 0.5 else {
                return PathBuilder()
                    .move(to: Vec(0, 0))
                    .line(to: Vec(w, 0))
                    .line(to: Vec(w, h))
                    .line(to: Vec(0, h))
                    .close()
            }
            let path = PathBuilder().move(to: Vec(radius, 0))
            path.line(to: Vec(w - radius, 0))
            path.circularArc(radius: radius, largeArc: false, sweep: true, to: Vec(w, radius))
            path.line(to: Vec(w, h - radius))
            path.circularArc(radius: radius, largeArc: false, sweep: true, to: Vec(w - radius, h))
            path.line(to: Vec(radius, h))
            path.circularArc(radius: radius, largeArc: false, sweep: true, to: Vec(0, h - radius))
            path.line(to: Vec(0, radius))
            path.circularArc(radius: radius, largeArc: false, sweep: true, to: Vec(radius, 0))
            return path.close()

        case .ellipse:
            // Two half-turns, which PathBuilder turns into cubics so the flattened vertices and the
            // drawn curve describe the same ellipse.
            let cx = w / 2, cy = h / 2
            let path = PathBuilder().move(to: Vec(0, cy))
            path.arc(rx: cx, ry: cy, largeArc: false, sweep: true, xAxisRotation: 0, to: Vec(w, cy))
            path.arc(rx: cx, ry: cy, largeArc: false, sweep: true, xAxisRotation: 0, to: Vec(0, cy))
            return path.close()
        }
    }

    /// A plain box path, for the shapes whose outline is always a rectangle (redactions, the
    /// spotlight highlight, a text box's frame).
    static func box(width: Double, height: Double) -> PathBuilder {
        PathBuilder()
            .move(to: Vec(0, 0))
            .line(to: Vec(width, 0))
            .line(to: Vec(width, height))
            .line(to: Vec(0, height))
            .close()
    }
}
