# Code Organization Best Practices

Modular architecture, project structure, and separation of concerns for macOS development.

## Project Structure

### Feature-Based Organization (Recommended)

```
MyMacApp/
├── App/
│   ├── MyMacApp.swift
│   └── AppDelegate.swift
├── Features/
│   ├── Articles/
│   │   ├── Views/
│   │   │   ├── ArticleListView.swift
│   │   │   ├── ArticleDetailView.swift
│   │   │   └── ArticleEditorView.swift
│   │   ├── ViewModels/
│   │   │   ├── ArticleListViewModel.swift
│   │   │   └── ArticleEditorViewModel.swift
│   │   ├── Models/
│   │   │   └── Article.swift
│   │   └── Services/
│   │       └── ArticleRepository.swift
│   ├── Authors/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   ├── Models/
│   │   └── Services/
│   └── Settings/
│       ├── Views/
│       ├── ViewModels/
│       └── Models/
├── Core/
│   ├── Data/
│   │   ├── SwiftDataStack.swift
│   │   └── ModelContainer+Extensions.swift
│   ├── Networking/
│   │   ├── NetworkManager.swift
│   │   ├── APIEndpoint.swift
│   │   └── NetworkError.swift
│   ├── Extensions/
│   │   ├── Date+Extensions.swift
│   │   ├── String+Extensions.swift
│   │   └── View+Extensions.swift
│   └── Utilities/
│       ├── Logger.swift
│       └── Validator.swift
├── Resources/
│   ├── Assets.xcassets
│   ├── Localization/
│   └── Fonts/
└── Tests/
    ├── ArticlesTests/
    ├── AuthorsTests/
    └── CoreTests/
```

### Layer-Based Organization (Alternative)

```
MyMacApp/
├── Presentation/
│   ├── SwiftUI/
│   │   ├── Articles/
│   │   └── Settings/
│   ├── AppKit/
│   │   └── CustomViews/
│   └── ViewModels/
├── Domain/
│   ├── Models/
│   ├── UseCases/
│   └── Interfaces/
├── Data/
│   ├── Repositories/
│   ├── DataSources/
│   └── SwiftData/
└── Infrastructure/
    ├── Networking/
    └── Utilities/
```

## Swift Package Manager Organization

### Multi-Module Architecture

```swift
// Package.swift
let package = Package(
    name: "MyMacApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArticleFeature", targets: ["ArticleFeature"]),
        .library(name: "CoreKit", targets: ["CoreKit"]),
        .library(name: "NetworkKit", targets: ["NetworkKit"]),
    ],
    dependencies: [
        // External dependencies
    ],
    targets: [
        // Feature modules
        .target(
            name: "ArticleFeature",
            dependencies: ["CoreKit", "NetworkKit"]
        ),
        .testTarget(
            name: "ArticleFeatureTests",
            dependencies: ["ArticleFeature"]
        ),

        // Core module
        .target(
            name: "CoreKit",
            dependencies: []
        ),

        // Network module
        .target(
            name: "NetworkKit",
            dependencies: ["CoreKit"]
        ),
    ]
)
```

### Benefits of SPM Modules

```swift
// ✅ GOOD: Clear dependencies and boundaries
import ArticleFeature  // Only imports what's needed
import CoreKit

// Each module can be:
// - Built independently
// - Tested in isolation
// - Reused across targets
// - Versioned separately
```

## Separation of Concerns

### MVVM Pattern for SwiftUI

```swift
// ❌ BAD: View doing too much
struct ArticleListView: View {
    @State private var articles: [Article] = []

    var body: some View {
        List(articles) { article in
            Text(article.title)
        }
        .task {
            // Bad: Networking in view
            let url = URL(string: "https://api.example.com/articles")!
            let (data, _) = try! await URLSession.shared.data(from: url)
            articles = try! JSONDecoder().decode([Article].self, from: data)
        }
    }
}

// ✅ GOOD: Proper separation
@MainActor
class ArticleListViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoading = false
    @Published var error: Error?

    private let repository: ArticleRepository

    init(repository: ArticleRepository) {
        self.repository = repository
    }

    func loadArticles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            articles = try await repository.fetchArticles()
        } catch {
            self.error = error
        }
    }
}

struct ArticleListView: View {
    @StateObject private var viewModel: ArticleListViewModel

    init(repository: ArticleRepository) {
        _viewModel = StateObject(
            wrappedValue: ArticleListViewModel(repository: repository)
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else {
                List(viewModel.articles) { article in
                    Text(article.title)
                }
            }
        }
        .task {
            await viewModel.loadArticles()
        }
    }
}
```

### Repository Pattern

```swift
// ✅ GOOD: Protocol defines contract
protocol ArticleRepository {
    func fetchArticles() async throws -> [Article]
    func fetchArticle(id: UUID) async throws -> Article?
    func save(_ article: Article) async throws
    func delete(id: UUID) async throws
}

// Implementation 1: SwiftData
class SwiftDataArticleRepository: ArticleRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchArticles() async throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func save(_ article: Article) async throws {
        modelContext.insert(article)
        try modelContext.save()
    }

    // ... other methods
}

// Implementation 2: Network
class NetworkArticleRepository: ArticleRepository {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func fetchArticles() async throws -> [Article] {
        try await networkManager.fetch(from: .articles)
    }

    // ... other methods
}

// Implementation 3: Mock for testing
class MockArticleRepository: ArticleRepository {
    var articles: [Article] = []

    func fetchArticles() async throws -> [Article] {
        articles
    }

    func save(_ article: Article) async throws {
        articles.append(article)
    }

    // ... other methods
}
```

## File Organization Best Practices

### Single Responsibility per File

```swift
// ✅ GOOD: One type per file
// Article.swift
struct Article: Identifiable {
    let id: UUID
    var title: String
    var content: String
}

// ArticleValidator.swift
struct ArticleValidator {
    static func validate(_ article: Article) throws {
        // Validation logic
    }
}

// ArticleFormatter.swift
struct ArticleFormatter {
    static func format(_ article: Article) -> String {
        // Formatting logic
    }
}

// ❌ BAD: Multiple unrelated types in one file
// ArticleHelpers.swift
struct Article { }
struct ArticleValidator { }
struct ArticleFormatter { }
class ArticleManager { }
```

### Extension Organization

```swift
// Article.swift - Main definition
struct Article: Identifiable {
    let id: UUID
    var title: String
    var content: String
}

// Article+Validation.swift - Validation logic
extension Article {
    func validate() throws {
        guard !title.isEmpty else {
            throw ValidationError.emptyTitle
        }
    }
}

// Article+Formatting.swift - Formatting logic
extension Article {
    var formattedPublishDate: String {
        publishedDate.formatted(date: .long, time: .omitted)
    }
}

// Article+Codable.swift - Codable conformance
extension Article: Codable { }
```

## Dependency Management

### Composition Root

```swift
// ✅ GOOD: Single place for dependency setup
@main
struct MyMacApp: App {
    let dependencyContainer: DependencyContainer

    init() {
        dependencyContainer = DependencyContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.articleRepository, dependencyContainer.articleRepository)
                .environment(\.networkManager, dependencyContainer.networkManager)
        }
    }
}

class DependencyContainer {
    // Singletons
    lazy var networkManager: NetworkManager = {
        NetworkManager()
    }()

    lazy var modelContainer: ModelContainer = {
        try! ModelContainer(for: Article.self, Author.self)
    }()

    // Factories
    var articleRepository: ArticleRepository {
        SwiftDataArticleRepository(
            modelContext: modelContainer.mainContext
        )
    }

    var articleListViewModel: ArticleListViewModel {
        ArticleListViewModel(repository: articleRepository)
    }
}
```

### Environment for SwiftUI

```swift
// Define environment keys
private struct ArticleRepositoryKey: EnvironmentKey {
    static let defaultValue: ArticleRepository = MockArticleRepository()
}

private struct NetworkManagerKey: EnvironmentKey {
    static let defaultValue: NetworkManager = NetworkManager()
}

extension EnvironmentValues {
    var articleRepository: ArticleRepository {
        get { self[ArticleRepositoryKey.self] }
        set { self[ArticleRepositoryKey.self] = newValue }
    }

    var networkManager: NetworkManager {
        get { self[NetworkManagerKey.self] }
        set { self[NetworkManagerKey.self] = newValue }
    }
}

// Usage in views
struct ArticleListView: View {
    @Environment(\.articleRepository) var repository

    var body: some View {
        // Use repository
    }
}
```

## Code Reusability (DRY)

### Extracting Common UI Components

```swift
// ✅ GOOD: Reusable components
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(8)
        }
    }
}

// Usage
VStack {
    PrimaryButton(title: "Save") { save() }
    SecondaryButton(title: "Cancel") { cancel() }
}
```

### View Modifiers for Common Styles

```swift
// ✅ GOOD: Custom view modifiers
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .shadow(radius: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// Usage
Text("Content")
    .cardStyle()
```

## Testing Organization

```swift
// Tests mirror source structure
MyMacAppTests/
├── Features/
│   ├── Articles/
│   │   ├── ArticleListViewModelTests.swift
│   │   ├── ArticleRepositoryTests.swift
│   │   └── ArticleValidatorTests.swift
│   └── Settings/
│       └── SettingsViewModelTests.swift
└── Core/
    ├── NetworkManagerTests.swift
    └── ValidationTests.swift

// ✅ GOOD: Test structure
import XCTest
@testable import MyMacApp

final class ArticleListViewModelTests: XCTestCase {
    var sut: ArticleListViewModel!
    var mockRepository: MockArticleRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockArticleRepository()
        sut = ArticleListViewModel(repository: mockRepository)
    }

    override func tearDown() {
        sut = nil
        mockRepository = nil
        super.tearDown()
    }

    func testLoadArticles_Success() async {
        // Given
        let expectedArticles = [
            Article(title: "Test 1", content: "Content 1"),
            Article(title: "Test 2", content: "Content 2")
        ]
        mockRepository.articles = expectedArticles

        // When
        await sut.loadArticles()

        // Then
        XCTAssertEqual(sut.articles.count, 2)
        XCTAssertEqual(sut.articles[0].title, "Test 1")
    }
}
```

## Configuration Management

```swift
// ✅ GOOD: Environment-based configuration
enum Environment {
    case development
    case staging
    case production

    static var current: Environment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

struct Configuration {
    let apiBaseURL: String
    let apiKey: String
    let enableLogging: Bool

    static var current: Configuration {
        switch Environment.current {
        case .development:
            return Configuration(
                apiBaseURL: "https://dev-api.example.com",
                apiKey: "dev-key",
                enableLogging: true
            )
        case .staging:
            return Configuration(
                apiBaseURL: "https://staging-api.example.com",
                apiKey: "staging-key",
                enableLogging: true
            )
        case .production:
            return Configuration(
                apiBaseURL: "https://api.example.com",
                apiKey: "prod-key",
                enableLogging: false
            )
        }
    }
}
```

## Code Organization Checklist

- [ ] Clear project structure (feature or layer-based)
- [ ] One type per file (with exceptions for tiny related types)
- [ ] Logical grouping of related files
- [ ] Consistent naming conventions
- [ ] Use of Swift Package Manager for modularity
- [ ] Proper separation of concerns (MVVM/VIPER/etc.)
- [ ] Repository pattern for data access
- [ ] Dependency injection at composition root
- [ ] Reusable UI components
- [ ] Tests mirror source structure
- [ ] Configuration management per environment

## Resources

- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [Swift Package Manager Documentation](https://swift.org/package-manager/)
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
