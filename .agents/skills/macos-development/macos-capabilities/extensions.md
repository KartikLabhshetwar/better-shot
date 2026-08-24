# System Extensions

App extensions, system extensions, and XPC services for extending macOS capabilities.

## App Extension Types

| Extension Type | Purpose | Host App |
|---------------|---------|----------|
| Share Extension | Share content to your app | Share sheet |
| Action Extension | Transform content in-place | Any app with action menu |
| Finder Sync | Badges, toolbar items, context menu in Finder | Finder |
| Quick Look Preview | Preview custom file types | Finder, Mail, etc. |
| Spotlight Importer | Index custom file types for search | Spotlight |
| Widget (WidgetKit) | Desktop/Notification Center widgets | System |
| Intents/App Intents | Siri, Shortcuts, Spotlight actions | System |
| Photo Editing | Edit photos in Photos.app | Photos |
| Network Extension | VPN, content filter, DNS proxy | System |
| Endpoint Security | Process monitoring, file access control | System |

## Share Extension

Allow users to share content from other apps into yours:

### Setup
1. File > New > Target > Share Extension
2. Configure supported content types in Info.plist

```swift
// ShareViewController.swift
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: NSViewController {
    override func loadView() {
        let hostingView = NSHostingView(rootView: ShareView(extensionContext: extensionContext))
        self.view = hostingView
    }
}

struct ShareView: View {
    let extensionContext: NSExtensionContext?
    @State private var sharedText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Save to MyApp")
                .font(.headline)
            TextEditor(text: $sharedText)
                .frame(height: 100)
            HStack {
                Button("Cancel") { cancel() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
        .task { await loadSharedContent() }
    }

    func loadSharedContent() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
                    sharedText = text ?? ""
                }
            }
        }
    }

    func save() {
        // Save via App Group shared container or UserDefaults suite
        let defaults = UserDefaults(suiteName: "group.com.example.myapp")
        var items = defaults?.stringArray(forKey: "sharedItems") ?? []
        items.append(sharedText)
        defaults?.set(items, forKey: "sharedItems")

        extensionContext?.completeRequest(returningItems: nil)
    }

    func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "user", code: 0))
    }
}
```

## Finder Sync Extension

Add badges, contextual menus, and toolbar buttons in Finder:

```swift
import FinderSync

class FinderSyncExtension: FIFinderSync {
    override init() {
        super.init()
        // Monitor these directories
        let monitoredFolder = URL(fileURLWithPath: "/Users/Shared/MyApp")
        FIFinderSyncController.default().directoryURLs = [monitoredFolder]
    }

    // Badge icons for file status
    override func requestBadgeIdentifier(for url: URL) {
        let status = getFileStatus(url)
        switch status {
        case .synced: FIFinderSyncController.default().setBadgeIdentifier("synced", for: url)
        case .syncing: FIFinderSyncController.default().setBadgeIdentifier("syncing", for: url)
        case .error: FIFinderSyncController.default().setBadgeIdentifier("error", for: url)
        }
    }

    // Context menu items
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "MyApp")
        menu.addItem(withTitle: "Share via MyApp", action: #selector(shareFile(_:)), keyEquivalent: "")
        return menu
    }

    @objc func shareFile(_ sender: Any) {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        // Handle selected files
    }
}
```

## Quick Look Preview Extension

Preview custom file types in Finder and other apps:

```swift
import Cocoa
import Quartz
import QuickLookUI

class PreviewViewController: NSViewController, QLPreviewingController {
    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let content = try MyFileFormat.parse(data)

        let hostingView = NSHostingView(rootView: FilePreviewView(content: content))
        view.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
```

## XPC Services

Separate privilege domains within your app. XPC services run in their own process with their own sandbox.

### When to Use XPC
Isolate crash-prone or privileged work in its own process, share functionality between app and extensions, or run long tasks that shouldn't crash the main app.

### Setting Up an XPC Service

1. File > New > Target > XPC Service

```swift
// XPC Protocol - shared between app and service
@objc protocol MyServiceProtocol {
    func processFile(at path: String, reply: @escaping (Data?, Error?) -> Void)
    func getStatus(reply: @escaping (String) -> Void)
}

// XPC Service implementation
class MyService: NSObject, MyServiceProtocol {
    func processFile(at path: String, reply: @escaping (Data?, Error?) -> Void) {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let processed = transform(data)
            reply(processed, nil)
        } catch {
            reply(nil, error)
        }
    }

    func getStatus(reply: @escaping (String) -> Void) {
        reply("ready")
    }
}

// Service delegate
class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MyServiceProtocol.self)
        connection.exportedObject = MyService()
        connection.resume()
        return true
    }
}

// main.swift for the XPC service
let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
```

### Connecting from the App

```swift
class XPCClient {
    private var connection: NSXPCConnection?

    func connect() -> MyServiceProtocol? {
        let connection = NSXPCConnection(serviceName: "com.example.myapp.xpcservice")
        connection.remoteObjectInterface = NSXPCInterface(with: MyServiceProtocol.self)
        connection.resume()
        self.connection = connection

        return connection.remoteObjectProxyWithErrorHandler { error in
            print("XPC error: \(error)")
        } as? MyServiceProtocol
    }

    func processFile(at path: String) async throws -> Data {
        guard let service = connect() else { throw XPCError.connectionFailed }
        return try await withCheckedThrowingContinuation { continuation in
            service.processFile(at: path) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: XPCError.noData) }
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
```

## App Groups (Sharing Data Between App and Extensions)

Share data between your main app and its extensions:

```swift
// 1. Add App Group entitlement to both app and extension
// com.apple.security.application-groups: ["group.com.example.myapp"]

// 2. Shared UserDefaults
let shared = UserDefaults(suiteName: "group.com.example.myapp")
shared?.set("value", forKey: "sharedKey")

// 3. Shared file container
let containerURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.com.example.myapp"
)

// 4. Shared SwiftData (macOS 14+)
let schema = Schema([MyModel.self])
let config = ModelConfiguration(
    groupContainer: .identifier("group.com.example.myapp")
)
let container = try ModelContainer(for: schema, configurations: config)
```

## Best Practices

1. **Minimal extension footprint** - Extensions have memory limits (varies by type)
2. **Handle extension lifecycle** - Extensions can be terminated at any time
3. **Test extensions independently** - Use separate scheme for extension targets
4. **Declare capabilities in Info.plist** - Extensions need explicit type declarations
