# Menu Bar Apps

Building menu bar applications with MenuBarExtra (SwiftUI) and NSStatusItem (AppKit). Covers background-only apps, popover menus, and hybrid architectures.

## MenuBarExtra (SwiftUI, macOS 13+)

The modern, declarative way to build menu bar apps.

### Simple Menu

```swift
@main
struct MyMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("MyApp", systemImage: "star.fill") {
            Button("Open Dashboard") {
                // Action
            }
            Button("Check for Updates") {
                // Action
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
```

### Window-Style Popover

For richer UIs, use `.menuBarExtraStyle(.window)`:

```swift
@main
struct StatusApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Status", systemImage: appState.statusIcon) {
            StatusPopoverView()
                .environment(appState)
                .frame(width: 320, height: 400)
        }
        .menuBarExtraStyle(.window)

        // Optional: main window
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(appState)
        }
    }
}

struct StatusPopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("System Status")
                    .font(.headline)
                Spacer()
                Button("Settings", systemImage: "gear") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Content
            ForEach(appState.statusItems) { item in
                StatusRow(item: item)
            }

            Divider()

            // Footer
            HStack {
                Text("Last updated: \(appState.lastUpdate.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") {
                    Task { await appState.refresh() }
                }
                .controlSize(.small)
            }
        }
        .padding()
    }
}
```

### Dynamic Icon

Update the menu bar icon based on state:

```swift
@Observable class AppState {
    var isConnected = false
    var unreadCount = 0

    var statusIcon: String {
        if !isConnected { return "wifi.slash" }
        if unreadCount > 0 { return "bell.badge.fill" }
        return "bell.fill"
    }
}

// The icon updates automatically when properties change
MenuBarExtra("Status", systemImage: appState.statusIcon) { ... }
```

### Dismissing the Menu After Actions

The menu should dismiss after the user clicks an action item:

```swift
struct MenuView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Main Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            dismiss()  // Dismiss after action
        }
    }
}
```

## NSStatusItem (AppKit)

For more control over the menu bar item, use AppKit's NSStatusItem directly.

### Basic Setup

```swift
class StatusBarController {
    private var statusItem: NSStatusItem?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "MyApp")
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // Reset so left-click works again
    }
}
```

### Popover with SwiftUI Content

```swift
class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "MyApp")
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient  // Auto-dismiss when clicking outside
        popover?.contentViewController = NSHostingController(
            rootView: PopoverContentView()
        )
    }

    @objc func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

## Background-Only App Architecture

A menu bar app with no Dock icon and no main window:

### Info.plist Configuration

```xml
<!-- Hide from Dock -->
<key>LSUIElement</key>
<true/>
```

### SwiftUI Approach

```swift
@main
struct BackgroundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("MyUtil", systemImage: "gearshape") {
            MenuView()
        }
        .menuBarExtraStyle(.window)

        // Settings window (opens on demand)
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No main window to show
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking Dock icon (if visible) doesn't open a window
        false
    }
}
```

### Activation Policy Switching

Toggle between Dock and menu-bar-only mode:

```swift
@Observable class AppMode {
    var showInDock: Bool = false {
        didSet {
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        }
    }
}
```

## Common Patterns

### Status Item with Badge Count

```swift
func updateBadge(count: Int) {
    guard let button = statusItem?.button else { return }
    if count > 0 {
        button.title = " \(count)"
        button.imagePosition = .imageLeading
    } else {
        button.title = ""
        button.imagePosition = .imageOnly
    }
}
```

### Opening Windows from Menu Bar

```swift
// Problem: openWindow() opens the window but doesn't bring it to front
// Solution: activate the app after opening

Button("Show Dashboard") {
    openWindow(id: "dashboard")
    NSApp.activate(ignoringOtherApps: true)
    dismiss()  // Close the menu
}
```

### Global Keyboard Shortcut

Register a hotkey to toggle the menu bar popover:

```swift
import Carbon

class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4D794170) // "MyAp"
        hotKeyID.id = 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            // Handler called on hotkey press
            return noErr
        }, 1, &eventType, nil, nil)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                           GetApplicationEventTarget(), 0, &hotkeyRef)
    }
}
```

## Best Practices

1. **Use MenuBarExtra for new apps** - Simpler, declarative, less code
2. **Always provide a Quit option** - Users expect it in menu bar apps
3. **Dismiss the menu after actions** - Standard macOS behavior
4. **Activate the app when opening windows** - Use `NSApp.activate(ignoringOtherApps: true)`
5. **Keep menus lightweight** - Don't do heavy computation in the menu view
6. **Support keyboard shortcuts** - Add `.keyboardShortcut()` to menu items
7. **Use SF Symbols for the status item** - Automatic template rendering for dark/light menu bar
