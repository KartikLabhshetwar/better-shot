# NSViewRepresentable

Wrapping AppKit views for use in SwiftUI. This is the primary mechanism for using AppKit views within a SwiftUI view hierarchy.

## Protocol Requirements

```swift
struct MyAppKitView: NSViewRepresentable {
    // 1. Create the AppKit view
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        return textField
    }

    // 2. Update when SwiftUI state changes
    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }

    // 3. Optional: Provide a coordinator for delegation
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // 4. Optional: Clean up resources
    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        // Remove observers, cancel timers, etc.
    }

    // 5. Optional: Control sizing
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
```

## The Coordinator Pattern

The coordinator is a long-lived object that survives SwiftUI view re-creation. Use it for:
- **Delegation**: AppKit delegate callbacks
- **Target-action**: Button targets, gesture recognizers
- **Observation**: KVO, NotificationCenter

```swift
class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: MyAppKitView
    var observation: NSKeyValueObservation?

    init(_ parent: MyAppKitView) {
        self.parent = parent
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        parent.text = textField.stringValue
    }
}
```

### Updating the Parent Reference

Refresh the coordinator's `parent` reference in `updateNSView`:

```swift
func updateNSView(_ nsView: NSTextField, context: Context) {
    context.coordinator.parent = self  // Keep parent reference fresh
    nsView.stringValue = text
}
```

## Wrapping Common AppKit Views

### NSTextView (Rich Text Editing)

```swift
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isRichText = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributedText)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.textStorage?.attributedString() != attributedText {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            parent.attributedText = NSAttributedString(attributedString: storage)
        }
    }
}
```

### NSTableView (High-Performance Lists)

Use when `List` or `Table` performance is insufficient (100k+ rows):

```swift
struct HighPerformanceList: NSViewRepresentable {
    let items: [ListItem]
    var onSelect: (ListItem) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.title = "Items"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        (scrollView.documentView as? NSTableView)?.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: HighPerformanceList
        init(_ parent: HighPerformanceList) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as? NSTextField
                ?? NSTextField(labelWithString: "")
            cell.identifier = tableColumn!.identifier
            cell.stringValue = parent.items[row].title
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            guard row >= 0 else { return }
            parent.onSelect(parent.items[row])
        }
    }
}
```

### Drag and Drop

```swift
struct DragDropView: NSViewRepresentable {
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DropTargetView()
        view.coordinator = context.coordinator
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class DropTargetView: NSView {
        weak var coordinator: Coordinator?

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
                return false
            }
            coordinator?.parent.onDrop(urls)
            return true
        }
    }

    class Coordinator: NSObject {
        var parent: DragDropView
        init(_ parent: DragDropView) { self.parent = parent }
    }
}
```

## Layout Integration

### sizeThatFits

Control how the wrapped view participates in SwiftUI layout:

```swift
func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
    // Return nil to use SwiftUI's default sizing
    // Return a size to override

    // Respect proposed width, calculate height
    let width = proposal.width ?? nsView.intrinsicContentSize.width
    let height = nsView.intrinsicContentSize.height
    return CGSize(width: width, height: height)
}
```

### Intrinsic Content Size

For custom NSView subclasses, override `intrinsicContentSize`:

```swift
class CustomView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 44)
    }
}
```

## Animation Context

Access SwiftUI animation state in `updateNSView`:

```swift
func updateNSView(_ nsView: NSView, context: Context) {
    if context.transaction.animation != nil {
        NSAnimationContext.runAnimationGroup { animContext in
            animContext.duration = 0.25
            animContext.allowsImplicitAnimation = true
            nsView.animator().alphaValue = isVisible ? 1.0 : 0.0
        }
    } else {
        nsView.alphaValue = isVisible ? 1.0 : 0.0
    }
}
```

## Best Practices

1. **Keep makeNSView minimal** - Only create and configure. Don't set data.
2. **Guard against redundant updates** - Check if values actually changed in `updateNSView`
3. **Always clean up in dismantleNSView** - Remove observers, invalidate timers, cancel tasks
4. **Update coordinator.parent** - Refresh the parent reference in `updateNSView`
5. **Use sizeThatFits for layout** - Don't set frames manually; let SwiftUI handle layout
6. **Avoid storing state in the coordinator** - Use @Binding and @State in the parent
