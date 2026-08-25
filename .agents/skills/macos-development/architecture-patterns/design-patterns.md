# Design Patterns for macOS

Common design patterns implemented in modern Swift for macOS applications. Each pattern includes when to use it, implementation, and real-world examples.

## MVVM (Model-View-ViewModel)

The primary pattern for SwiftUI macOS apps. The ViewModel owns business logic and exposes state the View observes.

### Implementation with @Observable

```swift
// Model
struct Task: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
}

// ViewModel
@Observable class TaskListViewModel {
    private let repository: TaskRepository

    var tasks: [Task] = []
    var filterOption: FilterOption = .all
    var errorMessage: String?

    var filteredTasks: [Task] {
        switch filterOption {
        case .all: tasks
        case .active: tasks.filter { !$0.isCompleted }
        case .completed: tasks.filter { $0.isCompleted }
        }
    }

    init(repository: TaskRepository) {
        self.repository = repository
    }

    func loadTasks() async {
        do {
            tasks = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleCompletion(_ task: Task) async {
        guard var updated = tasks.first(where: { $0.id == task.id }) else { return }
        updated.isCompleted.toggle()
        do {
            try await repository.save(updated)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// View
struct TaskListView: View {
    @State private var viewModel: TaskListViewModel

    init(repository: TaskRepository) {
        _viewModel = State(initialValue: TaskListViewModel(repository: repository))
    }

    var body: some View {
        List(viewModel.filteredTasks) { task in
            TaskRow(task: task) {
                Task { await viewModel.toggleCompletion(task) }
            }
        }
        .task { await viewModel.loadTasks() }
    }
}
```

### When to Use MVVM
- Any SwiftUI app with business logic beyond simple data display
- When you need testable business logic separate from the view
- When multiple views share the same state transformations

## Repository Pattern

Abstracts data access behind a protocol. The ViewModel doesn't know if data comes from a database, network, or cache.

```swift
protocol TaskRepository {
    func fetchAll() async throws -> [Task]
    func fetch(id: UUID) async throws -> Task?
    func save(_ task: Task) async throws
    func delete(_ task: Task) async throws
}

// SwiftData implementation
struct SwiftDataTaskRepository: TaskRepository {
    let modelContext: ModelContext

    func fetchAll() async throws -> [Task] {
        let descriptor = FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.dueDate)])
        return try modelContext.fetch(descriptor).map(\.toTask)
    }

    func save(_ task: Task) async throws {
        if let existing = try await fetch(id: task.id) as? TaskModel {
            existing.update(from: task)
        } else {
            modelContext.insert(TaskModel(from: task))
        }
        try modelContext.save()
    }

    func fetch(id: UUID) async throws -> Task? {
        let descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.toTask
    }

    func delete(_ task: Task) async throws {
        let descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == task.id })
        if let model = try modelContext.fetch(descriptor).first {
            modelContext.delete(model)
            try modelContext.save()
        }
    }
}

// In-memory implementation for tests and previews
struct InMemoryTaskRepository: TaskRepository {
    var tasks: [Task] = []

    func fetchAll() async throws -> [Task] { tasks }
    func fetch(id: UUID) async throws -> Task? { tasks.first { $0.id == id } }
    mutating func save(_ task: Task) async throws {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }
    mutating func delete(_ task: Task) async throws {
        tasks.removeAll { $0.id == task.id }
    }
}
```

### When to Use Repository
- Apps with persistence (SwiftData, Core Data, files)
- When you need to swap data sources (network vs. local)
- When you want testable data access without real databases

## Factory Pattern

Creates objects without exposing creation logic. Useful for building complex objects with varying configurations.

```swift
// Protocol for the product
protocol AlertPresenter {
    func show(title: String, message: String)
}

// Factory
enum AlertPresenterFactory {
    static func make(for context: AlertContext) -> AlertPresenter {
        switch context {
        case .modal:
            return ModalAlertPresenter()
        case .notification:
            return NotificationAlertPresenter()
        case .statusBar:
            return StatusBarAlertPresenter()
        }
    }
}

// More practical: ViewModel factory with dependencies
enum ViewModelFactory {
    static func makeTaskList(modelContext: ModelContext) -> TaskListViewModel {
        let repository = SwiftDataTaskRepository(modelContext: modelContext)
        return TaskListViewModel(repository: repository)
    }

    static func makeSettings(store: UserDefaults = .standard) -> SettingsViewModel {
        let preferences = UserDefaultsPreferences(store: store)
        return SettingsViewModel(preferences: preferences)
    }
}
```

### When to Use Factory
- Complex object creation with multiple dependencies
- When creation logic varies based on context or configuration
- Centralizing dependency wiring

## Observer Pattern

Built into Swift via Combine, @Observable, and NotificationCenter. Choose the right mechanism for the coupling level.

### @Observable (Tight Coupling)

```swift
@Observable class DownloadManager {
    var activeDownloads: [Download] = []
    var totalProgress: Double = 0.0
    var isDownloading: Bool { !activeDownloads.isEmpty }
}

// Views automatically observe accessed properties
struct DownloadStatusView: View {
    var manager: DownloadManager
    var body: some View {
        if manager.isDownloading {
            ProgressView(value: manager.totalProgress)
        }
    }
}
```

### Combine (Medium Coupling)

```swift
class FileWatcher {
    let fileChanged = PassthroughSubject<URL, Never>()

    func startWatching(_ directory: URL) {
        // FSEvents or DispatchSource monitoring
        // When file changes:
        fileChanged.send(changedURL)
    }
}

// Consumer
class EditorController {
    private var cancellables = Set<AnyCancellable>()

    init(watcher: FileWatcher) {
        watcher.fileChanged
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] url in
                self?.reloadFile(at: url)
            }
            .store(in: &cancellables)
    }
}
```

### When to Use Which Observer Mechanism
| Mechanism | Coupling | Use Case |
|-----------|----------|----------|
| @Observable | Tight | ViewModel-to-View data binding |
| Combine | Medium | Async streams, data transformation pipelines |
| AsyncSequence | Medium | Streaming data, server-sent events |

## Coordinator Pattern

Manages navigation flow, keeping ViewModels free of navigation logic. Most useful in large apps with complex flows.

```swift
@Observable class AppCoordinator {
    var selectedTab: Tab = .documents
    var navigationPath = NavigationPath()
    var presentedSheet: SheetDestination?
    var presentedAlert: AlertDestination?

    func showDocument(_ document: Document) {
        selectedTab = .documents
        navigationPath.append(document)
    }

    func showSettings() {
        presentedSheet = .settings
    }

    func showDeleteConfirmation(for document: Document) {
        presentedAlert = .deleteConfirmation(document)
    }

    func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        switch components.host {
        case "document":
            if let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                navigationPath.append(DocumentRoute(id: id))
            }
        case "settings":
            showSettings()
        default:
            break
        }
    }
}

// Usage in the root view
struct ContentView: View {
    @State private var coordinator = AppCoordinator()

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            NavigationStack(path: $coordinator.navigationPath) {
                DocumentListView()
                    .navigationDestination(for: Document.self) { doc in
                        DocumentDetailView(document: doc)
                    }
            }
            .tag(Tab.documents)
        }
        .sheet(item: $coordinator.presentedSheet) { destination in
            switch destination {
            case .settings: SettingsView()
            }
        }
        .environment(coordinator)
    }
}
```

### When to Use Coordinator
- Apps with complex navigation flows (onboarding, multi-step forms)
- Deep linking support
- When navigation logic is cluttering ViewModels
- Multi-window macOS apps

## Service Locator (Lightweight DI)

For small-to-medium apps where a full DI container is overkill.

```swift
@Observable class ServiceContainer {
    lazy var taskRepository: TaskRepository = SwiftDataTaskRepository(modelContext: modelContext)
    lazy var analytics: AnalyticsTracking = FirebaseTracker()
    lazy var networkMonitor: NetworkMonitor = SystemNetworkMonitor()

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
}

// Inject via SwiftUI environment
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(ServiceContainer(modelContext: modelContext))
        }
    }
}

// Consume in views
struct TaskListView: View {
    @Environment(ServiceContainer.self) private var services

    var body: some View {
        TaskListContent(repository: services.taskRepository)
    }
}
```

## Choosing the Right Pattern

| Scenario | Recommended Patterns |
|----------|---------------------|
| Simple CRUD app | MVVM + Repository |
| Multi-screen app with navigation | MVVM + Repository + Coordinator |
| App with swappable backends | Repository + Factory |
| Plugin/extension architecture | Factory + Observer |
