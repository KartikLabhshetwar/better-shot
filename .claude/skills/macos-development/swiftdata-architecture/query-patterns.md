# SwiftData Query Patterns

Efficient use of @Query, FetchDescriptor, predicates, and sorting for optimal performance.

## @Query in SwiftUI Views

The `@Query` property wrapper fetches data reactively — the view updates automatically when data changes.

### Basic Usage

```swift
struct TaskListView: View {
    // Simple fetch with sorting
    @Query(sort: \.createdAt, order: .reverse)
    private var tasks: [Task]

    var body: some View {
        List(tasks) { task in
            TaskRow(task: task)
        }
    }
}
```

### With Predicates

```swift
struct ActiveTasksView: View {
    // Static predicate
    @Query(filter: #Predicate<Task> { !$0.isCompleted },
           sort: \.dueDate)
    private var activeTasks: [Task]

    var body: some View {
        List(activeTasks) { task in
            TaskRow(task: task)
        }
    }
}
```

### Dynamic Filtering

Use init to create dynamic queries based on parameters:

```swift
struct FilteredTasksView: View {
    @Query private var tasks: [Task]

    init(projectID: UUID, showCompleted: Bool) {
        let predicate: Predicate<Task>
        if showCompleted {
            predicate = #Predicate { $0.project?.id == projectID }
        } else {
            predicate = #Predicate { $0.project?.id == projectID && !$0.isCompleted }
        }
        _tasks = Query(filter: predicate, sort: \.createdAt, order: .reverse)
    }

    var body: some View {
        List(tasks) { task in
            TaskRow(task: task)
        }
    }
}
```

### Multiple Sort Descriptors

```swift
@Query(sort: [
    SortDescriptor(\Task.priority, order: .reverse),  // High priority first
    SortDescriptor(\Task.dueDate),                     // Then by due date
    SortDescriptor(\Task.title)                         // Then alphabetical
])
private var tasks: [Task]
```

### Fetch Limit

```swift
// Only show the 10 most recent
@Query(sort: \.createdAt, order: .reverse)
private var recentTasks: [Task]

init() {
    var descriptor = FetchDescriptor<Task>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    descriptor.fetchLimit = 10
    _recentTasks = Query(descriptor)
}
```

## FetchDescriptor (In ViewModels/Services)

Use `FetchDescriptor` for programmatic fetches outside SwiftUI views.

### Basic Fetch

```swift
func fetchAllProjects(context: ModelContext) throws -> [Project] {
    let descriptor = FetchDescriptor<Project>(
        sortBy: [SortDescriptor(\.name)]
    )
    return try context.fetch(descriptor)
}
```

### With Predicate

```swift
func fetchOverdueTasks(context: ModelContext) throws -> [Task] {
    let now = Date.now
    let descriptor = FetchDescriptor<Task>(
        predicate: #Predicate { $0.dueDate != nil && $0.dueDate! < now && !$0.isCompleted },
        sortBy: [SortDescriptor(\.dueDate)]
    )
    return try context.fetch(descriptor)
}
```

### Pagination

```swift
func fetchTasks(page: Int, pageSize: Int, context: ModelContext) throws -> [Task] {
    var descriptor = FetchDescriptor<Task>(
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchOffset = page * pageSize
    descriptor.fetchLimit = pageSize
    return try context.fetch(descriptor)
}
```

### Count Without Fetching

```swift
func countActiveTasks(context: ModelContext) throws -> Int {
    let descriptor = FetchDescriptor<Task>(
        predicate: #Predicate { !$0.isCompleted }
    )
    return try context.fetchCount(descriptor)
}
```

### Fetch Specific Properties Only

Reduce memory by fetching only needed properties:

```swift
func fetchTaskTitles(context: ModelContext) throws -> [Task] {
    var descriptor = FetchDescriptor<Task>()
    descriptor.propertiesToFetch = [\.title, \.isCompleted]
    return try context.fetch(descriptor)
}
```

### Fetch Identifiers Only

For even lighter fetches:

```swift
func fetchTaskIDs(context: ModelContext) throws -> [PersistentIdentifier] {
    let descriptor = FetchDescriptor<Task>(
        predicate: #Predicate { $0.isCompleted }
    )
    return try context.fetchIdentifiers(descriptor)
}
```

## Predicate Patterns

### String Matching

```swift
// Contains (case-sensitive)
#Predicate<Task> { $0.title.contains("urgent") }

// Starts with
#Predicate<Task> { $0.title.starts(with: "Bug:") }

// Case-insensitive contains
#Predicate<Task> { $0.title.localizedStandardContains(searchText) }
```

### Date Ranges

```swift
// Tasks due this week
let startOfWeek = Calendar.current.startOfWeek(for: .now)
let endOfWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: startOfWeek)!

#Predicate<Task> {
    $0.dueDate != nil &&
    $0.dueDate! >= startOfWeek &&
    $0.dueDate! < endOfWeek
}
```

### Optional Handling

```swift
// Tasks with no due date
#Predicate<Task> { $0.dueDate == nil }

// Tasks with a due date
#Predicate<Task> { $0.dueDate != nil }

// Safe optional comparison
#Predicate<Task> {
    if let dueDate = $0.dueDate {
        dueDate < Date.now
    } else {
        false
    }
}
```

### Relationship Queries

```swift
// Tasks belonging to a specific project
let projectID = someProject.id
#Predicate<Task> { $0.project?.id == projectID }

// Projects that have overdue tasks
let now = Date.now
#Predicate<Project> {
    $0.tasks.contains(where: { !$0.isCompleted && $0.dueDate != nil && $0.dueDate! < now })
}
```

### Enum Comparisons

```swift
// Tasks with high priority
let highPriority = Priority.high
#Predicate<Task> { $0.priority == highPriority }

// Note: you cannot use enum cases directly in predicates
// Wrong: #Predicate<Task> { $0.priority == .high }
// Right: capture the value in a local variable first
```

### Compound Predicates

```swift
// Combine multiple conditions
func buildPredicate(
    searchText: String,
    showCompleted: Bool,
    priority: Priority?
) -> Predicate<Task> {
    #Predicate<Task> { task in
        (searchText.isEmpty || task.title.localizedStandardContains(searchText)) &&
        (showCompleted || !task.isCompleted) &&
        (priority == nil || task.priority == priority)
    }
}
```

## @Query vs FetchDescriptor

| Feature | @Query | FetchDescriptor |
|---------|--------|-----------------|
| Where to use | SwiftUI views | ViewModels, services |
| Auto-updates | Yes | No (manual re-fetch) |
| Dynamic filtering | Via init() | Direct property setting |
| Pagination | Via init() | fetchOffset + fetchLimit |
| Count queries | No | fetchCount() |
| ID-only queries | No | fetchIdentifiers() |
| Background context | No | Yes |

## Common Mistakes

### Predicate Capture Issues

```swift
// Wrong - computed property in predicate
#Predicate<Task> { $0.dueDate! < Date.now }  // Date.now evaluated once, not live

// Right - capture the date
let now = Date.now
#Predicate<Task> { $0.dueDate != nil && $0.dueDate! < now }
```

### Fetching in a Loop

```swift
// Wrong - N+1 query problem
for project in projects {
    let tasks = try context.fetch(FetchDescriptor<Task>(
        predicate: #Predicate { $0.project?.id == project.id }
    ))
    // Process tasks
}

// Right - single fetch with all needed data
let allTasks = try context.fetch(FetchDescriptor<Task>())
let tasksByProject = Dictionary(grouping: allTasks) { $0.project?.id }
```

### Ignoring Fetch Limits

```swift
// Wrong - fetches all 100k records for a "recent" display
@Query(sort: \.createdAt, order: .reverse)
private var recentDocuments: [Document]
// Then only showing first 10 in the UI

// Right - limit the fetch
init() {
    var descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    descriptor.fetchLimit = 10
    _recentDocuments = Query(descriptor)
}
```

## Best Practices

1. **Use @Query for view data** - Auto-updates when data changes
2. **Use FetchDescriptor for service logic** - More control, background context support
3. **Always set fetchLimit for bounded displays** - Don't fetch 10k records for a top-10 list
4. **Capture predicate values in local variables** - Especially dates and enum cases
5. **Use fetchCount for existence checks** - Cheaper than fetching full objects
6. **Avoid N+1 queries** - Fetch related data in bulk, not per-item
7. **Use propertiesToFetch for partial loads** - Reduce memory for list views
