# macOS Tahoe Human Interface Guidelines

Platform-specific design guidelines for macOS 26 (Tahoe).

## Window Management

### Window Chrome

```swift
// ✅ GOOD: Modern window with unified toolbar
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}

// ✅ GOOD: Toolbar with standard controls
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("New") {
                    // Action
                }
            }
        }
    }
}

// ❌ BAD: Custom window chrome (avoid unless necessary)
```

### Window Sizing and Constraints

```swift
// ✅ GOOD: Appropriate size constraints
WindowGroup {
    ContentView()
}
.defaultSize(width: 800, height: 600)
.windowResizability(.contentSize)  // or .automatic

// Document windows
DocumentGroup(newDocument: { MyDocument() }) { file in
    DocumentView(document: file.$document)
}
.defaultSize(width: 1024, height: 768)
```

### Multiple Windows

```swift
// ✅ GOOD: Supporting multiple windows
@main
struct MyApp: App {
    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    // Create new window
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Settings window
        Settings {
            SettingsView()
        }
    }
}
```

## Toolbar Design

### Standard Toolbar Items

```swift
// ✅ GOOD: Well-organized toolbar
.toolbar(id: "main") {
    // Leading items
    ToolbarItem(id: "sidebar", placement: .navigation) {
        Button(action: toggleSidebar) {
            Label("Sidebar", systemImage: "sidebar.left")
        }
    }

    // Flexible space
    ToolbarItem(placement: .automatic) {
        Spacer()
    }

    // Center items (search, filters)
    ToolbarItem(id: "search", placement: .automatic) {
        TextField("Search", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
    }

    // Trailing items
    ToolbarItem(id: "share", placement: .primaryAction) {
        ShareLink(item: currentItem)
    }

    ToolbarItem(id: "add", placement: .primaryAction) {
        Button(action: addNew) {
            Label("Add", systemImage: "plus")
        }
    }
}
.toolbarRole(.editor)
```

### Customizable Toolbars

```swift
// ✅ GOOD: Allow toolbar customization
.toolbar(id: "customizable-toolbar") {
    ToolbarItem(id: "action1", placement: .automatic, showsByDefault: true) {
        Button("Action 1") { }
    }

    ToolbarItem(id: "action2", placement: .automatic, showsByDefault: false) {
        Button("Action 2") { }
    }
}
.toolbarRole(.editor)
```

## Menu Bar Organization

### Standard Menu Structure

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Replace standard commands
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    // Action
                }
                .keyboardShortcut("n")
            }

            // Add after File menu
            CommandGroup(after: .newItem) {
                Button("Import...") {
                    // Action
                }
                .keyboardShortcut("i")
            }

            // Custom menu
            CommandMenu("Tools") {
                Button("Refresh") {
                    // Action
                }
                .keyboardShortcut("r")

                Divider()

                Button("Export...") {
                    // Action
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
```

### Keyboard Shortcuts

```swift
// ✅ GOOD: Standard keyboard shortcuts
.keyboardShortcut("n", modifiers: .command)           // ⌘N
.keyboardShortcut("s", modifiers: .command)           // ⌘S
.keyboardShortcut("w", modifiers: .command)           // ⌘W
.keyboardShortcut("z", modifiers: .command)           // ⌘Z
.keyboardShortcut("z", modifiers: [.command, .shift]) // ⇧⌘Z

// ⚠️ Don't override system shortcuts (⌘Q, ⌘H, ⌘M, ⌘Tab, etc.)

// ✅ GOOD: Function key shortcuts
.keyboardShortcut(.return, modifiers: .command)       // ⌘↩
.keyboardShortcut(.delete, modifiers: .command)       // ⌘⌫
.keyboardShortcut(.escape)                            // ⎋
```

## Navigation Patterns

### Sidebar Navigation

```swift
// ✅ GOOD: Three-column layout
struct ContentView: View {
    @State private var selectedCategory: Category?
    @State private var selectedItem: Item?

    var body: some View {
        NavigationSplitView {
            // Primary sidebar
            List(categories, selection: $selectedCategory) { category in
                Label(category.name, systemImage: category.icon)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            // Secondary sidebar
            if let category = selectedCategory {
                List(category.items, selection: $selectedItem) { item in
                    Text(item.name)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            // Detail view
            if let item = selectedItem {
                ItemDetailView(item: item)
            } else {
                Text("Select an item")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// ✅ GOOD: Two-column layout
NavigationSplitView {
    List(items, selection: $selectedItem) { item in
        NavigationLink(value: item) {
            Label(item.name, systemImage: item.icon)
        }
    }
} detail: {
    if let item = selectedItem {
        DetailView(item: item)
    }
}
```

### Tab Navigation

```swift
// ✅ GOOD: TabView for distinct sections
TabView {
    DashboardView()
        .tabItem {
            Label("Dashboard", systemImage: "chart.bar")
        }

    ProjectsView()
        .tabItem {
            Label("Projects", systemImage: "folder")
        }

    SettingsView()
        .tabItem {
            Label("Settings", systemImage: "gear")
        }
}
.frame(minWidth: 600, minHeight: 400)
```

## Control Patterns

### Buttons

```swift
// ✅ GOOD: Appropriate button styles
Button("Primary Action") {
    // Action
}
.buttonStyle(.borderedProminent)  // Primary CTA

Button("Secondary Action") {
    // Action
}
.buttonStyle(.bordered)  // Secondary action

Button("Cancel") {
    // Action
}
.buttonStyle(.borderless)  // Tertiary action

// ✅ GOOD: Destructive actions
Button("Delete", role: .destructive) {
    // Action
}
.buttonStyle(.bordered)
```

### Forms and Fields

```swift
// ✅ GOOD: Form layout
Form {
    Section("General") {
        TextField("Name", text: $name)
        TextField("Email", text: $email)
            .textContentType(.emailAddress)

        Picker("Role", selection: $role) {
            ForEach(roles) { role in
                Text(role.name).tag(role)
            }
        }
    }

    Section("Preferences") {
        Toggle("Enable notifications", isOn: $notificationsEnabled)
        Toggle("Dark mode", isOn: $darkModeEnabled)

        Picker("Theme", selection: $theme) {
            Text("Light").tag(Theme.light)
            Text("Dark").tag(Theme.dark)
            Text("Auto").tag(Theme.auto)
        }
        .pickerStyle(.segmented)
    }

    Section {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
.formStyle(.grouped)
.frame(minWidth: 400, minHeight: 300)
```

### Lists and Tables

```swift
// ✅ GOOD: List with context menu
List(items, selection: $selection) { item in
    ItemRow(item: item)
        .contextMenu {
            Button("Open") { openItem(item) }
            Button("Duplicate") { duplicateItem(item) }
            Divider()
            Button("Delete", role: .destructive) {
                deleteItem(item)
            }
        }
}
.listStyle(.sidebar)

// ✅ GOOD: Table view
Table(items, selection: $selection) {
    TableColumn("Name") { item in
        Text(item.name)
    }
    TableColumn("Date") { item in
        Text(item.date, style: .date)
    }
    TableColumn("Size") { item in
        Text(item.size, format: .byteCount(style: .file))
    }
}
```

## Alerts and Sheets

### Alerts

```swift
// ✅ GOOD: Simple alert
.alert("Delete Item?", isPresented: $showingAlert) {
    Button("Cancel", role: .cancel) { }
    Button("Delete", role: .destructive) {
        deleteItem()
    }
} message: {
    Text("This action cannot be undone.")
}

// ✅ GOOD: Confirmation dialog
.confirmationDialog("Export Options", isPresented: $showingExport) {
    Button("PDF") { exportPDF() }
    Button("HTML") { exportHTML() }
    Button("Markdown") { exportMarkdown() }
    Button("Cancel", role: .cancel) { }
}
```

### Sheets and Popovers

```swift
// ✅ GOOD: Sheet presentation
.sheet(isPresented: $showingSheet) {
    SettingsView()
        .frame(minWidth: 500, minHeight: 400)
}

// ✅ GOOD: Popover
.popover(isPresented: $showingPopover) {
    FilterOptionsView()
        .frame(width: 300)
}
```

## Touch Bar (Legacy)

Touch Bar is removed on newer Macs — don't rely on it for essential functionality; provide alternative toolbar/menu access.

## macOS Tahoe-Specific Features

### Spotlight Integration

```swift
// ✅ GOOD: Make content searchable
// Implement NSUserActivity for Spotlight indexing
func makeUserActivity() -> NSUserActivity {
    let activity = NSUserActivity(activityType: "com.app.viewArticle")
    activity.title = "View Article"
    activity.userInfo = ["articleID": article.id.uuidString]
    activity.isEligibleForSearch = true

    let attributes = CSSearchableItemAttributeSet(itemContentType: kUTTypeContent as String)
    attributes.title = article.title
    attributes.contentDescription = article.excerpt
    activity.contentAttributeSet = attributes

    return activity
}
```

### Phone App on Mac

```swift
// ✅ GOOD: Support phone links for Phone app integration
Link("Call Support", destination: URL(string: "tel:1-800-555-0123")!)

// Continuity features automatically handled by system
```

## Platform Conventions Checklist

- [ ] Use standard window chrome (unified toolbar)
- [ ] Appropriate window size constraints
- [ ] Support multiple windows (if applicable)
- [ ] Well-organized toolbar with standard items
- [ ] Standard menu structure with shortcuts
- [ ] Keyboard shortcut consistency
- [ ] Appropriate navigation pattern (sidebar, tabs)
- [ ] Platform-standard controls and buttons
- [ ] Proper alert and dialog usage
- [ ] Context menus for list items
- [ ] Spotlight integration (if applicable)
- [ ] No reliance on Touch Bar

## Resources

- [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/macos)
- [macOS Tahoe Design Resources](https://developer.apple.com/design/resources/)
- [WWDC 2025: What's new in macOS](https://developer.apple.com/videos/)
