# Continuity Features

Cross-device integration between macOS, iOS, and iPadOS.

## Universal Clipboard

```swift
// ✅ Copy to universal clipboard
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(text, forType: .string)
// Automatically syncs to other devices

// ✅ Monitor clipboard changes
NotificationCenter.default.addObserver(
    forName: NSPasteboard.didChangeNotification,
    object: nil,
    queue: .main
) { _ in
    handleClipboardChange()
}
```

## Handoff

```swift
// ✅ Enable Handoff
func setupHandoff() {
    let activity = NSUserActivity(activityType: "com.app.editing")
    activity.title = "Editing Document"
    activity.userInfo = ["documentID": document.id.uuidString]
    activity.isEligibleForHandoff = true
    activity.becomeCurrent()
}

// ✅ Continue activity from another device
func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
) -> Bool {
    if userActivity.activityType == "com.app.editing",
       let documentID = userActivity.userInfo?["documentID"] as? String {
        openDocument(id: documentID)
        return true
    }
    return false
}
```

## AirDrop Integration

```swift
import AppKit

// ✅ Share via AirDrop
let sharingService = NSSharingService(named: .sendViaAirDrop)
sharingService?.perform(withItems: [url])

// ✅ Receive AirDrop files
func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
        handleReceivedFile(url)
    }
}
```

## Resources

- [Continuity Documentation](https://developer.apple.com/documentation/foundation/nsuseractivity)
