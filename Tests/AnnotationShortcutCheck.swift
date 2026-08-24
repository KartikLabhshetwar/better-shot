import AppKit

@main
enum AnnotationShortcutCheck {
    static func main() {
        let keys = AnnotationTool.toolbarCases.map(\.shortcut)
        precondition(Set(keys).count == keys.count, "two tools claim the same key: \(keys)")

        for tool in AnnotationTool.toolbarCases {
            precondition(
                AnnotationTool.tool(forShortcut: tool.shortcut) == tool,
                "\(tool.title) does not round-trip through its key \(tool.shortcut)"
            )
        }

        precondition(AnnotationTool.tool(forShortcut: "z") == nil, "an unclaimed key selects nothing")
        precondition(
            AnnotationTool.tool(forShortcut: AnnotationTool.pixelate.shortcut) == nil,
            "a tool the toolbar hides has no key"
        )

        print("annotation keys: \(keys.count) tools, all unique and all round-trip")
    }
}
