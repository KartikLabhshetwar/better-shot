# State Management Across Frameworks

Bridging state between AppKit and SwiftUI. The key challenge is keeping both sides synchronized without retain cycles or stale data.

## Approach 1: @Observable (Recommended, macOS 14+)

The simplest and most modern approach. Both AppKit and SwiftUI can observe the same `@Observable` class.

```swift
@Observable
class AppState {
    var currentDocument: Document?
    var isEditing = false
    var statusMessage = ""
}
```

### SwiftUI Side

```swift
struct ContentView: View {
    var appState: AppState

    var body: some View {
        VStack {
            if let doc = appState.currentDocument {
                DocumentView(document: doc)
            }
            Text(appState.statusMessage)
                .foregroundStyle(.secondary)
        }
    }
}
```

### AppKit Side

Use `withObservationTracking` to react to changes:

```swift
class AppKitController: NSViewController {
    let appState: AppState
    private var isObserving = true

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeState()
    }

    private func observeState() {
        guard isObserving else { return }
        withObservationTracking {
            // Access properties you want to observe
            let message = appState.statusMessage
            updateStatusBar(message)
        } onChange: {
            // Re-observe on next change (must re-register)
            DispatchQueue.main.async { [weak self] in
                self?.observeState()
            }
        }
    }

    deinit {
        isObserving = false
    }
}
```

### Hosting with @Observable

```swift
let appState = AppState()

// SwiftUI side - pass as environment
let hostingView = NSHostingView(
    rootView: ContentView()
        .environment(appState)
)

// AppKit side - use the same instance
let appKitController = AppKitController(appState: appState)

// Changes from either side propagate automatically
appState.statusMessage = "Updated from AppKit"  // SwiftUI view updates
```

## Approach 2: Combine (macOS 10.15+)

Use Combine publishers for cross-framework communication when targeting older macOS versions.

### Shared ViewModel with Combine

```swift
class SharedViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var selectedItemID: UUID?
    @Published var isLoading = false
}
```

### SwiftUI Side

```swift
struct ItemListView: View {
    @ObservedObject var viewModel: SharedViewModel

    var body: some View {
        List(viewModel.items, selection: $viewModel.selectedItemID) { item in
            Text(item.name)
        }
    }
}
```

### AppKit Side

```swift
class AppKitSidebarController: NSViewController {
    let viewModel: SharedViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: SharedViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.$selectedItemID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedID in
                self?.highlightItem(selectedID)
            }
            .store(in: &cancellables)

        viewModel.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.reloadTable(with: items)
            }
            .store(in: &cancellables)
    }

    func userSelectedItem(_ id: UUID) {
        viewModel.selectedItemID = id  // SwiftUI view updates automatically
    }
}
```

## Approach 3: NotificationCenter

Best for loosely coupled, fire-and-forget communication between distant parts of the app.

```swift
// Define notification names
extension Notification.Name {
    static let documentDidSave = Notification.Name("documentDidSave")
    static let themeDidChange = Notification.Name("themeDidChange")
}

// AppKit posts
NotificationCenter.default.post(
    name: .documentDidSave,
    object: nil,
    userInfo: ["documentID": document.id]
)

// SwiftUI receives
struct ContentView: View {
    var body: some View {
        Text("Content")
            .onReceive(NotificationCenter.default.publisher(for: .documentDidSave)) { notification in
                if let docID = notification.userInfo?["documentID"] as? UUID {
                    handleSave(docID)
                }
            }
    }
}
```

## Approach 4: Shared UserDefaults / App Storage

For simple preferences shared between both frameworks:

```swift
// SwiftUI side
@AppStorage("sidebarWidth") private var sidebarWidth: Double = 250

// AppKit side
UserDefaults.standard.addObserver(self, forKeyPath: "sidebarWidth", context: nil)

override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    if keyPath == "sidebarWidth" {
        let width = UserDefaults.standard.double(forKey: "sidebarWidth")
        updateSidebarWidth(width)
    }
}
```

## Approach 5: NSResponder Chain

Pass actions up through the responder chain from SwiftUI to AppKit:

```swift
// SwiftUI sends an action up the responder chain
struct ToolbarView: View {
    var body: some View {
        Button("Save") {
            NSApp.sendAction(#selector(DocumentController.saveDocument(_:)), to: nil, from: nil)
        }
    }
}

// AppKit receives via responder chain
class DocumentController: NSDocumentController {
    @objc func saveDocument(_ sender: Any?) {
        currentDocument?.save(nil)
    }
}
```

## Choosing the Right Approach

| Approach | macOS Version | Coupling | Best For |
|----------|--------------|----------|----------|
| @Observable | 14+ | Tight | Shared view models, closely related views |
| Combine | 10.15+ | Medium | Reactive data streams, async updates |
| NotificationCenter | Any | Loose | Cross-module events, fire-and-forget |
| UserDefaults | Any | Loose | Simple preferences, settings |
| Responder Chain | Any | Loose | Menu actions, commands |

## Common Mistakes

### Retain Cycles

```swift
// Wrong - strong reference cycle
class Coordinator: NSObject {
    let viewModel: SharedViewModel
    var cancellable: AnyCancellable?

    init(viewModel: SharedViewModel) {
        self.viewModel = viewModel
        cancellable = viewModel.$items.sink { items in
            self.update(items)  // Strong capture of self!
        }
    }
}

// Right - weak capture
cancellable = viewModel.$items.sink { [weak self] items in
    self?.update(items)
}
```

### Thread Safety

```swift
// Wrong - updating UI from background thread
viewModel.$data
    .sink { data in
        self.tableView.reloadData()  // May be on background thread!
    }

// Right - ensure main thread
viewModel.$data
    .receive(on: DispatchQueue.main)
    .sink { [weak self] data in
        self?.tableView.reloadData()
    }
```

## Best Practices

1. **Use @Observable for macOS 14+** - Simplest approach, works automatically across both frameworks
2. **Avoid mixing approaches** - Pick one primary mechanism per data flow
3. **Always use weak self in closures** - Prevent retain cycles in Combine sinks and callbacks
4. **Dispatch to main thread** - All UI updates must happen on the main thread
5. **Clean up subscriptions** - Cancel Combine subscriptions and remove observers in deinit/dismantle
6. **Keep shared state minimal** - Only share what both frameworks actually need
7. **Test bidirectional updates** - Verify changes from either side propagate correctly
