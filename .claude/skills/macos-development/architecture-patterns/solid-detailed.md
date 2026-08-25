# SOLID Principles in Detail

Real-world Swift examples for each SOLID principle with refactoring patterns. Focus on practical application, not academic theory.

## Single Responsibility Principle (SRP)

**A type should have one reason to change.**

### Violation

```swift
class DocumentManager {
    var documents: [Document] = []

    // Responsibility 1: Document CRUD
    func createDocument(title: String) -> Document { ... }
    func deleteDocument(_ doc: Document) { ... }

    // Responsibility 2: Persistence
    func saveToFile(_ doc: Document) throws { ... }
    func loadFromFile(_ url: URL) throws -> Document { ... }

    // Responsibility 3: Export
    func exportToPDF(_ doc: Document) -> Data { ... }
    func exportToHTML(_ doc: Document) -> String { ... }

    // Responsibility 4: Search
    func search(query: String) -> [Document] { ... }
}
```

### Refactored

```swift
// Each class has one reason to change
@Observable class DocumentStore {
    var documents: [Document] = []
    func create(title: String) -> Document { ... }
    func delete(_ doc: Document) { ... }
}

struct DocumentPersistence {
    func save(_ doc: Document, to url: URL) throws { ... }
    func load(from url: URL) throws -> Document { ... }
}

struct DocumentExporter {
    func toPDF(_ doc: Document) -> Data { ... }
    func toHTML(_ doc: Document) -> String { ... }
}

struct DocumentSearch {
    func search(_ documents: [Document], query: String) -> [Document] { ... }
}
```

### When to Bend SRP
- **Tiny apps**: A single ViewModel handling fetch + display is fine for 1-2 screens
- **Data models**: `@Model` classes naturally combine data + persistence — that's SwiftData's design
- **Value types**: Small structs with 2-3 responsibilities are often clearer than over-split types

## Open/Closed Principle (OCP)

**Open for extension, closed for modification.**

Use protocols and enums to add behavior without changing existing code.

### Violation

```swift
class ReportGenerator {
    func generate(type: String, data: ReportData) -> String {
        switch type {
        case "pdf": return generatePDF(data)
        case "html": return generateHTML(data)
        case "csv": return generateCSV(data)
        // Adding "markdown" requires modifying this class
        default: fatalError()
        }
    }
}
```

### Refactored

```swift
protocol ReportFormat {
    func generate(from data: ReportData) -> String
}

struct PDFReport: ReportFormat {
    func generate(from data: ReportData) -> String { ... }
}

struct HTMLReport: ReportFormat {
    func generate(from data: ReportData) -> String { ... }
}

// Adding Markdown requires no changes to existing code
struct MarkdownReport: ReportFormat {
    func generate(from data: ReportData) -> String { ... }
}

class ReportGenerator {
    func generate(format: ReportFormat, data: ReportData) -> String {
        format.generate(from: data)
    }
}
```

### Swift-Specific OCP: Protocol Extensions

```swift
protocol Cacheable {
    var cacheKey: String { get }
    var cacheExpiry: TimeInterval { get }
}

// Default behavior via extension — open for override, closed for modification
extension Cacheable {
    var cacheExpiry: TimeInterval { 300 } // 5 minutes default
}
```

## Liskov Substitution Principle (LSP)

**Subtypes must be substitutable for their base types without breaking behavior.**

### Violation

```swift
class FileStorage {
    func save(_ data: Data, to path: String) throws { ... }
    func load(from path: String) throws -> Data { ... }
    func delete(at path: String) throws { ... }
}

class ReadOnlyStorage: FileStorage {
    override func save(_ data: Data, to path: String) throws {
        throw StorageError.readOnly  // Breaks the contract!
    }
    override func delete(at path: String) throws {
        throw StorageError.readOnly  // Breaks the contract!
    }
}
```

### Refactored

```swift
protocol ReadableStorage {
    func load(from path: String) throws -> Data
}

protocol WritableStorage: ReadableStorage {
    func save(_ data: Data, to path: String) throws
    func delete(at path: String) throws
}

struct FileStorage: WritableStorage {
    func load(from path: String) throws -> Data { ... }
    func save(_ data: Data, to path: String) throws { ... }
    func delete(at path: String) throws { ... }
}

struct BundleStorage: ReadableStorage {
    func load(from path: String) throws -> Data { ... }
    // No save/delete — not part of the contract
}
```

## Interface Segregation Principle (ISP)

**Clients shouldn't depend on methods they don't use.**

### Violation

```swift
protocol DataService {
    func fetchUsers() async throws -> [User]
    func fetchPosts() async throws -> [Post]
    func fetchComments() async throws -> [Comment]
    func createUser(_ user: User) async throws
    func createPost(_ post: Post) async throws
    func deleteUser(_ id: UUID) async throws
}

// UserListView only needs fetchUsers but depends on the entire protocol
struct UserListViewModel {
    let service: DataService  // Forced to depend on posts, comments, etc.
}
```

### Refactored

```swift
protocol UserFetching {
    func fetchUsers() async throws -> [User]
}

protocol UserManaging: UserFetching {
    func createUser(_ user: User) async throws
    func deleteUser(_ id: UUID) async throws
}

protocol PostFetching {
    func fetchPosts() async throws -> [Post]
}

// A single concrete type can conform to all
class APIService: UserManaging, PostFetching {
    func fetchUsers() async throws -> [User] { ... }
    func createUser(_ user: User) async throws { ... }
    func deleteUser(_ id: UUID) async throws { ... }
    func fetchPosts() async throws -> [Post] { ... }
}

// Each consumer depends only on what it needs
struct UserListViewModel {
    let userFetcher: UserFetching  // Minimal dependency
}
```

## Dependency Inversion Principle (DIP)

**High-level modules shouldn't depend on low-level modules. Both should depend on abstractions.**

### Violation

```swift
class AnalyticsViewModel {
    let tracker = FirebaseAnalytics()  // Direct dependency on concrete type

    func trackEvent(_ name: String) {
        tracker.logEvent(name, parameters: nil)
    }
}
```

### Refactored

```swift
protocol AnalyticsTracking {
    func trackEvent(_ name: String, properties: [String: Any])
}

struct FirebaseTracker: AnalyticsTracking {
    func trackEvent(_ name: String, properties: [String: Any]) { ... }
}

struct MockTracker: AnalyticsTracking {
    var trackedEvents: [(String, [String: Any])] = []
    mutating func trackEvent(_ name: String, properties: [String: Any]) {
        trackedEvents.append((name, properties))
    }
}

@Observable class AnalyticsViewModel {
    private let tracker: AnalyticsTracking

    init(tracker: AnalyticsTracking) {
        self.tracker = tracker
    }
}
```

### DIP with SwiftUI Environment

```swift
// Define the abstraction
protocol ImageLoader {
    func load(url: URL) async throws -> NSImage
}

// Environment key
struct ImageLoaderKey: EnvironmentKey {
    static let defaultValue: ImageLoader = URLSessionImageLoader()
}

extension EnvironmentValues {
    var imageLoader: ImageLoader {
        get { self[ImageLoaderKey.self] }
        set { self[ImageLoaderKey.self] = newValue }
    }
}

// Inject via environment
ContentView()
    .environment(\.imageLoader, CachedImageLoader())

// Consume in views
struct ThumbnailView: View {
    @Environment(\.imageLoader) private var imageLoader
}
```

## Pragmatic SOLID

SOLID principles are guidelines, not laws. Apply them proportionally:

| App Size | SRP | OCP | LSP | ISP | DIP |
|----------|-----|-----|-----|-----|-----|
| Prototype | Loose | Skip | Follow | Skip | Skip |
| Small (1-3 screens) | Moderate | Where natural | Follow | Light | For testing |
| Medium (4-10 screens) | Strict | For extensible areas | Follow | Moderate | For services |
| Large (10+ screens) | Strict | Everywhere | Follow | Strict | Everywhere |

**Rules of thumb:**
- If a class is under 100 lines, SRP violations are probably fine
- If you'll never extend a type, OCP is unnecessary overhead
- LSP should always be followed — it prevents bugs
- ISP matters most at module boundaries
- DIP matters most for testability and swappable implementations
