# Modern AppKit Patterns

AppKit best practices for macOS 26 (Tahoe) with Liquid Glass design integration.

## When to Use AppKit

- Complex table views with custom cells
- Advanced text editing (NSTextView)
- Custom drawing with precise control
- Legacy code migration
- Features not yet available in SwiftUI
- Performance-critical UI components

## Modern NSViewController Patterns

```swift
// ✅ GOOD: Modern view controller
final class ArticleViewController: NSViewController {
    // MARK: - Properties
    private let viewModel: ArticleViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements
    private lazy var tableView: NSTableView = {
        let table = NSTableView()
        table.delegate = self
        table.dataSource = self
        table.style = .automatic
        return table
    }()

    // MARK: - Initialization
    init(viewModel: ArticleViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Lifecycle
    override func loadView() {
        view = NSView()
        setupUI()
        setupConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindViewModel()
    }

    // MARK: - Setup
    private func setupUI() {
        // Setup UI elements
    }

    private func setupConstraints() {
        // Use Auto Layout
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindViewModel() {
        viewModel.$articles
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }
}
```

## Liquid Glass in AppKit

### Visual Effect Views

```swift
// ✅ GOOD: Use NSVisualEffectView for Liquid Glass
final class GlassPanel: NSView {
    private let visualEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(visualEffectView)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Round corners
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }
}
```

### Transparent Window Background

```swift
// ✅ GOOD: Window with transparency
final class TransparentWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: backingStoreType,
            defer: flag
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear

        // Modern appearance
        if let contentView = contentView {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .underWindowBackground
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.frame = contentView.bounds
            visualEffect.autoresizingMask = [.width, .height]
            contentView.addSubview(visualEffect, positioned: .below, relativeTo: nil)
        }
    }
}
```

## Modern Table Views

```swift
// ✅ GOOD: Cell-based table view
extension ArticleViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.articles.count
    }
}

extension ArticleViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let article = viewModel.articles[row]

        guard let cellView = tableView.makeView(
            withIdentifier: ArticleCellView.identifier,
            owner: self
        ) as? ArticleCellView else {
            let cellView = ArticleCellView()
            cellView.identifier = ArticleCellView.identifier
            return cellView
        }

        cellView.configure(with: article)
        return cellView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        60
    }
}

// ✅ GOOD: Custom cell view
final class ArticleCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ArticleCell")

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let subtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Add subviews and constraints
    }

    func configure(with article: Article) {
        titleLabel.stringValue = article.title
        subtitleLabel.stringValue = article.subtitle
    }
}
```

## Window Management

```swift
// ✅ GOOD: Modern window controller
final class DocumentWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        self.init(window: window)
    }

    override func windowDidLoad() {
        super.windowDidLoad()

        // Setup toolbar
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }
}

extension DocumentWindowController: NSToolbarDelegate {
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        // Return toolbar items
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .add, .share]
    }
}
```

## Split View Controllers

```swift
// ✅ GOOD: Modern split view
final class MainSplitViewController: NSSplitViewController {
    private let sidebarViewController: SidebarViewController
    private let detailViewController: DetailViewController

    init(
        sidebarViewController: SidebarViewController,
        detailViewController: DetailViewController
    ) {
        self.sidebarViewController = sidebarViewController
        self.detailViewController = detailViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Sidebar item
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 300
        addSplitViewItem(sidebarItem)

        // Detail item
        let detailItem = NSSplitViewItem(viewController: detailViewController)
        addSplitViewItem(detailItem)

        splitView.autosaveName = "MainSplitView"
    }
}
```

## Menu Bar Apps with AppKit

```swift
// ✅ GOOD: Modern menu bar app
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "App")
            button.action = #selector(togglePopover)
        }

        // Create popover
        let popover = NSPopover()
        popover.contentViewController = MenuViewController()
        popover.behavior = .transient
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
```

## Responder Chain and Events

```swift
// ✅ GOOD: Handling key events
override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 51:  // Delete
        deleteSelected()
    case 36:  // Return
        editSelected()
    default:
        super.keyDown(with: event)
    }
}

// ✅ GOOD: Validating menu items
extension ViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(delete(_:)):
            return selectedItems.count > 0
        case #selector(duplicate(_:)):
            return selectedItems.count == 1
        default:
            return true
        }
    }
}
```

## Animations in AppKit

```swift
// ✅ GOOD: NSAnimationContext
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.3
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    view.animator().alphaValue = 0.5
    view.animator().frame = newFrame
}

// ✅ GOOD: Core Animation layers
view.wantsLayer = true
view.layer?.add(animation, forKey: "transform")
```

## AppKit + SwiftUI Integration

```swift
// ✅ GOOD: Hosting SwiftUI in AppKit
final class SwiftUIHostingController: NSViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func loadView() {
        let swiftUIView = ContentView()
        let hostingView = NSHostingView(rootView: swiftUIView)
        self.view = hostingView
    }
}

// ✅ GOOD: Embedding AppKit in SwiftUI (see swiftui-macos.md)
```

## Modern AppKit Checklist

- [ ] Use NSVisualEffectView for Liquid Glass effects
- [ ] Implement transparent window backgrounds
- [ ] Use Auto Layout constraints
- [ ] Follow MVVM pattern with ViewModels
- [ ] Use Combine for reactive bindings
- [ ] Implement proper responder chain
- [ ] Support dark mode and accent colors
- [ ] Use NSToolbar for window toolbars
- [ ] Implement NSSplitViewController for sidebars
- [ ] Support keyboard shortcuts and menu validation
- [ ] Use smooth animations
- [ ] Integrate SwiftUI where beneficial

## Resources

- [AppKit Documentation](https://developer.apple.com/documentation/appkit)
- [NSVisualEffectView Guide](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [Modern AppKit Patterns](https://developer.apple.com/videos/)
