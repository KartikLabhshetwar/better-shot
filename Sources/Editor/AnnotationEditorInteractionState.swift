import CoreGraphics

enum AnnotationInteraction {
    case drawing(startPoint: CGPoint)
    case moving(id: AnnotationItem.ID, startPoint: CGPoint, originalItem: AnnotationItem)
    case movingSelection(ids: Set<AnnotationItem.ID>, startPoint: CGPoint, originalItems: [AnnotationItem])
    case resizing(id: AnnotationItem.ID, handle: AnnotationResizeHandle, originalItem: AnnotationItem)
    case selecting(startPoint: CGPoint, originalSelection: Set<AnnotationItem.ID>, extendsSelection: Bool)
}

enum AnnotationToolState: String {
    case idle
    case drawing
    case translating
    case resizing

    func path(for tool: AnnotationTool) -> String {
        "root.\(tool.rawValue).\(rawValue)"
    }
}

struct AnnotationHistory {
    private var undoStack: [[AnnotationItem]] = []
    private var redoStack: [[AnnotationItem]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func reset() {
        undoStack = []
        redoStack = []
    }

    mutating func push(_ items: [AnnotationItem]) {
        guard undoStack.last != items else { return }

        undoStack.append(items)
        redoStack.removeAll()
    }

    mutating func undo(current: [AnnotationItem]) -> [AnnotationItem]? {
        guard let previous = undoStack.popLast() else { return nil }

        redoStack.append(current)
        return previous
    }

    mutating func redo(current: [AnnotationItem]) -> [AnnotationItem]? {
        guard let next = redoStack.popLast() else { return nil }

        undoStack.append(current)
        return next
    }
}
