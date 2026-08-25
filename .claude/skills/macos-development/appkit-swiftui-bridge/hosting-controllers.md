# Hosting Controllers

Embedding SwiftUI views inside AppKit applications using NSHostingView and NSHostingController. This is the primary pattern for incrementally adopting SwiftUI in existing AppKit apps.

## NSHostingView

Wraps a SwiftUI view as an NSView. Use when you need to embed SwiftUI in an existing NSView hierarchy.

### Basic Usage

```swift
import SwiftUI

let swiftUIView = MySwiftUIView(viewModel: viewModel)
let hostingView = NSHostingView(rootView: swiftUIView)

// Add to existing view hierarchy
parentView.addSubview(hostingView)

// With Auto Layout
hostingView.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    hostingView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
    hostingView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
    hostingView.topAnchor.constraint(equalTo: parentView.topAnchor),
    hostingView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
])
```

### Sizing Behavior

NSHostingView calculates its `intrinsicContentSize` from the SwiftUI view. Control this with `sizingOptions`:

```swift
let hostingView = NSHostingView(rootView: myView)

// Default: hosting view has intrinsic size from SwiftUI content
hostingView.sizingOptions = .intrinsicContentSize

// Prefer minimal size (useful for fixed-size badges, indicators)
hostingView.sizingOptions = .minSize

// Both (most flexible)
hostingView.sizingOptions = [.intrinsicContentSize, .minSize]
```

### Updating the Root View

When your data model changes, update the hosted view:

```swift
// With @Observable (macOS 14+) - automatic updates, no manual refresh needed
@Observable class ViewModel {
    var title = "Hello"
}

let viewModel = ViewModel()
let hostingView = NSHostingView(rootView: ContentView(viewModel: viewModel))
// Changes to viewModel.title automatically update the hosted SwiftUI view

// Without @Observable - manually update rootView
hostingView.rootView = MySwiftUIView(updatedData: newData)
```

## NSHostingController

Wraps a SwiftUI view as an NSViewController. Use when you need a full view controller (e.g., in NSSplitViewController, tab views, sheets).

### Basic Usage

```swift
let hostingController = NSHostingController(rootView: SettingsView())

// Present as sheet
parentViewController.presentAsSheet(hostingController)

// Add as child view controller
parentVC.addChild(hostingController)
parentVC.view.addSubview(hostingController.view)
hostingController.view.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    hostingController.view.leadingAnchor.constraint(equalTo: parentVC.view.leadingAnchor),
    hostingController.view.trailingAnchor.constraint(equalTo: parentVC.view.trailingAnchor),
    hostingController.view.topAnchor.constraint(equalTo: parentVC.view.topAnchor),
    hostingController.view.bottomAnchor.constraint(equalTo: parentVC.view.bottomAnchor)
])
```

### Window Management

Create a new window with SwiftUI content:

```swift
func showSwiftUIWindow() {
    let hostingController = NSHostingController(rootView: DetailView())

    let window = NSWindow(contentViewController: hostingController)
    window.title = "Detail"
    window.setContentSize(NSSize(width: 600, height: 400))
    window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
    window.center()
    window.makeKeyAndOrderFront(nil)

    // Retain the window controller
    let windowController = NSWindowController(window: window)
    windowController.showWindow(nil)
}
```

### In NSSplitViewController

```swift
class MainSplitViewController: NSSplitViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Sidebar in SwiftUI
        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: SidebarView())
        )
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true

        // Content in SwiftUI
        let contentItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: ContentView())
        )
        contentItem.minimumThickness = 300

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }
}
```

## Incremental Adoption Strategy

### Phase 1: Leaf Views
Start by replacing simple, self-contained views:
- Settings panels
- Detail views
- Empty states
- Status indicators

```swift
// Replace an AppKit detail view with SwiftUI
class DetailViewController: NSViewController {
    private var hostingView: NSHostingView<DetailSwiftUIView>!

    override func loadView() {
        let swiftUIView = DetailSwiftUIView(item: item)
        hostingView = NSHostingView(rootView: swiftUIView)
        self.view = hostingView
    }
}
```

### Phase 2: Container Views
Move to views that contain other views:
- Tab containers
- Split view panels
- List/detail patterns

### Phase 3: Window-Level
Eventually host entire windows in SwiftUI:
- New windows as SwiftUI `WindowGroup`
- Settings via SwiftUI `Settings` scene
- Menu bar with `MenuBarExtra`

### Phase 4: Full Migration
- Replace the App Delegate entry point with SwiftUI `@main App`
- Use `NSApplicationDelegateAdaptor` for remaining AppKit lifecycle needs

```swift
@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        Settings {
            SettingsView()
        }
    }
}
```

## SwiftUI Environment in Hosted Views

Hosted SwiftUI views have access to the full SwiftUI environment:

```swift
let hostingController = NSHostingController(
    rootView: MyView()
        .environment(\.managedObjectContext, persistentContainer.viewContext)
        .environment(appState)
)
```

## Toolbar Integration

NSHostingController integrates with NSWindow toolbars. Use SwiftUI's `.toolbar` modifier:

```swift
struct ContentView: View {
    var body: some View {
        MainContent()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { }
                }
            }
    }
}
// When hosted in NSHostingController, toolbar items appear in the window toolbar
```

## Best Practices

1. **Use @Observable for shared state** - Automatic updates across the bridge (macOS 14+)
2. **Set sizing options explicitly** - Don't rely on default sizing for complex layouts
3. **Adopt incrementally** - Start with leaf views, work up to containers
4. **Keep the bridge thin** - Don't build complex logic at the boundary
5. **Use NSHostingController for view controller contexts** - Sheets, split views, tab views
6. **Use NSHostingView for view-level embedding** - Cells, decorations, inline content
7. **Test resizing behavior** - Verify hosted views respond correctly to window resizing
