import Foundation

/// The resolved description of an arrow.

struct ArrowBindings {
    var start: ArrowBinding?
    var end: ArrowBinding?
}

/// One end of an arrow: where its handle sits (the terminal the user drags) and where the drawn
/// body actually starts (pushed off the bound shape's edge).
struct ArrowPoint {
    var handle: Vec
    var point: Vec
    var arrowhead: Arrowhead
}

/// A circular arc described the way SVG's arc command wants it.
struct ArcInfo {
    var center: Vec
    var radius: Double
    /// The signed size of the arc in radians.
    var size: Double
    /// The signed length of the arc in distance units.
    var length: Double
    var largeArcFlag: Int
    var sweepFlag: Int
}

enum ArrowBody {
    case straight(start: Vec, end: Vec)
    case arc(ArcInfo)
}

struct ArrowInfo {
    var bindings: ArrowBindings
    var start: ArrowPoint
    var end: ArrowPoint
    /// The midpoint handle, which the user drags to bend the arrow.
    var middle: Vec
    var body: ArrowBody
    /// The arc through the *handles*, which the midpoint handle rides on. Only set for arcs.
    var handleArc: ArcInfo?
    var isValid: Bool

    var isStraight: Bool {
        if case .straight = body { return true }
        return false
    }
}

enum ArrowConstants {
    static let minArrowLength: Double = 10
    static let boundArrowOffset: Double = 10
    static let wayTooBigArrowBendFactor: Double = 10
    /// Bends smaller than this snap the arrow straight.
    static let minArrowBend: Double = 8
    /// Keeps anchors off exact edges and corners, to avoid degenerate arrow intersections.
    static let normalizedAnchorEpsilon: Double = 1e-3
}
