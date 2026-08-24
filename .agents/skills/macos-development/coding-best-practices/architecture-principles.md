# Architecture & Design Principles

SOLID principles, DRY, Clean Architecture, and design patterns for macOS development.

## SOLID Principles

### S - Single Responsibility Principle (SRP)

**Definition**: A class should have only one reason to change.

```swift
// ❌ BAD: Multiple responsibilities
class UserViewController: NSViewController {
    func loadUser() {
        // Network call
        let url = URL(string: "https://api.example.com/user")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            // Parsing
            let user = try? JSONDecoder().decode(User.self, from: data!)
            // Database saving
            try? self.saveToDatabase(user!)
            // UI update
            DispatchQueue.main.async {
                self.nameLabel.stringValue = user!.name
            }
        }.resume()
    }
}

// ✅ GOOD: Separated responsibilities
protocol UserRepository {
    func fetchUser(id: UUID) async throws -> User
}

class NetworkUserRepository: UserRepository {
    func fetchUser(id: UUID) async throws -> User {
        // Only handles network calls
    }
}

@MainActor
class UserViewModel: ObservableObject {
    @Published var user: User?
    private let repository: UserRepository

    init(repository: UserRepository) {
        self.repository = repository
    }

    func loadUser(id: UUID) async {
        do {
            user = try await repository.fetchUser(id: id)
        } catch {
            // Handle error
        }
    }
}

class UserViewController: NSViewController {
    private let viewModel: UserViewModel

    // Only handles UI updates
    func updateUI() {
        nameLabel.stringValue = viewModel.user?.name ?? ""
    }
}
```

### O - Open/Closed Principle (OCP)

**Definition**: Software entities should be open for extension but closed for modification.

```swift
// ❌ BAD: Must modify class to add new export formats
class DocumentExporter {
    func export(_ document: Document, format: String) throws -> Data {
        switch format {
        case "pdf":
            return exportToPDF(document)
        case "html":
            return exportToHTML(document)
        default:
            throw ExportError.unsupportedFormat
        }
    }
}

// ✅ GOOD: Open for extension via protocols
protocol DocumentExportStrategy {
    func export(_ document: Document) throws -> Data
}

class PDFExportStrategy: DocumentExportStrategy {
    func export(_ document: Document) throws -> Data {
        // PDF export logic
    }
}

class HTMLExportStrategy: DocumentExportStrategy {
    func export(_ document: Document) throws -> Data {
        // HTML export logic
    }
}

class MarkdownExportStrategy: DocumentExportStrategy {
    func export(_ document: Document) throws -> Data {
        // Markdown export logic - new format added without modifying existing code
    }
}

class DocumentExporter {
    func export(_ document: Document, using strategy: DocumentExportStrategy) throws -> Data {
        try strategy.export(document)
    }
}
```

### L - Liskov Substitution Principle (LSP)

**Definition**: Subtypes must be substitutable for their base types.

```swift
// ❌ BAD: Violates LSP - ReadOnlyDocument can't fulfill Document contract
class Document {
    var content: String

    func save() throws {
        // Save to disk
    }
}

class ReadOnlyDocument: Document {
    override func save() throws {
        throw DocumentError.readOnly  // Violates contract!
    }
}

// ✅ GOOD: Proper abstraction
protocol Readable {
    var content: String { get }
}

protocol Writable {
    var content: String { get set }
    func save() throws
}

class Document: Readable, Writable {
    var content: String

    func save() throws {
        // Save to disk
    }
}

class ReadOnlyDocument: Readable {
    let content: String  // Immutable, as expected

    init(content: String) {
        self.content = content
    }
}

// Now functions can require only what they need
func displayContent(_ document: Readable) {
    print(document.content)  // Works with both types
}

func editContent(_ document: Writable) {
    // Works only with writable documents
}
```

### I - Interface Segregation Principle (ISP)

**Definition**: Clients should not be forced to depend on interfaces they don't use.

```swift
// ❌ BAD: Fat protocol forcing unnecessary implementations
protocol MediaPlayer {
    func play()
    func pause()
    func stop()
    func adjustVolume(_ volume: Int)
    func showSubtitles(_ show: Bool)
    func setPlaybackSpeed(_ speed: Double)
}

class AudioPlayer: MediaPlayer {
    func play() { /* ... */ }
    func pause() { /* ... */ }
    func stop() { /* ... */ }
    func adjustVolume(_ volume: Int) { /* ... */ }
    func showSubtitles(_ show: Bool) { /* Not applicable! */ }
    func setPlaybackSpeed(_ speed: Double) { /* Not applicable! */ }
}

// ✅ GOOD: Segregated interfaces
protocol Playable {
    func play()
    func pause()
    func stop()
}

protocol VolumeControllable {
    func adjustVolume(_ volume: Int)
}

protocol SubtitleSupporting {
    func showSubtitles(_ show: Bool)
}

protocol PlaybackSpeedControllable {
    func setPlaybackSpeed(_ speed: Double)
}

class AudioPlayer: Playable, VolumeControllable {
    func play() { /* ... */ }
    func pause() { /* ... */ }
    func stop() { /* ... */ }
    func adjustVolume(_ volume: Int) { /* ... */ }
    // No forced subtitle implementation!
}

class VideoPlayer: Playable, VolumeControllable, SubtitleSupporting, PlaybackSpeedControllable {
    // Implements all relevant protocols
}
```

### D - Dependency Inversion Principle (DIP)

**Definition**: High-level modules should not depend on low-level modules. Both should depend on abstractions.

```swift
// ❌ BAD: High-level class depends on concrete implementation
class ArticleViewController: NSViewController {
    private let database = CoreDataManager()  // Concrete dependency!

    func loadArticles() {
        let articles = database.fetchArticles()
        // Update UI
    }
}

// ✅ GOOD: Depend on abstraction
protocol ArticleRepository {
    func fetchArticles() async throws -> [Article]
    func save(_ article: Article) async throws
}

class CoreDataArticleRepository: ArticleRepository {
    func fetchArticles() async throws -> [Article] {
        // Core Data implementation
    }

    func save(_ article: Article) async throws {
        // Core Data implementation
    }
}

class SwiftDataArticleRepository: ArticleRepository {
    func fetchArticles() async throws -> [Article] {
        // SwiftData implementation
    }

    func save(_ article: Article) async throws {
        // SwiftData implementation
    }
}

@MainActor
class ArticleViewModel: ObservableObject {
    @Published var articles: [Article] = []
    private let repository: ArticleRepository  // Depends on abstraction!

    init(repository: ArticleRepository) {
        self.repository = repository
    }

    func loadArticles() async {
        do {
            articles = try await repository.fetchArticles()
        } catch {
            // Handle error
        }
    }
}

// Easy to swap implementations or mock for testing
let viewModel = ArticleViewModel(repository: SwiftDataArticleRepository())
let testViewModel = ArticleViewModel(repository: MockArticleRepository())
```

## DRY Principle (Don't Repeat Yourself)

**Definition**: Every piece of knowledge must have a single, unambiguous representation.

### Code Duplication
```swift
// ❌ BAD: Repeated validation logic
func createUser(name: String, email: String) throws {
    if name.isEmpty {
        throw ValidationError.emptyName
    }
    if !email.contains("@") {
        throw ValidationError.invalidEmail
    }
    // Create user
}

func updateUser(name: String, email: String) throws {
    if name.isEmpty {
        throw ValidationError.emptyName
    }
    if !email.contains("@") {
        throw ValidationError.invalidEmail
    }
    // Update user
}

// ✅ GOOD: Extract common validation
struct UserValidator {
    static func validate(name: String, email: String) throws {
        guard !name.isEmpty else {
            throw ValidationError.emptyName
        }
        guard email.contains("@") else {
            throw ValidationError.invalidEmail
        }
    }
}

func createUser(name: String, email: String) throws {
    try UserValidator.validate(name: name, email: email)
    // Create user
}

func updateUser(name: String, email: String) throws {
    try UserValidator.validate(name: name, email: email)
    // Update user
}
```

### SwiftUI View Duplication
```swift
// ❌ BAD: Repeated UI components
struct ProfileView: View {
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "person")
                Text("John Doe")
                    .font(.headline)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)

            HStack {
                Image(systemName: "envelope")
                Text("john@example.com")
                    .font(.headline)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
    }
}

// ✅ GOOD: Reusable component
struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(text)
                .font(.headline)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

struct ProfileView: View {
    var body: some View {
        VStack {
            InfoRow(icon: "person", text: "John Doe")
            InfoRow(icon: "envelope", text: "john@example.com")
        }
    }
}
```

### Configuration Duplication
```swift
// ❌ BAD: Hardcoded values everywhere
class NetworkManager {
    func fetchUsers() async throws -> [User] {
        let url = URL(string: "https://api.example.com/users")!
        // ...
    }

    func fetchPosts() async throws -> [Post] {
        let url = URL(string: "https://api.example.com/posts")!
        // ...
    }
}

// ✅ GOOD: Centralized configuration
enum APIEndpoint {
    case users
    case posts
    case articles

    var url: URL {
        let baseURL = "https://api.example.com"
        switch self {
        case .users: return URL(string: "\(baseURL)/users")!
        case .posts: return URL(string: "\(baseURL)/posts")!
        case .articles: return URL(string: "\(baseURL)/articles")!
        }
    }
}

class NetworkManager {
    func fetch<T: Decodable>(from endpoint: APIEndpoint) async throws -> T {
        let url = endpoint.url
        // Single fetch implementation
    }

    func fetchUsers() async throws -> [User] {
        try await fetch(from: .users)
    }

    func fetchPosts() async throws -> [Post] {
        try await fetch(from: .posts)
    }
}
```

## Clean Architecture

### Layer Separation
```swift
// Domain Layer - Business logic, no framework dependencies
struct Article {
    let id: UUID
    let title: String
    let content: String
    let author: Author
}

protocol ArticleRepository {
    func fetch(id: UUID) async throws -> Article
    func save(_ article: Article) async throws
}

class ArticleUseCase {
    private let repository: ArticleRepository

    init(repository: ArticleRepository) {
        self.repository = repository
    }

    func publishArticle(_ article: Article) async throws {
        // Business logic
        guard article.content.count > 100 else {
            throw ValidationError.contentTooShort
        }
        try await repository.save(article)
    }
}

// Data Layer - Framework-specific implementations
import SwiftData

@Model
class ArticleEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    // SwiftData specific
}

class SwiftDataArticleRepository: ArticleRepository {
    private let modelContext: ModelContext

    func fetch(id: UUID) async throws -> Article {
        // Convert ArticleEntity to Article
    }

    func save(_ article: Article) async throws {
        // Convert Article to ArticleEntity and save
    }
}

// Presentation Layer - SwiftUI/AppKit
@MainActor
class ArticleViewModel: ObservableObject {
    @Published var article: Article?
    private let useCase: ArticleUseCase

    init(useCase: ArticleUseCase) {
        self.useCase = useCase
    }

    func publish() async {
        guard let article else { return }
        do {
            try await useCase.publishArticle(article)
        } catch {
            // Handle error
        }
    }
}
```

## Dependency Injection

### Constructor Injection (Preferred)
```swift
// ✅ GOOD: Dependencies injected via initializer
class ArticleService {
    private let repository: ArticleRepository
    private let logger: Logger
    private let validator: ArticleValidator

    init(
        repository: ArticleRepository,
        logger: Logger,
        validator: ArticleValidator
    ) {
        self.repository = repository
        self.logger = logger
        self.validator = validator
    }
}
```

### Property Injection (Use Sparingly)
```swift
// Use for SwiftUI Environment
struct ArticleListView: View {
    @Environment(\.articleRepository) var repository

    var body: some View {
        // Use repository
    }
}

// Define environment key
private struct ArticleRepositoryKey: EnvironmentKey {
    static let defaultValue: ArticleRepository = MockArticleRepository()
}

extension EnvironmentValues {
    var articleRepository: ArticleRepository {
        get { self[ArticleRepositoryKey.self] }
        set { self[ArticleRepositoryKey.self] = newValue }
    }
}
```

### Service Locator (Avoid When Possible)
```swift
// ⚠️ Use sparingly - hides dependencies
class ServiceLocator {
    static let shared = ServiceLocator()

    private var services: [String: Any] = [:]

    func register<T>(_ service: T, for type: T.Type) {
        let key = String(describing: type)
        services[key] = service
    }

    func resolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: type)
        return services[key] as? T
    }
}
```

## Composition Over Inheritance

```swift
// ❌ BAD: Deep inheritance hierarchy
class Vehicle {
    func start() { }
}

class Car: Vehicle {
    func honk() { }
}

class ElectricCar: Car {
    func charge() { }
}

class TeslaModelS: ElectricCar {
    // Too deep!
}

// ✅ GOOD: Composition with protocols
protocol Startable {
    func start()
}

protocol Honkable {
    func honk()
}

protocol Chargeable {
    func charge()
}

struct ElectricCar: Startable, Honkable, Chargeable {
    private let engine: ElectricEngine
    private let horn: Horn
    private let battery: Battery

    func start() {
        engine.start()
    }

    func honk() {
        horn.makeSound()
    }

    func charge() {
        battery.charge()
    }
}
```

## Architecture Patterns Checklist

- [ ] **SOLID**: Each class has single responsibility
- [ ] **SOLID**: Code open for extension, closed for modification
- [ ] **SOLID**: Subtypes properly substitutable
- [ ] **SOLID**: Interfaces are segregated and focused
- [ ] **SOLID**: Depend on abstractions, not concretions
- [ ] **DRY**: No duplicated logic or configuration
- [ ] **Clean Architecture**: Clear layer separation
- [ ] **DI**: Dependencies injected, not created internally
- [ ] **Composition**: Prefer composition over inheritance
- [ ] **Testability**: Easy to mock and test

## Resources

- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [Clean Architecture by Robert C. Martin](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Swift Design Patterns](https://refactoring.guru/design-patterns/swift)
