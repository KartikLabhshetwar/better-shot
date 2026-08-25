import CoreGraphics
import Foundation

/// The dash pattern for a segment: how long the dashes are and where the pattern starts, so that a
/// whole number of them fits the segment and both ends land on a dash.
///
/// Ported from `getPerfectDashProps` in
/// `packages/editor/src/lib/editor/shapes/shared/getPerfectDashProps.ts`.
func perfectDashProps(
    totalLength: Double,
    strokeWidth: Double,
    style: DashStyle,
    snap: Int = 1,
    start: DashTerminal = .outset,
    end: DashTerminal = .outset,
    lengthRatio: Double = 2,
    closed: Bool = false
) -> (dashes: [CGFloat], phase: CGFloat) {
    var totalLength = totalLength
    var dashLength = 0.0
    var dashCount = 0
    var ratio = 1.0
    var gapLength = 0.0
    var strokeDashoffset = 0.0

    switch style {
    case .dashed:
        ratio = 1
        dashLength = Swift.min(strokeWidth * lengthRatio, totalLength / 4)
    case .dotted:
        ratio = 100
        dashLength = strokeWidth / ratio
    case .solid, .draw:
        return ([], 0)
    }

    guard dashLength > 0 else { return ([], 0) }

    if !closed {
        switch start {
        case .outset:
            totalLength += dashLength / 2
            strokeDashoffset += dashLength / 2
        case .skip:
            totalLength -= dashLength
            strokeDashoffset -= dashLength
        case .none:
            break
        }
        switch end {
        case .outset: totalLength += dashLength / 2
        case .skip: totalLength -= dashLength
        case .none: break
        }
    }

    dashCount = Int(floor(totalLength / dashLength / (2 * ratio)))
    dashCount -= dashCount % snap

    if dashCount < 3 && style == .dashed {
        if totalLength / strokeWidth < 4 {
            dashLength = totalLength
            dashCount = 1
            gapLength = 0
        } else {
            dashLength = totalLength * (1.0 / 3.0)
            gapLength = totalLength * (1.0 / 3.0)
        }
    } else {
        guard dashCount > 0 else { return ([], 0) }
        dashLength = totalLength / Double(dashCount) / (2 * ratio)
        if closed {
            strokeDashoffset = dashLength / 2
            gapLength = (totalLength - Double(dashCount) * dashLength) / Double(dashCount)
        } else {
            gapLength = (totalLength - Double(dashCount) * dashLength) / Double(Swift.max(1, dashCount - 1))
        }
    }

    guard dashLength.isFinite, gapLength.isFinite, dashLength > 0 else { return ([], 0) }
    // Core Graphics advances the pattern by the phase, where SVG's dash offset pulls it back.
    return ([CGFloat(dashLength), CGFloat(Swift.max(0, gapLength))], CGFloat(-strokeDashoffset))
}

/// How a dashed run treats its ends.
enum DashTerminal {
    /// Extend by half a dash, so the run starts and ends mid-dash.
    case outset
    /// Pull in by a dash.
    case skip
    case none
}
