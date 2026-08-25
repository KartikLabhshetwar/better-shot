# SwiftData Schema Design

Best practices for @Model design, relationships, and attributes. Focus on normalization, cascade rules, and unique constraints.

## @Model Basics

```swift
import SwiftData

@Model
class Project {
    var name: String
    var createdAt: Date
    var isArchived: Bool

    // Optional properties
    var notes: String?
    var dueDate: Date?

    // Relationships
    var tasks: [Task]

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.isArchived = false
        self.tasks = []
    }
}
```

## Attributes

### @Attribute Options

```swift
@Model
class Document {
    // Unique constraint
    #Unique<Document>([\.slug])

    var title: String
    var slug: String

    // Stored as external binary data (large blobs)
    @Attribute(.externalStorage) var imageData: Data?

    // Spotlight indexable
    @Attribute(.spotlight) var searchableTitle: String

    // Encrypted at rest (preserves value through transforms)
    @Attribute(.allowsCloudEncryption) var sensitiveNotes: String?

    // Transient - not persisted
    @Transient var isSelected = false

    // Transformable custom types (must conform to Codable)
    var metadata: [String: String] = [:]
    var tags: [String] = []

    init(title: String) {
        self.title = title
        self.slug = title.slugified()
        self.searchableTitle = title
    }
}
```

### Supported Property Types

| Type | Supported | Notes |
|------|-----------|-------|
| String, Int, Double, Bool | Yes | Native support |
| Date, UUID, URL, Data | Yes | Native support |
| Optional versions | Yes | Maps to nullable columns |
| Arrays of value types | Yes | Stored as transformable |
| Dictionaries | Yes | Must be Codable |
| Enums | Yes | Must be Codable |
| Other @Model classes | Yes | Relationships |
| Custom Codable structs | Yes | Stored as transformable |

### Enums in Models

```swift
enum Priority: Int, Codable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case urgent = 3
}

enum Status: String, Codable {
    case draft, active, completed, archived
}

@Model
class Task {
    var title: String
    var priority: Priority
    var status: Status

    init(title: String, priority: Priority = .medium) {
        self.title = title
        self.priority = priority
        self.status = .draft
    }
}
```

## Relationships

### One-to-Many

```swift
@Model
class Author {
    var name: String
    // Inverse relationship inferred automatically
    var books: [Book]

    init(name: String) {
        self.name = name
        self.books = []
    }
}

@Model
class Book {
    var title: String
    // SwiftData infers inverse from Author.books
    var author: Author?

    init(title: String, author: Author? = nil) {
        self.title = title
        self.author = author
    }
}
```

### Many-to-Many

```swift
@Model
class Student {
    var name: String
    var courses: [Course]

    init(name: String) {
        self.name = name
        self.courses = []
    }
}

@Model
class Course {
    var title: String
    var students: [Student]

    init(title: String) {
        self.title = title
        self.students = []
    }
}

// Usage
let student = Student(name: "Alice")
let course = Course(title: "Swift 101")
student.courses.append(course)
// SwiftData manages the join table automatically
```

### Cascade Delete Rules

```swift
@Model
class Project {
    var name: String

    // Delete project → delete all tasks (cascade)
    @Relationship(deleteRule: .cascade)
    var tasks: [Task]

    // Delete project → set task.project to nil (nullify)
    @Relationship(deleteRule: .nullify)
    var optionalTasks: [Task]

    // Delete project → block if tasks exist (deny)
    @Relationship(deleteRule: .deny)
    var requiredTasks: [Task]

    init(name: String) {
        self.name = name
        self.tasks = []
        self.optionalTasks = []
        self.requiredTasks = []
    }
}
```

### Choosing Delete Rules

| Rule | Behavior | Use When |
|------|----------|----------|
| `.cascade` | Delete children when parent deleted | Children have no meaning without parent |
| `.nullify` | Set reference to nil | Children can exist independently |
| `.deny` | Prevent parent deletion if children exist | Children must be handled first |
| `.noAction` | Do nothing (leaves orphans) | Rarely appropriate |

## Unique Constraints

Prevent duplicate records:

```swift
@Model
class Contact {
    #Unique<Contact>([\.email])

    var email: String
    var name: String
    var phone: String?

    init(email: String, name: String) {
        self.email = email
        self.name = name
    }
}

// Multi-property uniqueness
@Model
class Enrollment {
    #Unique<Enrollment>([\.studentID, \.courseID])

    var studentID: UUID
    var courseID: UUID
    var enrolledAt: Date

    init(studentID: UUID, courseID: UUID) {
        self.studentID = studentID
        self.courseID = courseID
        self.enrolledAt = .now
    }
}
```

### Upsert Behavior

When inserting a model that violates a unique constraint, SwiftData performs an upsert:

```swift
// First insert creates the record
let contact = Contact(email: "alice@example.com", name: "Alice")
modelContext.insert(contact)

// Second insert with same email updates the existing record
let updated = Contact(email: "alice@example.com", name: "Alice Smith")
modelContext.insert(updated)  // Updates the existing record, doesn't create duplicate
try modelContext.save()
```

## Schema Versioning and Migration

### Lightweight Migration (Automatic)

SwiftData handles these automatically:
- Adding new properties with default values
- Making a required property optional
- Renaming properties (with `@Attribute(originalName:)`)

```swift
@Model
class Task {
    @Attribute(originalName: "name") var title: String  // Renamed from "name"
    var priority: Priority
    var createdAt: Date  // New property with default
    var notes: String?   // New optional property

    init(title: String, priority: Priority = .medium) {
        self.title = title
        self.priority = priority
        self.createdAt = .now
    }
}
```

### Custom Migration

For complex changes, use VersionedSchema and SchemaMigrationPlan:

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [TaskV1.self] }

    @Model class TaskV1 {
        var name: String
        init(name: String) { self.name = name }
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [TaskV2.self] }

    @Model class TaskV2 {
        var title: String
        var priority: Int
        init(title: String, priority: Int = 0) {
            self.title = title
            self.priority = priority
        }
    }
}

enum TaskMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    ) { context in
        let tasks = try context.fetch(FetchDescriptor<SchemaV1.TaskV1>())
        for task in tasks {
            // Transform data during migration
        }
        try context.save()
    }
}
```

## Design Guidelines

### Do

- Use value types (enums, Codable structs) for embedded data
- Set sensible defaults in initializers
- Use optional for truly optional data
- Add unique constraints for natural keys (email, slug, etc.)
- Use cascade delete for owned children
- Keep models focused — avoid god objects

### Don't

- Don't store computed values that can be derived from other properties
- Don't use @Model for value-type data (use Codable structs instead)
- Don't create circular cascade deletes
- Don't store large binary data inline — use `@Attribute(.externalStorage)`
- Don't add business logic to @Model classes — keep them pure data
