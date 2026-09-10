import Foundation

@main
struct OverlayLayoutCheck {
    static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        precondition(OverlayToolLayout(data: nil) == .standard)
        precondition(OverlayToolLayout(data: Data("invalid".utf8)) == .standard)
        for preset in [OverlayLayoutPreset.standard, .sharing, .minimal] {
            let base = preset.layout!
            precondition(base.preset == preset)
            precondition(OverlayToolLayout(data: base.data) == base)
            for slot in OverlayToolSlot.allCases {
                for tool in OverlayTool.allCases.map(Optional.some) + [nil] {
                    var layout = base
                    layout.assign(tool, to: slot)
                    precondition(Set(layout.assignments.values).count == layout.assignments.count,
                                 "Moving an action cannot duplicate it")
                    precondition(layout.assignments.values.contains(.dismiss), "Dismiss must remain reachable")
                    precondition(OverlayToolLayout(data: layout.data) == layout, "Custom layouts must persist")
                }
            }
        }
        var layout = OverlayToolLayout.standard
        layout.assign(.share, to: .topLeft)
        precondition(layout.assignments[.topLeft] == .share && layout.assignments[.bottomRight] == .pin)
        precondition(layout.preset == .custom)
        layout.assign(nil, to: .bottomRight)
        precondition(!layout.assignments.values.contains(.pin))
        layout.assign(.pin, to: .topRight)
        precondition(layout.assignments[.topRight] == .pin && layout.assignments[.bottomRight] == .dismiss)
        let damaged = Data(#"{"topLeft":"copy","centerLeft":"copy","bottomRight":"future-action"}"#.utf8)
        let recovered = OverlayToolLayout(data: damaged)
        precondition(recovered.assignments.values.filter { $0 == .copy }.count == 1)
        precondition(recovered.assignments[.topRight] == .dismiss)
        print("Overlay layouts: presets, swaps, hiding, required dismissal, decoding recovery, and persistence passed")
    }
}
