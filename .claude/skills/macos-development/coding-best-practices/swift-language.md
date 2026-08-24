# Swift Language Best Practices

Modern Swift 6+ language patterns and idioms for macOS development.

## Swift 6 Features

### Strict Concurrency Checking
```swift
// ✅ GOOD: Sendable conformance
struct User: Sendable {
    let id: UUID
    let name: String
}

// ❌ BAD: Mutable reference type without protection
class UserManager {
    var users: [User] = []  // Not thread-safe!
}

// ✅ GOOD: Use actor for mutable state
actor UserManager {
    private var users: [User] = []

    func addUser(_ user: User) {
        users.append(user)
    }
}
```

### Macro System
```swift
// ✅ Use macros for reducing boilerplate
import SwiftData

@Model
class Article {
    var title: String
    var content: String
    var publishedDate: Date
}

// Generates: Codable, Hashable, Observable, and more
```

### Typed Throws (Swift 6+)
```swift
// ✅ GOOD: Specific error types
enum NetworkError: Error {
    case invalidURL
    case timeout
    case serverError(Int)
}

func fetchData() throws(NetworkError) -> Data {
    // Implementation
}

// Usage with specific error handling
do {
    let data = try fetchData()
} catch let error as NetworkError {
    switch error {
    case .invalidURL:
        // Handle specific error
    case .timeout:
        // Handle timeout
    case .serverError(let code):
        // Handle server error
    }
}
```

## Value Types vs Reference Types

### Prefer Value Types
```swift
// ✅ GOOD: Value type for data
struct Settings {
    var theme: Theme
    var fontSize: Int
    var notifications: Bool
}

// ❌ BAD: Unnecessary class
class Settings {
    var theme: Theme
    var fontSize: Int
    var notifications: Bool
}
```

### When to Use Reference Types
```swift
// ✅ GOOD: Reference type for identity and shared state
final class DocumentController: ObservableObject {
    @Published var document: Document
    private let fileManager: FileManager

    // Complex lifecycle, needs identity
}

// ✅ GOOD: Reference type for inheritance
class BaseViewController: NSViewController {
    // AppKit requires inheritance
}
```

## Protocol-Oriented Programming

### Protocol Composition
```swift
// ✅ GOOD: Small, focused protocols
protocol Identifiable {
    var id: UUID { get }
}

protocol Timestamped {
    var createdAt: Date { get }
    var updatedAt: Date { get }
}

protocol Searchable {
    var searchableText: String { get }
}

// Compose protocols
struct Article: Identifiable, Timestamped, Searchable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var title: String
    var content: String

    var searchableText: String {
        "\(title) \(content)"
    }
}
```

### Protocol Extensions
```swift
// ✅ GOOD: Default implementations
protocol Validatable {
    func validate() throws
}

extension Validatable {
    func isValid() -> Bool {
        do {
            try validate()
            return true
        } catch {
            return false
        }
    }
}
```

### Protocol Witnesses (Avoid Runtime Type Checks)
```swift
// ❌ BAD: Runtime type checking
func process(_ item: Any) {
    if let article = item as? Article {
        print(article.title)
    } else if let video = item as? Video {
        print(video.title)
    }
}

// ✅ GOOD: Protocol-based approach
protocol Displayable {
    var displayTitle: String { get }
}

extension Article: Displayable {
    var displayTitle: String { title }
}

extension Video: Displayable {
    var displayTitle: String { title }
}

func process(_ item: Displayable) {
    print(item.displayTitle)
}
```

## Generics and Type Safety

### Generic Functions
```swift
// ✅ GOOD: Generic function with constraints
func findFirst<T: Collection>(
    in collection: T,
    matching predicate: (T.Element) -> Bool
) -> T.Element? where T.Element: Equatable {
    collection.first(where: predicate)
}
```

### Associated Types
```swift
// ✅ GOOD: Protocol with associated type
protocol Repository {
    associatedtype Entity

    func fetch(id: UUID) async throws -> Entity?
    func save(_ entity: Entity) async throws
    func delete(id: UUID) async throws
}

struct ArticleRepository: Repository {
    typealias Entity = Article

    func fetch(id: UUID) async throws -> Article? {
        // Implementation
    }

    func save(_ entity: Article) async throws {
        // Implementation
    }

    func delete(id: UUID) async throws {
        // Implementation
    }
}
```

## Optionals Best Practices

### Optional Binding
```swift
// ✅ GOOD: Guard for early exit
func processUser(_ user: User?) {
    guard let user else { return }
    // Work with unwrapped user
}

// ✅ GOOD: If-let for scoped usage
if let user = optionalUser {
    print(user.name)
}

// ❌ BAD: Force unwrapping
let name = user!.name  // Dangerous!

// ❌ BAD: Implicit unwrapping (use sparingly)
var user: User!
```

### Nil-Coalescing and Optional Chaining
```swift
// ✅ GOOD: Nil-coalescing with default
let displayName = user?.name ?? "Guest"

// ✅ GOOD: Optional chaining
let uppercasedName = user?.name?.uppercased()

// ✅ GOOD: Optional map and flatMap
let userID = optionalUser.map { $0.id }
```

## Property Wrappers

### Built-in Property Wrappers
```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var theme: String = "light"
    @State private var isEditing = false
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        // View implementation
    }
}
```

### Custom Property Wrappers
```swift
// ✅ GOOD: Custom property wrapper for validation
@propertyWrapper
struct Clamped<Value: Comparable> {
    private var value: Value
    private let range: ClosedRange<Value>

    var wrappedValue: Value {
        get { value }
        set { value = min(max(range.lowerBound, newValue), range.upperBound) }
    }

    init(wrappedValue: Value, _ range: ClosedRange<Value>) {
        self.range = range
        self.value = min(max(range.lowerBound, wrappedValue), range.upperBound)
    }
}

struct Settings {
    @Clamped(0...100) var volume: Int = 50
    @Clamped(10...72) var fontSize: Int = 14
}
```

## Result Builders

### SwiftUI-Style DSL
```swift
// ✅ GOOD: Result builder for custom DSL
@resultBuilder
struct MenuBuilder {
    static func buildBlock(_ components: MenuItem...) -> [MenuItem] {
        components
    }
}

struct MenuItem {
    let title: String
    let action: () -> Void
}

func createMenu(@MenuBuilder builder: () -> [MenuItem]) -> [MenuItem] {
    builder()
}

// Usage
let menu = createMenu {
    MenuItem(title: "Open") { /* action */ }
    MenuItem(title: "Save") { /* action */ }
    MenuItem(title: "Close") { /* action */ }
}
```

## Error Handling

### Swift Error Protocol
```swift
// ✅ GOOD: Well-structured error types
enum ValidationError: Error, LocalizedError {
    case emptyField(String)
    case invalidFormat(field: String, expected: String)
    case outOfRange(field: String, range: ClosedRange<Int>)

    var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "\(field) cannot be empty"
        case .invalidFormat(let field, let expected):
            return "\(field) has invalid format. Expected: \(expected)"
        case .outOfRange(let field, let range):
            return "\(field) must be between \(range.lowerBound) and \(range.upperBound)"
        }
    }
}
```

### Do-Catch Best Practices
```swift
// ✅ GOOD: Specific error handling
func saveDocument(_ document: Document) async {
    do {
        try await repository.save(document)
        showSuccess()
    } catch let error as ValidationError {
        showValidationError(error)
    } catch let error as NetworkError {
        showNetworkError(error)
    } catch {
        showGenericError(error)
    }
}

// ✅ GOOD: Using Result type
func loadDocument(id: UUID) -> Result<Document, Error> {
    do {
        let document = try repository.fetch(id: id)
        return .success(document)
    } catch {
        return .failure(error)
    }
}
```

## Collections and Algorithms

### Use Appropriate Collection Types
```swift
// ✅ GOOD: Array for ordered collections
var items: [Item] = []

// ✅ GOOD: Set for unique values and fast lookup
var uniqueIDs: Set<UUID> = []

// ✅ GOOD: Dictionary for key-value pairs
var usersByID: [UUID: User] = [:]

// ✅ GOOD: OrderedSet (Swift Collections) when order + uniqueness matter
import OrderedCollections
var orderedUniqueItems: OrderedSet<Item> = []
```

### Functional Programming Patterns
```swift
// ✅ GOOD: Map, filter, reduce
let activeUserNames = users
    .filter { $0.isActive }
    .map { $0.name }
    .sorted()

let totalScore = scores.reduce(0, +)

// ✅ GOOD: CompactMap for removing nils
let validURLs = strings.compactMap { URL(string: $0) }

// ✅ GOOD: FlatMap for flattening nested collections
let allTags = articles.flatMap { $0.tags }
```

## Memory Management

### Capture Lists in Closures
```swift
// ✅ GOOD: Weak self to avoid retain cycles
class DocumentViewController: NSViewController {
    private var document: Document

    func setupObserver() {
        NotificationCenter.default.addObserver(
            forName: .documentDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.updateUI()
        }
    }
}

// ✅ GOOD: Unowned when guaranteed to exist
class ChildView: NSView {
    unowned let parentController: ParentViewController

    func handleAction() {
        parentController.performAction()  // Safe: parent owns this view
    }
}
```

### Automatic Reference Counting (ARC)
```swift
// ❌ BAD: Strong reference cycle
class Author {
    var books: [Book] = []
}

class Book {
    var author: Author  // Strong reference creates cycle!
}

// ✅ GOOD: Break cycle with weak reference
class Author {
    var books: [Book] = []
}

class Book {
    weak var author: Author?  // Weak reference breaks cycle
}
```

## Swift 6 Migration Checklist

- [ ] Enable strict concurrency checking
- [ ] Mark types as `Sendable` where appropriate
- [ ] Use actors for mutable shared state
- [ ] Replace completion handlers with async/await
- [ ] Use typed throws for better error handling
- [ ] Adopt new Swift 6 features (macros, etc.)
- [ ] Remove deprecated APIs
- [ ] Update to use `@Observable` instead of `ObservableObject`

## Resources

- [Swift Language Guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/)
- [Swift Evolution Proposals](https://github.com/apple/swift-evolution)
- [WWDC 2024: What's new in Swift](https://developer.apple.com/videos/play/wwdc2024/)
