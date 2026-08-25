# Modular Design

Swift Package Manager organization, feature modules, and code organization strategies for macOS applications.

## Project Organization Strategies

### Strategy 1: Group by Feature (Recommended for Most Apps)

```
MyApp/
├── Features/
│   ├── Documents/
│   │   ├── DocumentListView.swift
│   │   ├── DocumentDetailView.swift
│   │   ├── DocumentViewModel.swift
│   │   └── DocumentModel.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── GeneralSettingsTab.swift
│   │   ├── AppearanceSettingsTab.swift
│   │   └── SettingsViewModel.swift
│   └── Search/
│       ├── SearchView.swift
│       ├── SearchResultRow.swift
│       └── SearchViewModel.swift
├── Core/
│   ├── Models/
│   │   └── SharedModels.swift
│   ├── Services/
│   │   ├── PersistenceService.swift
│   │   └── NetworkService.swift
│   └── Extensions/
│       └── Date+Formatting.swift
├── App/
│   ├── MyApp.swift
│   ├── ContentView.swift
│   └── AppState.swift
└── Resources/
    └── Assets.xcassets
```

**Pros**: Related files together, easy to find things, scales well
**Cons**: Shared dependencies can create circular references

### Strategy 2: Group by Layer

```
MyApp/
├── Views/
│   ├── DocumentListView.swift
│   ├── DocumentDetailView.swift
│   ├── SettingsView.swift
│   └── SearchView.swift
├── ViewModels/
│   ├── DocumentViewModel.swift
│   ├── SettingsViewModel.swift
│   └── SearchViewModel.swift
├── Models/
│   ├── Document.swift
│   ├── Settings.swift
│   └── SearchResult.swift
├── Services/
│   ├── DocumentRepository.swift
│   └── SearchService.swift
└── App/
    └── MyApp.swift
```

**Pros**: Clear separation of concerns, familiar to MVVM developers
**Cons**: Related files scattered across folders, doesn't scale as well

### Recommendation
- **Small apps (< 15 files)**: Group by layer — simpler, less folder nesting
- **Medium+ apps (15+ files)**: Group by feature — better discoverability and modularity

## Swift Package Manager Modularization

For large apps, extract code into local Swift packages for build isolation, clear API boundaries, and faster incremental builds.

### Package Structure

```
MyApp/
├── MyApp.xcodeproj
├── MyApp/                          # App target (thin shell)
│   ├── MyApp.swift
│   └── ContentView.swift
└── Packages/
    ├── Core/                       # Shared models, protocols, utilities
    │   ├── Package.swift
    │   └── Sources/Core/
    │       ├── Models/
    │       ├── Protocols/
    │       └── Extensions/
    ├── DocumentFeature/            # Document management feature
    │   ├── Package.swift
    │   └── Sources/DocumentFeature/
    │       ├── DocumentListView.swift
    │       ├── DocumentDetailView.swift
    │       └── DocumentViewModel.swift
    ├── Persistence/                # Data layer
    │   ├── Package.swift
    │   └── Sources/Persistence/
    │       ├── SwiftDataModels/
    │       └── Repositories/
    └── Networking/                  # Network layer
        ├── Package.swift
        └── Sources/Networking/
            ├── APIClient.swift
            └── Endpoints/
```

### Package.swift for a Feature Module

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocumentFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DocumentFeature", targets: ["DocumentFeature"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(
            name: "DocumentFeature",
            dependencies: ["Core", "Persistence"]
        ),
        .testTarget(
            name: "DocumentFeatureTests",
            dependencies: ["DocumentFeature"]
        ),
    ]
)
```

### Dependency Graph Rules

1. **Service layers** (Persistence, Networking) depend on Core only
2. **Feature modules** depend on Core and relevant service layers
3. **App target** depends on all feature modules and wires them together

```
App → DocumentFeature → Persistence → Core
    → SettingsFeature → Core
    → SearchFeature → Networking → Core
```

## Access Control for Module Boundaries

Use Swift's access levels to enforce clean module APIs:

```swift
// In Persistence module

// Public: API surface used by other modules
public protocol TaskRepository: Sendable {
    func fetchAll() async throws -> [Task]
    func save(_ task: Task) async throws
}

// Public: consumers need to create this
public struct SwiftDataTaskRepository: TaskRepository {
    public init(modelContext: ModelContext) { ... }
    public func fetchAll() async throws -> [Task] { ... }
    public func save(_ task: Task) async throws { ... }
}

// Internal: implementation detail, not visible outside module
struct CacheManager {
    func invalidate() { ... }
}

// Package: visible to other targets in same package, not outside
package struct MigrationHelper {
    package func migrate(from oldSchema: Schema) { ... }
}
```

### Access Level Summary

| Level | Visible To |
|-------|-----------|
| `private` | Enclosing declaration only |
| `fileprivate` | Same source file |
| `internal` (default) | Same module/target |
| `package` | Same package |
| `public` | Any importing module |
| `open` | Any module (can subclass/override) |

## DRY: Reducing Duplication

### Extract Shared Views

```swift
// Reusable components in Core or a shared UI module
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
    }
}

struct LoadingOverlay: View {
    let isLoading: Bool
    var body: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        }
    }
}
```

### Extract Common Logic into Extensions

```swift
// Instead of duplicating date formatting across features
extension Date {
    var relativeDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    var shortDisplay: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
```

### Protocol with Default Implementations

```swift
protocol Searchable {
    var searchableText: String { get }
}

extension Array where Element: Searchable {
    func search(query: String) -> [Element] {
        guard !query.isEmpty else { return self }
        let lowered = query.lowercased()
        return filter { $0.searchableText.lowercased().contains(lowered) }
    }
}

// Any model can opt-in
struct Document: Searchable {
    let title: String
    let content: String
    var searchableText: String { "\(title) \(content)" }
}

struct Contact: Searchable {
    let name: String
    let email: String
    var searchableText: String { "\(name) \(email)" }
}
```

## When to Modularize

| Signal | Action |
|--------|--------|
| Build times getting slow | Extract stable code into packages |
| Multiple developers working on same files | Split into feature modules |
| Want to share code between app and extension | Extract into shared package |
| Tests require the full app to compile | Extract testable code into packages |
| Hard to find files | Reorganize by feature |

## Testing Across Modules

Each package has its own test target with fast, isolated tests:

```swift
// In DocumentFeatureTests/
@testable import DocumentFeature
import Core

struct MockTaskRepository: TaskRepository {
    var tasks: [Task] = []
    func fetchAll() async throws -> [Task] { tasks }
    func save(_ task: Task) async throws { }
}

@Test func testFilteredTasks() async {
    let repo = MockTaskRepository(tasks: [
        Task(id: UUID(), title: "Active", isCompleted: false),
        Task(id: UUID(), title: "Done", isCompleted: true),
    ])
    let viewModel = TaskListViewModel(repository: repo)
    await viewModel.loadTasks()

    viewModel.filterOption = .active
    #expect(viewModel.filteredTasks.count == 1)
    #expect(viewModel.filteredTasks[0].title == "Active")
}
```
