# SwiftData Performance Optimization

Batch operations, background contexts, lazy loading, and memory management techniques for SwiftData.

## Measuring Performance

Before optimizing, measure. Use Instruments to identify actual bottlenecks:

```swift
// Quick timing in code
func measureFetch() async throws {
    let start = CFAbsoluteTimeGetCurrent()
    let results = try modelContext.fetch(FetchDescriptor<Document>())
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    print("Fetched \(results.count) documents in \(elapsed)s")
}
```

### Instruments Traces
- **SwiftData** instrument: query durations, save operations
- **Core Data** instrument: underlying SQLite operations (SwiftData uses Core Data)
- **Allocations**: memory growth from model objects
- **Time Profiler**: CPU time in fetch/save operations

## Background Context Operations

Never block the main thread with heavy data operations. Use `@ModelActor` for background work.

### Background Imports

```swift
@ModelActor
actor DataImporter {
    func importItems(_ items: [ImportItem]) async throws -> Int {
        var importedCount = 0

        for item in items {
            let model = DocumentModel(
                title: item.title,
                content: item.content,
                createdAt: item.date
            )
            modelContext.insert(model)
            importedCount += 1

            // Save in batches to manage memory
            if importedCount % 500 == 0 {
                try modelContext.save()
            }
        }

        try modelContext.save()
        return importedCount
    }
}

// Usage from ViewModel
@Observable @MainActor
class ImportViewModel {
    var progress: Double = 0
    var isImporting = false

    func importFile(url: URL, container: ModelContainer) async throws {
        isImporting = true
        defer { isImporting = false }

        let items = try parseFile(url)
        let importer = DataImporter(modelContainer: container)
        let count = try await importer.importItems(items)
        print("Imported \(count) items")
    }
}
```

### Background Deletions

```swift
@ModelActor
actor DataCleaner {
    func deleteOldItems(olderThan date: Date) async throws -> Int {
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.timestamp < date }
        )
        let items = try modelContext.fetch(descriptor)
        let count = items.count

        for item in items {
            modelContext.delete(item)
        }
        try modelContext.save()
        return count
    }
}
```

## Batch Operations

### Efficient Batch Insert

```swift
@ModelActor
actor BatchProcessor {
    func batchInsert(_ records: [Record]) async throws {
        // Insert in chunks to manage memory
        let chunkSize = 1000
        for chunk in records.chunked(into: chunkSize) {
            for record in chunk {
                modelContext.insert(record.toModel())
            }
            try modelContext.save()

            // Reset context to free memory from processed objects
            modelContext.reset()
        }
    }
}

// Array chunking helper
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

### Efficient Batch Updates

```swift
@ModelActor
actor BatchUpdater {
    func markAllCompleted(projectID: UUID) async throws {
        let descriptor = FetchDescriptor<TaskModel>(
            predicate: #Predicate { $0.project?.id == projectID && !$0.isCompleted }
        )
        let tasks = try modelContext.fetch(descriptor)
        for task in tasks {
            task.isCompleted = true
        }
        try modelContext.save()
    }
}
```

## Fetch Optimization

### Fetch Only What You Need

```swift
// Wrong - fetches all properties of all records
let everything = try modelContext.fetch(FetchDescriptor<Document>())
let titles = everything.map(\.title)

// Right - fetch specific properties
var descriptor = FetchDescriptor<Document>()
descriptor.propertiesToFetch = [\.title, \.createdAt]
let documents = try modelContext.fetch(descriptor)
```

### Use Count Instead of Fetch

```swift
// Counts at the database level instead of materializing objects
let count = try modelContext.fetchCount(FetchDescriptor<Task>())
```

### Use Identifiers for Lightweight Checks

```swift
// Fetch just IDs (no object materialization)
let ids = try modelContext.fetchIdentifiers(
    FetchDescriptor<Document>(predicate: #Predicate { $0.isArchived })
)
let archivedCount = ids.count
```

### Pagination for Large Datasets

```swift
struct PaginatedList<Model: PersistentModel>: View {
    @State private var items: [Model] = []
    @State private var hasMore = true
    @State private var currentPage = 0
    let pageSize = 50
    let sortDescriptor: SortDescriptor<Model>

    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(items) { item in
                // Row view
            }

            if hasMore {
                ProgressView()
                    .task { await loadNextPage() }
            }
        }
        .task { await loadNextPage() }
    }

    func loadNextPage() async {
        var descriptor = FetchDescriptor<Model>(sortBy: [sortDescriptor])
        descriptor.fetchOffset = currentPage * pageSize
        descriptor.fetchLimit = pageSize

        do {
            let newItems = try context.fetch(descriptor)
            items.append(contentsOf: newItems)
            hasMore = newItems.count == pageSize
            currentPage += 1
        } catch {
            hasMore = false
        }
    }
}
```

## Memory Management

### Autosave Considerations

By default, SwiftData autosaves. For bulk operations, you may want to control saves:

```swift
let config = ModelConfiguration(isStoredInMemoryOnly: false)
let container = try ModelContainer(
    for: Document.self,
    configurations: config
)

// The ModelContext.autosaveEnabled property controls auto-saves
// For background contexts in @ModelActor, auto-save is off by default
```

### Reset Context After Bulk Work

```swift
@ModelActor
actor HeavyProcessor {
    func processAllDocuments() async throws {
        var offset = 0
        let batchSize = 100

        while true {
            var descriptor = FetchDescriptor<Document>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }

            for doc in batch {
                doc.processedAt = .now
            }

            try modelContext.save()
            modelContext.reset()  // Free memory from processed objects

            offset += batchSize
        }
    }
}
```

### Relationship Faulting

SwiftData lazily loads relationships. Access them only when needed:

```swift
// Good - relationship not accessed until needed
struct ProjectListView: View {
    @Query var projects: [Project]

    var body: some View {
        List(projects) { project in
            HStack {
                Text(project.name)
                Spacer()
                // Tasks loaded on-demand when this view appears
                Text("\(project.tasks.count) tasks")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

## Predicate Performance

### Use Indexed Properties for Frequent Queries

Predicates on indexed properties are significantly faster:

```swift
@Model
class Document {
    // Properties frequently used in predicates should be simple types
    var title: String          // Fast to query
    var isArchived: Bool       // Fast to query
    var createdAt: Date        // Fast to query
    var tags: [String] = []    // Slower to query (transformable)
}
```

### Predicate Complexity

```swift
// Fast - simple property comparison
#Predicate<Task> { !$0.isCompleted }

// Fast - date comparison
let cutoff = Date.now
#Predicate<Task> { $0.createdAt > cutoff }

// Slower - string contains
#Predicate<Task> { $0.title.localizedStandardContains(searchText) }

// Slower - nested relationship traversal
#Predicate<Task> { $0.project?.category?.name == categoryName }
```

### Optimize Search

For search features, consider a denormalized search field:

```swift
@Model
class Document {
    var title: String
    var content: String
    var author: String

    // Denormalized for fast search
    var searchText: String

    init(title: String, content: String, author: String) {
        self.title = title
        self.content = content
        self.author = author
        self.searchText = "\(title) \(content) \(author)".lowercased()
    }
}

// Fast single-field search instead of multi-field predicate
let query = searchText.lowercased()
#Predicate<Document> { $0.searchText.contains(query) }
```

## Common Performance Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Fetching too many objects | High memory, slow scroll | Use fetchLimit, pagination |
| Main thread saves | UI freezes on save | Use @ModelActor for writes |
| N+1 queries | Slow list rendering | Batch fetch relationships |
| No fetch limits | Memory growth | Always set fetchLimit for bounded UI |
| Frequent small saves | Disk I/O bottleneck | Batch saves (every N items) |

## Best Practices

1. **Measure before optimizing** - Use Instruments, not intuition
2. **Use @ModelActor for background work** - Never block the main thread
3. **Batch saves** - Save every 100-1000 items, not every single insert
4. **Use fetchCount for counts** - Don't materialize objects just to count
5. **Set fetchLimit for bounded UI** - A "top 10" list shouldn't fetch 10,000 records
6. **Paginate large datasets** - Load on-demand as the user scrolls
7. **Keep predicates simple** - Complex nested predicates are slower
8. **Denormalize for search** - A single searchText field beats multi-field predicates
