# Repository Pattern with SwiftData

Protocol-based data abstraction for testable, flexible data access. The repository sits between ViewModels and SwiftData, hiding persistence details.

## Why Use a Repository

| Without Repository | With Repository |
|-------------------|-----------------|
| ViewModel talks directly to ModelContext | ViewModel talks to a protocol |
| Can't unit test without SwiftData | Can test with mock/in-memory implementations |
| Locked to SwiftData | Can swap to Core Data, network, or file-based storage |
| ModelContext leaks into view layer | Clean separation of concerns |

## Basic Repository Protocol

```swift
protocol TaskRepository: Sendable {
    func fetchAll() async throws -> [TaskDTO]
    func fetch(id: UUID) async throws -> TaskDTO?
    func create(_ task: TaskDTO) async throws
    func update(_ task: TaskDTO) async throws
    func delete(id: UUID) async throws
    func count(matching predicate: Predicate<TaskDTO>?) async throws -> Int
}
```

### Data Transfer Objects (DTOs)

Use plain structs to decouple ViewModels from @Model classes:

```swift
struct TaskDTO: Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var priority: Priority
    var dueDate: Date?
    var projectID: UUID?
    var createdAt: Date
}
```

### Mapping Between @Model and DTO

```swift
extension TaskModel {
    var toDTO: TaskDTO {
        TaskDTO(
            id: id,
            title: title,
            isCompleted: isCompleted,
            priority: priority,
            dueDate: dueDate,
            projectID: project?.id,
            createdAt: createdAt
        )
    }

    func update(from dto: TaskDTO) {
        title = dto.title
        isCompleted = dto.isCompleted
        priority = dto.priority
        dueDate = dto.dueDate
    }
}
```

## SwiftData Repository Implementation

```swift
@ModelActor
actor SwiftDataTaskRepository: TaskRepository {
    func fetchAll() async throws -> [TaskDTO] {
        let descriptor = FetchDescriptor<TaskModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.toDTO)
    }

    func fetch(id: UUID) async throws -> TaskDTO? {
        let descriptor = FetchDescriptor<TaskModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first?.toDTO
    }

    func create(_ task: TaskDTO) async throws {
        let model = TaskModel(
            id: task.id,
            title: task.title,
            priority: task.priority,
            dueDate: task.dueDate
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    func update(_ task: TaskDTO) async throws {
        let id = task.id
        let descriptor = FetchDescriptor<TaskModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        model.update(from: task)
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        let descriptor = FetchDescriptor<TaskModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        modelContext.delete(model)
        try modelContext.save()
    }

    func count(matching predicate: Predicate<TaskDTO>?) async throws -> Int {
        let descriptor = FetchDescriptor<TaskModel>()
        return try modelContext.fetchCount(descriptor)
    }
}
```

### @ModelActor

The `@ModelActor` macro creates an actor with its own `ModelContext`, enabling safe background data operations:

```swift
@ModelActor
actor DataWorker {
    // modelContext is automatically provided
    // modelExecutor is automatically provided

    func importData(_ items: [ImportItem]) async throws {
        for item in items {
            let model = TaskModel(from: item)
            modelContext.insert(model)
        }
        try modelContext.save()
    }
}

// Create with a ModelContainer
let worker = DataWorker(modelContainer: container)
try await worker.importData(items)
```

## In-Memory Repository for Testing

```swift
actor InMemoryTaskRepository: TaskRepository {
    private var tasks: [UUID: TaskDTO] = [:]

    func fetchAll() async throws -> [TaskDTO] {
        Array(tasks.values).sorted { $0.createdAt > $1.createdAt }
    }

    func fetch(id: UUID) async throws -> TaskDTO? {
        tasks[id]
    }

    func create(_ task: TaskDTO) async throws {
        tasks[task.id] = task
    }

    func update(_ task: TaskDTO) async throws {
        guard tasks[task.id] != nil else { throw RepositoryError.notFound }
        tasks[task.id] = task
    }

    func delete(id: UUID) async throws {
        guard tasks[id] != nil else { throw RepositoryError.notFound }
        tasks[id] = nil
    }

    func count(matching predicate: Predicate<TaskDTO>?) async throws -> Int {
        tasks.count
    }

    // Test helpers
    func seed(_ seedTasks: [TaskDTO]) {
        for task in seedTasks {
            tasks[task.id] = task
        }
    }

    func reset() {
        tasks.removeAll()
    }
}
```

## ViewModel Using Repository

```swift
@Observable
@MainActor
class TaskListViewModel {
    private let repository: TaskRepository

    var tasks: [TaskDTO] = []
    var isLoading = false
    var errorMessage: String?

    init(repository: TaskRepository) {
        self.repository = repository
    }

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tasks = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleCompletion(_ task: TaskDTO) async {
        var updated = task
        updated.isCompleted.toggle()

        do {
            try await repository.update(updated)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTask(_ task: TaskDTO) async {
        do {
            try await repository.delete(id: task.id)
            tasks.removeAll { $0.id == task.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

## Dependency Injection

### Via SwiftUI Environment

```swift
// Environment key
struct TaskRepositoryKey: EnvironmentKey {
    static let defaultValue: TaskRepository = InMemoryTaskRepository()
}

extension EnvironmentValues {
    var taskRepository: TaskRepository {
        get { self[TaskRepositoryKey.self] }
        set { self[TaskRepositoryKey.self] = newValue }
    }
}

// In the app
@main
struct MyApp: App {
    let container: ModelContainer

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.taskRepository, SwiftDataTaskRepository(modelContainer: container))
        }
    }
}

// In previews
#Preview {
    let repo = InMemoryTaskRepository()
    // seed with sample data
    ContentView()
        .environment(\.taskRepository, repo)
}
```

### Via Initializer

```swift
struct TaskListView: View {
    @State private var viewModel: TaskListViewModel

    init(repository: TaskRepository) {
        _viewModel = State(initialValue: TaskListViewModel(repository: repository))
    }

    var body: some View {
        List(viewModel.tasks) { task in
            TaskRow(task: task)
        }
        .task { await viewModel.loadTasks() }
    }
}
```

## Testing

```swift
import Testing

@Suite struct TaskListViewModelTests {
    let repository = InMemoryTaskRepository()

    @Test func loadTasks() async {
        let sampleTasks = [
            TaskDTO(id: UUID(), title: "Task 1", isCompleted: false, priority: .medium, createdAt: .now),
            TaskDTO(id: UUID(), title: "Task 2", isCompleted: true, priority: .high, createdAt: .now),
        ]
        await repository.seed(sampleTasks)

        let viewModel = await TaskListViewModel(repository: repository)
        await viewModel.loadTasks()

        await #expect(viewModel.tasks.count == 2)
        await #expect(viewModel.errorMessage == nil)
    }

    @Test func toggleCompletion() async {
        let task = TaskDTO(id: UUID(), title: "Test", isCompleted: false, priority: .medium, createdAt: .now)
        await repository.seed([task])

        let viewModel = await TaskListViewModel(repository: repository)
        await viewModel.loadTasks()
        await viewModel.toggleCompletion(task)

        let updated = try? await repository.fetch(id: task.id)
        #expect(updated?.isCompleted == true)
    }

    @Test func deleteTask() async {
        let task = TaskDTO(id: UUID(), title: "Delete me", isCompleted: false, priority: .low, createdAt: .now)
        await repository.seed([task])

        let viewModel = await TaskListViewModel(repository: repository)
        await viewModel.loadTasks()
        await viewModel.deleteTask(task)

        await #expect(viewModel.tasks.isEmpty)
        let count = try? await repository.count(matching: nil)
        #expect(count == 0)
    }
}
```

## When to Use (and Not Use) Repository Pattern

### Use When
- You need unit-testable ViewModels
- You might swap data sources (SwiftData, network, file)
- Multiple ViewModels access the same data
- You want to add caching or transformation layers

### Skip When
- Simple CRUD app with 1-2 screens
- @Query in views is sufficient
- You won't write tests for the data layer
- Prototyping or MVPs

## Best Practices

1. **Use DTOs** - Don't leak @Model types outside the repository
2. **Use @ModelActor for background work** - Thread-safe by design
3. **Keep repository methods focused** - One operation per method
4. **Return DTOs, not models** - Prevents accidental mutations outside the repository
5. **Use actor isolation** - Repository should be an actor for thread safety
6. **Seed test repositories** - Provide helper methods for setting up test data
7. **Save explicitly** - Don't rely on auto-save; call `modelContext.save()` after mutations
