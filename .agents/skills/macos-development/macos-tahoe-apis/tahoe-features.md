# macOS Tahoe Features

New and enhanced features in macOS 26 (Tahoe).

## Redesigned Spotlight Search

### Quick Actions API

```swift
import AppKit

// ✅ Register Spotlight quick actions
extension AppDelegate {
    func registerSpotlightActions() {
        let action = NSUserActivity(activityType: "com.app.createDocument")
        action.title = "Create New Document"
        action.isEligibleForSearch = true
        action.isEligibleForPrediction = true

        // Add to Spotlight
        action.becomeCurrent()
    }
}

// Handle quick action
func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
) -> Bool {
    if userActivity.activityType == "com.app.createDocument" {
        createNewDocument()
        return true
    }
    return false
}
```

### Third-Party Spotlight Integration

```swift
import CoreSpotlight

// ✅ Index content for Spotlight
func indexArticle(_ article: Article) {
    let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
    attributeSet.title = article.title
    attributeSet.contentDescription = article.content
    attributeSet.keywords = article.tags
    attributeSet.thumbnailData = article.thumbnail

    let item = CSSearchableItem(
        uniqueIdentifier: article.id.uuidString,
        domainIdentifier: "com.app.articles",
        attributeSet: attributeSet
    )

    CSSearchableIndex.default().indexSearchableItems([item]) { error in
        if let error = error {
            print("Indexing error: \(error)")
        }
    }
}

// ✅ Handle Spotlight selection
func handleSpotlightSelection(_ uniqueIdentifier: String) {
    guard let articleID = UUID(uuidString: uniqueIdentifier) else { return }
    openArticle(id: articleID)
}
```

## Phone App on Mac (Continuity)

### Making Calls from Mac

```swift
// ✅ Tel links automatically open in Phone app
Link("Call Support", destination: URL(string: "tel:1-800-555-0123")!)

// ✅ FaceTime links
Link("FaceTime", destination: URL(string: "facetime:user@example.com")!)

// Check if calling is available
if let url = URL(string: "tel:1-800-555-0123"),
   NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
    // Phone app available
}
```

## Control Center Integration

### Custom Control Center Widgets

```swift
// Note: Control Center customization is system-level
// Apps can provide widgets through WidgetKit

import WidgetKit
import SwiftUI

struct ControlWidget: Widget {
    let kind: String = "ControlWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ControlWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Control")
        .description("Quick access control")
        .supportedFamilies([.systemSmall])
    }
}

struct ControlWidgetView: View {
    let entry: Provider.Entry

    var body: some View {
        VStack {
            Image(systemName: "power")
                .font(.largeTitle)
            Text("Toggle")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
```

## Custom Folder Icons and Emblems

### Programmatic Icon Customization

```swift
import AppKit

// ✅ Set custom folder icon
func setCustomFolderIcon(for url: URL, icon: NSImage) {
    NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
}

// ✅ Get folder icon
func getFolderIcon(for url: URL) -> NSImage? {
    NSWorkspace.shared.icon(forFile: url.path)
}

// ✅ Support accent color in icons
let icon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
icon?.isTemplate = true  // Respects accent color
```

## Edge Light for Video Calls

### Detecting Low Light Conditions

```swift
import AVFoundation

// ✅ Monitor camera light conditions
class CameraMonitor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Analyze brightness
        let brightness = calculateBrightness(imageBuffer)

        if brightness < 0.3 {
            // Low light - Edge Light will activate automatically
            print("Low light detected")
        }
    }

    private func calculateBrightness(_ imageBuffer: CVImageBuffer) -> Double {
        // Implementation
        return 0.0
    }
}

// Note: Edge Light is automatic in system video call apps
// Third-party apps can detect conditions but system handles the feature
```

## Thunderbolt 5 Multi-Mac Support

### Detecting Multi-Mac Cluster

```swift
import IOKit

// ✅ Check for Thunderbolt 5 connections
func detectThunderbolt5() -> Bool {
    // Query IOKit for Thunderbolt 5 controllers
    // This is a low-level API check
    return false  // Placeholder
}

// ✅ Distributed computing setup
// Use distributed actor frameworks for multi-Mac processing
```

## High-Priority Reminders

### Creating High-Priority Reminders

EventKit has no "urgent" flag — `EKReminder.priority` is the standard 1–9
scale (1 = highest). Reminders surfaces priority 1 as a high-priority item;
there is no separate urgent state on macOS 26.

```swift
import EventKit

// ✅ Create high-priority reminder
func createHighPriorityReminder() async throws {
    let eventStore = EKEventStore()
    guard try await eventStore.requestFullAccessToReminders() else { return }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = "Important Task"
    reminder.calendar = eventStore.defaultCalendarForNewReminders()

    // Set due date
    let dueDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
    reminder.dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute],
        from: dueDate!
    )

    reminder.priority = 1  // 1–9 scale; 1 = highest

    try eventStore.save(reminder, commit: true)
}
```

## macOS Tahoe Checklist

- [ ] Integrate with redesigned Spotlight (quick actions, indexing)
- [ ] Support Phone app links (tel:, facetime:)
- [ ] Consider Control Center widgets (WidgetKit)
- [ ] Support custom folder icons and accent colors
- [ ] Detect low light for video features (if applicable)
- [ ] Consider Thunderbolt 5 for distributed computing
- [ ] Use urgent reminders API correctly

## Resources

- [macOS 26 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes)
- [Core Spotlight Framework](https://developer.apple.com/documentation/corespotlight)
- [WidgetKit Documentation](https://developer.apple.com/documentation/widgetkit)
