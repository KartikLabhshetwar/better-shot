# Data Persistence Best Practices

SwiftData-first approach with Core Data guidance for legacy scenarios.

## SwiftData (Modern Approach)

### Model Definition

```swift
import SwiftData

// ✅ GOOD: Clean SwiftData model
@Model
final class Article {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var publishedDate: Date
    var author: Author?
    var tags: [Tag]

    init(title: String, content: String, author: Author? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.publishedDate = Date()
        self.author = author
        self.tags = []
    }
}

@Model
final class Author {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String

    @Relationship(deleteRule: .cascade, inverse: \Article.author)
    var articles: [Article]

    init(name: String, email: String) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.articles = []
    }
}

@Model
final class Tag {
    @Attribute(.unique) var name: String
    var articles: [Article]

    init(name: String) {
        self.name = name
        self.articles = []
    }
}
```

### Relationships

```swift
// One-to-Many with cascade delete
@Model
final class Project {
    var name: String

    @Relationship(deleteRule: .cascade)
    var tasks: [Task]
}

@Model
final class Task {
    var title: String
    var project: Project?
}

// Many-to-Many
@Model
final class Student {
    var name: String
    var courses: [Course]
}

@Model
final class Course {
    var title: String
    var students: [Student]
}

// One-to-One
@Model
final class User {
    var username: String

    @Relationship(deleteRule: .cascade)
    var profile: UserProfile?
}

@Model
final class UserProfile {
    var bio: String
    var avatarURL: URL?
    var user: User?
}
```

### Model Container Setup

```swift
import SwiftUI
import SwiftData

@main
struct MyApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Article.self,
                Author.self,
                Tag.self
            ])

            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

// ✅ GOOD: In-memory container for testing
extension ModelContainer {
    static func preview() throws -> ModelContainer {
        let schema = Schema([Article.self, Author.self, Tag.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

### Querying Data

```swift
import SwiftUI
import SwiftData

// ✅ GOOD: Simple query
struct ArticleListView: View {
    @Query(sort: \Article.publishedDate, order: .reverse)
    private var articles: [Article]

    var body: some View {
        List(articles) { article in
            Text(article.title)
        }
    }
}

// ✅ GOOD: Filtered query
struct ArticleListView: View {
    @Query(
        filter: #Predicate<Article> { article in
            article.publishedDate > Date().addingTimeInterval(-86400 * 7)
        },
        sort: \Article.publishedDate,
        order: .reverse
    )
    private var recentArticles: [Article]

    var body: some View {
        List(recentArticles) { article in
            Text(article.title)
        }
    }
}

// ✅ GOOD: Dynamic query with init
struct ArticleListView: View {
    @Query private var articles: [Article]

    init(authorName: String) {
        let predicate = #Predicate<Article> { article in
            article.author?.name == authorName
        }
        _articles = Query(
            filter: predicate,
            sort: \.publishedDate,
            order: .reverse
        )
    }

    var body: some View {
        List(articles) { article in
            Text(article.title)
        }
    }
}
```

### Model Context Operations

```swift
import SwiftData

@MainActor
class ArticleViewModel: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // ✅ GOOD: Insert
    func createArticle(title: String, content: String) {
        let article = Article(title: title, content: content)
        modelContext.insert(article)

        do {
            try modelContext.save()
        } catch {
            print("Error saving article: \(error)")
        }
    }

    // ✅ GOOD: Update
    func updateArticle(_ article: Article, title: String) {
        article.title = title

        do {
            try modelContext.save()
        } catch {
            print("Error updating article: \(error)")
        }
    }

    // ✅ GOOD: Delete
    func deleteArticle(_ article: Article) {
        modelContext.delete(article)

        do {
            try modelContext.save()
        } catch {
            print("Error deleting article: \(error)")
        }
    }

    // ✅ GOOD: Batch fetch
    func fetchArticles(matching searchText: String) throws -> [Article] {
        let predicate = #Predicate<Article> { article in
            article.title.localizedStandardContains(searchText) ||
            article.content.localizedStandardContains(searchText)
        }

        let descriptor = FetchDescriptor<Article>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }
}
```

### Advanced Predicates

```swift
import Foundation
import SwiftData

// ✅ Complex filtering
let predicate = #Predicate<Article> { article in
    article.publishedDate > Date().addingTimeInterval(-86400 * 30) &&
    article.author?.name == "John Doe" &&
    article.tags.contains { $0.name == "Swift" }
}

// ✅ Text search
let searchPredicate = #Predicate<Article> { article in
    article.title.localizedStandardContains("SwiftData")
}

// ✅ Range filtering
let rangePredicate = #Predicate<Article> { article in
    article.publishedDate >= startDate &&
    article.publishedDate <= endDate
}

// ✅ Combining predicates
let combinedPredicate = #Predicate<Article> { article in
    (article.title.localizedStandardContains("Swift") ||
     article.content.localizedStandardContains("Swift")) &&
    article.publishedDate > Date().addingTimeInterval(-86400 * 7)
}
```

### Migration and Versioning

```swift
import SwiftData

// Version 1
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Article.self, Author.self]
    }

    @Model
    final class Article {
        var title: String
        var content: String
    }

    @Model
    final class Author {
        var name: String
    }
}

// Version 2 - Added fields
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Article.self, Author.self]
    }

    @Model
    final class Article {
        var title: String
        var content: String
        var publishedDate: Date  // New field
        var tags: [String]       // New field
    }

    @Model
    final class Author {
        var name: String
        var email: String  // New field
    }
}

// Migration plan
enum ArticleMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // Custom migration logic
            let articles = try context.fetch(FetchDescriptor<SchemaV2.Article>())
            for article in articles {
                article.publishedDate = Date()
                article.tags = []
            }
            try context.save()
        }
    )
}
```

### Performance Optimization

```swift
// ✅ GOOD: Batch operations
func batchInsert(articles: [ArticleData]) {
    let modelContext = ModelContext(modelContainer)

    for articleData in articles {
        let article = Article(
            title: articleData.title,
            content: articleData.content
        )
        modelContext.insert(article)
    }

    do {
        try modelContext.save()  // Single save for all inserts
    } catch {
        print("Batch insert error: \(error)")
    }
}

// ✅ GOOD: Lazy loading with limits
func fetchRecentArticles(limit: Int = 20) throws -> [Article] {
    let descriptor = FetchDescriptor<Article>(
        sortBy: [SortDescriptor(\.publishedDate, order: .reverse)]
    )
    descriptor.fetchLimit = limit

    return try modelContext.fetch(descriptor)
}

// ✅ GOOD: Background context for heavy operations
func processArticles() async {
    await Task.detached {
        let backgroundContext = ModelContext(modelContainer)

        let articles = try? backgroundContext.fetch(FetchDescriptor<Article>())
        // Process articles...

        try? backgroundContext.save()
    }.value
}
```

### CloudKit Integration

```swift
import SwiftData

// ✅ Configure CloudKit sync
let configuration = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,
    allowsSave: true,
    cloudKitDatabase: .automatic  // Enables CloudKit sync
)

let container = try ModelContainer(
    for: schema,
    configurations: [configuration]
)

// ✅ Handle sync conflicts
@Model
final class Article {
    var title: String
    var content: String

    // CloudKit metadata
    @Attribute(.cloudKitSystemFields)
    var cloudKitMetadata: Data?
}
```

## Core Data (Legacy Scenarios)

### When to Use Core Data Instead of SwiftData

Complex migrations from an existing Core Data app, advanced Core Data features not yet in SwiftData, Fetched Results Controllers with complex predicates, or custom NSManagedObject subclasses.

### Core Data Best Practices

```swift
import CoreData

// ✅ GOOD: Core Data stack
class CoreDataStack {
    static let shared = CoreDataStack()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "MyApp")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        return container
    }()

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    func saveContext() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// ✅ GOOD: Background operations
extension CoreDataStack {
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        persistentContainer.performBackgroundTask(block)
    }
}
```

### Migration from Core Data to SwiftData

```swift
// Step 1: Create SwiftData models matching Core Data entities
@Model
final class Article {
    var title: String
    var content: String
    var publishedDate: Date

    init(from managedObject: NSManagedObject) {
        self.title = managedObject.value(forKey: "title") as? String ?? ""
        self.content = managedObject.value(forKey: "content") as? String ?? ""
        self.publishedDate = managedObject.value(forKey: "publishedDate") as? Date ?? Date()
    }
}

// Step 2: Migration utility
class CoreDataToSwiftDataMigration {
    static func migrate() async throws {
        let coreDataContext = CoreDataStack.shared.viewContext
        let swiftDataContainer = try ModelContainer(for: Article.self)
        let swiftDataContext = ModelContext(swiftDataContainer)

        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Article")
        let coreDataArticles = try coreDataContext.fetch(fetchRequest)

        for managedObject in coreDataArticles {
            let article = Article(from: managedObject)
            swiftDataContext.insert(article)
        }

        try swiftDataContext.save()
    }
}
```

## UserDefaults for Simple Data

```swift
// ✅ GOOD: Property wrapper for UserDefaults
@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get {
            UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

// ✅ GOOD: Settings with UserDefaults
struct AppSettings {
    @UserDefault(key: "theme", defaultValue: "light")
    static var theme: String

    @UserDefault(key: "fontSize", defaultValue: 14)
    static var fontSize: Int

    @UserDefault(key: "notificationsEnabled", defaultValue: true)
    static var notificationsEnabled: Bool
}

// ⚠️ Don't use UserDefaults for large data or complex objects
// Use SwiftData/Core Data instead
```

## Data Persistence Checklist

- [ ] Use SwiftData for new projects
- [ ] Define clear model relationships
- [ ] Implement proper delete rules
- [ ] Use @Query in SwiftUI views
- [ ] Handle save errors gracefully
- [ ] Use background contexts for heavy operations
- [ ] Implement migrations for schema changes
- [ ] Consider CloudKit sync if needed
- [ ] Use UserDefaults only for simple preferences
- [ ] Test with realistic data volumes

## Resources

- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [WWDC 2024: What's new in SwiftData](https://developer.apple.com/videos/swiftdata)
- [Core Data Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/)
