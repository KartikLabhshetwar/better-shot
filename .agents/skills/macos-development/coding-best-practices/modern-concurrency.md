# Modern Concurrency Best Practices

Async/await, actors, structured concurrency, and Swift 6 concurrency patterns for macOS.

## Async/Await Basics

### Converting from Completion Handlers

```swift
// ❌ OLD: Completion handler
func fetchUser(id: UUID, completion: @escaping (Result<User, Error>) -> Void) {
    URLSession.shared.dataTask(with: url) { data, response, error in
        // Handle callback
    }.resume()
}

// Usage with pyramid of doom
fetchUser(id: userID) { result in
    switch result {
    case .success(let user):
        fetchPosts(for: user) { result in
            switch result {
            case .success(let posts):
                // More nesting...
            case .failure(let error):
                // Handle error
            }
        }
    case .failure(let error):
        // Handle error
    }
}

// ✅ GOOD: Async/await
func fetchUser(id: UUID) async throws -> User {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(User.self, from: data)
}

func fetchPosts(for user: User) async throws -> [Post] {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode([Post].self, from: data)
}

// Usage - clean and linear
do {
    let user = try await fetchUser(id: userID)
    let posts = try await fetchPosts(for: user)
    // Process posts
} catch {
    // Handle error
}
```

### Async Properties

```swift
// ✅ GOOD: Async computed property
class ImageLoader {
    var image: UIImage {
        get async throws {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = UIImage(data: data) else {
                throw ImageError.invalidData
            }
            return image
        }
    }
}

// Usage
let image = try await imageLoader.image
```

## Task Management

### Creating and Managing Tasks

```swift
// ✅ GOOD: Unstructured task
class ViewController: NSViewController {
    private var loadingTask: Task<Void, Never>?

    func loadData() {
        loadingTask = Task {
            do {
                let data = try await fetchData()
                await updateUI(with: data)
            } catch {
                await showError(error)
            }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        loadingTask?.cancel()  // Cancel when view disappears
    }
}

// ✅ GOOD: Detached task (runs independently)
Task.detached {
    // Runs with default priority, no parent context
    let result = await heavyComputation()
    await MainActor.run {
        // Update UI on main thread
        updateUI(with: result)
    }
}
```

### Task Groups for Parallel Execution

```swift
// ✅ GOOD: Parallel fetching with task group
func fetchAllArticles(ids: [UUID]) async throws -> [Article] {
    try await withThrowingTaskGroup(of: Article.self) { group in
        for id in ids {
            group.addTask {
                try await self.fetchArticle(id: id)
            }
        }

        var articles: [Article] = []
        for try await article in group {
            articles.append(article)
        }
        return articles
    }
}

// ✅ GOOD: With error handling per task
func fetchAllArticles(ids: [UUID]) async -> [Result<Article, Error>] {
    await withTaskGroup(of: Result<Article, Error>.self) { group in
        for id in ids {
            group.addTask {
                do {
                    let article = try await self.fetchArticle(id: id)
                    return .success(article)
                } catch {
                    return .failure(error)
                }
            }
        }

        var results: [Result<Article, Error>] = []
        for await result in group {
            results.append(result)
        }
        return results
    }
}
```

### Async Sequences

```swift
// ✅ GOOD: Processing async sequences
func processLines(from url: URL) async throws {
    let lines = url.lines  // AsyncSequence

    for try await line in lines {
        processLine(line)
    }
}

// ✅ GOOD: Custom async sequence
struct NumberGenerator: AsyncSequence {
    typealias Element = Int

    let range: Range<Int>

    struct AsyncIterator: AsyncIteratorProtocol {
        var current: Int
        let end: Int

        mutating func next() async -> Int? {
            guard current < end else { return nil }
            let value = current
            current += 1
            try? await Task.sleep(for: .milliseconds(100))  // Simulate delay
            return value
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(current: range.lowerBound, end: range.upperBound)
    }
}

// Usage
for await number in NumberGenerator(range: 0..<10) {
    print(number)
}
```

## Actors for Thread Safety

### Basic Actor Usage

```swift
// ❌ BAD: Unsafe class with mutable state
class Counter {
    var value = 0  // Race condition!

    func increment() {
        value += 1
    }
}

// ✅ GOOD: Thread-safe actor
actor Counter {
    private var value = 0

    func increment() {
        value += 1
    }

    func getValue() -> Int {
        value
    }
}

// Usage (async required)
let counter = Counter()
await counter.increment()
let value = await counter.getValue()
```

### Actor Isolation

```swift
actor DataManager {
    private var cache: [UUID: Data] = [:]

    // Isolated to actor - synchronous within actor
    func updateCache(id: UUID, data: Data) {
        cache[id] = data
    }

    // Non-isolated - can be called synchronously
    nonisolated func generateID() -> UUID {
        UUID()  // Pure function, no actor state access
    }

    // Isolated - async from outside
    func getData(id: UUID) -> Data? {
        cache[id]
    }
}

// Usage
let manager = DataManager()
let id = manager.generateID()  // Synchronous - nonisolated
await manager.updateCache(id: id, data: data)  // Async - isolated
```

### Global Actors

```swift
// ✅ GOOD: MainActor for UI updates
@MainActor
class ViewModel: ObservableObject {
    @Published var items: [Item] = []

    // Runs on main thread
    func updateItems(_ newItems: [Item]) {
        items = newItems
    }

    // Explicitly run off main thread
    nonisolated func processInBackground() async {
        // Heavy computation off main thread
        let processed = await heavyComputation()

        // Switch back to main thread for UI update
        await updateItems(processed)
    }
}

// Individual functions can be marked
@MainActor
func updateUI() {
    // Guaranteed to run on main thread
}

// Mix isolated and non-isolated in same type
class MixedClass {
    @MainActor
    var uiProperty: String = ""

    nonisolated
    func backgroundWork() {
        // Runs on background thread
    }
}
```

## Sendable Protocol

### Sendable Types

```swift
// ✅ GOOD: Value types are automatically Sendable
struct User: Sendable {
    let id: UUID
    let name: String
}

// ✅ GOOD: Immutable classes can be Sendable
final class Configuration: Sendable {
    let apiKey: String
    let baseURL: URL

    init(apiKey: String, baseURL: URL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

// ❌ BAD: Mutable class can't be Sendable safely
final class Counter: Sendable {  // Warning!
    var count = 0  // Mutable property not thread-safe
}

// ✅ GOOD: Use actor instead
actor Counter {
    var count = 0  // Thread-safe via actor isolation
}

// ✅ GOOD: @unchecked Sendable when you know it's safe
final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}
```

### Sendable Closures

```swift
// ✅ GOOD: Sendable closure
func processAsync(_ handler: @Sendable () -> Void) async {
    await Task.detached {
        handler()
    }.value
}

// ❌ BAD: Capturing mutable state
var counter = 0
processAsync {
    counter += 1  // Error: capturing mutable state
}

// ✅ GOOD: Use actor for mutable state
actor SharedCounter {
    var value = 0
}

let sharedCounter = SharedCounter()
processAsync {
    await sharedCounter.increment()
}
```

## Concurrency Patterns

### Repository Pattern with Async/Await

```swift
protocol ArticleRepository {
    func fetchArticles() async throws -> [Article]
    func save(_ article: Article) async throws
}

actor SwiftDataArticleRepository: ArticleRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchArticles() async throws -> [Article] {
        let descriptor = FetchDescriptor<Article>()
        return try modelContext.fetch(descriptor)
    }

    func save(_ article: Article) async throws {
        modelContext.insert(article)
        try modelContext.save()
    }
}
```

### ViewModel with Async Operations

```swift
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
        error = nil

        do {
            articles = try await repository.fetchArticles()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func refresh() async {
        await loadArticles()
    }
}

// Usage in SwiftUI
struct ArticleListView: View {
    @StateObject private var viewModel: ArticleListViewModel

    var body: some View {
        List(viewModel.articles) { article in
            Text(article.title)
        }
        .task {
            await viewModel.loadArticles()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}
```

### Cancellation Handling

```swift
// ✅ GOOD: Checking for cancellation
func performLongOperation() async throws {
    for i in 0..<1000 {
        // Check if task was cancelled
        try Task.checkCancellation()

        // Or check manually
        if Task.isCancelled {
            cleanup()
            return
        }

        await processItem(i)
    }
}

// ✅ GOOD: Cancellation in view model
@MainActor
class SearchViewModel: ObservableObject {
    @Published var results: [Result] = []
    private var searchTask: Task<Void, Never>?

    func search(_ query: String) {
        // Cancel previous search
        searchTask?.cancel()

        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))  // Debounce
                try Task.checkCancellation()

                let results = try await performSearch(query)
                self.results = results
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
                // Handle other errors
            }
        }
    }
}
```

## Concurrency Best Practices

### Avoid Blocking Main Thread

```swift
// ❌ BAD: Blocking main thread
@MainActor
func loadData() {
    let data = heavyComputation()  // Blocks UI!
    updateUI(with: data)
}

// ✅ GOOD: Run computation off main thread
@MainActor
func loadData() async {
    let data = await Task.detached {
        heavyComputation()
    }.value
    updateUI(with: data)
}
```

### Use Structured Concurrency

```swift
// ❌ BAD: Unstructured tasks can leak
func fetchAllData() {
    Task {
        let users = try await fetchUsers()
    }
    Task {
        let posts = try await fetchPosts()
    }
    // Tasks may outlive this function
}

// ✅ GOOD: Structured with task group
func fetchAllData() async throws -> (users: [User], posts: [Post]) {
    try await withThrowingTaskGroup(of: Void.self) { group in
        var users: [User] = []
        var posts: [Post] = []

        group.addTask {
            users = try await self.fetchUsers()
        }

        group.addTask {
            posts = try await self.fetchPosts()
        }

        try await group.waitForAll()

        return (users, posts)
    }
}
```

### Prioritize Tasks

```swift
// ✅ GOOD: Task priorities
Task(priority: .background) {
    await performBackgroundSync()
}

Task(priority: .userInitiated) {
    await loadUserData()
}

Task(priority: .high) {
    await handleUrgentRequest()
}
```

## AsyncStream for Continuous Updates

```swift
// ✅ GOOD: AsyncStream for real-time updates
actor NotificationCenter {
    private var continuations: [UUID: AsyncStream<Notification>.Continuation] = [:]

    func notifications() -> AsyncStream<Notification> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    func post(_ notification: Notification) {
        for continuation in continuations.values {
            continuation.yield(notification)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

// Usage
let notificationCenter = NotificationCenter()

Task {
    for await notification in await notificationCenter.notifications() {
        print("Received: \(notification)")
    }
}

await notificationCenter.post(Notification(name: "test"))
```

## Concurrency Checklist

- [ ] Use async/await instead of completion handlers
- [ ] Mark UI-related code with @MainActor
- [ ] Use actors for mutable shared state
- [ ] Ensure types crossing concurrency boundaries are Sendable
- [ ] Handle task cancellation appropriately
- [ ] Use structured concurrency (task groups) over unstructured tasks
- [ ] Check for race conditions in mutable state
- [ ] Avoid blocking the main thread
- [ ] Set appropriate task priorities
- [ ] Clean up resources on task cancellation

## Swift 6 Concurrency Migration

- [ ] Enable strict concurrency checking
- [ ] Fix non-Sendable type warnings
- [ ] Mark appropriate types as @MainActor
- [ ] Replace DispatchQueue with async/await
- [ ] Convert @escaping closures to async functions
- [ ] Use actors instead of locks
- [ ] Audit @unchecked Sendable usage

## Resources

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [WWDC 2023: Beyond the basics of structured concurrency](https://developer.apple.com/videos/play/wwdc2023/10170/)
- [Swift Evolution: Concurrency](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
