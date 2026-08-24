# Sandboxing and Entitlements

App Sandbox requirements, security-scoped bookmarks, and file access patterns for macOS apps.

## App Sandbox Fundamentals

The App Sandbox restricts your app to a container directory and limits access to system resources. It is **required** for Mac App Store distribution.

### What the Sandbox Restricts

| Resource | Default Access | How to Enable |
|----------|---------------|---------------|
| File system | App container only | Entitlements + user consent |
| Network | None | `network.client` / `network.server` |
| Camera | None | `device.camera` + usage description |
| Microphone | None | `device.microphone` + usage description |
| Location | None | `personal-information.location` |
| Contacts | None | `personal-information.addressbook` |
| Calendar | None | `personal-information.calendars` |
| USB | None | `device.usb` |
| Printing | None | `print` |
| Apple Events | None | `automation.apple-events` |

### Container Directory

```swift
// These resolve to the container automatically
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
```

## File Access Patterns

### User-Selected Files (Open/Save Panels)

The sandbox grants temporary access to files the user explicitly selects:

```swift
// Open panel - user selects a file
let panel = NSOpenPanel()
panel.allowedContentTypes = [.png, .jpeg, .pdf]
panel.allowsMultipleSelection = true

let response = await panel.begin()
if response == .OK {
    for url in panel.urls {
        // Access is granted for this session only
        let data = try Data(contentsOf: url)
        processFile(data)
    }
}
```

**Entitlement required:**
```xml
<key>com.apple.security.files.user-selected.read-only</key><true/>
<!-- or for read-write: -->
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

### Security-Scoped Bookmarks

Persist access to user-selected files/folders across app launches:

```swift
class BookmarkManager {
    private let bookmarkKey = "savedBookmarks"

    /// Save a bookmark for a user-selected URL
    func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) ?? [:]
        bookmarks[url.path] = bookmarkData
        UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
    }

    /// Restore access from a saved bookmark
    func restoreBookmark(for path: String) -> URL? {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey),
              let data = bookmarks[path] as? Data else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-save the bookmark
            try? saveBookmark(for: url)
        }

        return url
    }

    /// Access a bookmarked resource (must be balanced with stopAccessingSecurityScopedResource)
    func accessResource(at url: URL, work: (URL) throws -> Void) rethrows {
        guard url.startAccessingSecurityScopedResource() else {
            throw SandboxError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        try work(url)
    }
}
```

**Entitlement required:**
```xml
<key>com.apple.security.files.bookmarks.app-scope</key><true/>
<!-- For sharing bookmarks between apps: -->
<key>com.apple.security.files.bookmarks.document-scope</key><true/>
```

### Critical: Start/Stop Access Pairing

Always balance `startAccessingSecurityScopedResource()` with `stopAccessingSecurityScopedResource()`:

```swift
// Wrong - never stops accessing
let url = restoreBookmark(for: path)!
url.startAccessingSecurityScopedResource()
let data = try Data(contentsOf: url)
// Leaked security scope!

// Right - use defer
guard url.startAccessingSecurityScopedResource() else { return }
defer { url.stopAccessingSecurityScopedResource() }
let data = try Data(contentsOf: url)
```

### Folder Access Pattern

Let users select a folder, then access all files within it:

```swift
func selectWorkingFolder() async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Select a folder to grant access"

    let response = await panel.begin()
    guard response == .OK, let url = panel.url else { return nil }

    // Save bookmark for persistent access
    try? bookmarkManager.saveBookmark(for: url)
    return url
}

func listFiles(in folderURL: URL) throws -> [URL] {
    guard folderURL.startAccessingSecurityScopedResource() else {
        throw SandboxError.accessDenied
    }
    defer { folderURL.stopAccessingSecurityScopedResource() }

    let contents = try FileManager.default.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: .skipsHiddenFiles
    )
    return contents
}
```

## Related Items (Implicitly Accessed Files)

Access files related to a user-selected file (e.g., .srt subtitle for a .mp4 video):

```xml
<!-- Info.plist - declare related file types -->
<key>NSServices</key>
<array>
    <dict>
        <key>NSRelatedItemsContentTypes</key>
        <array>
            <string>public.plain-text</string>
        </array>
    </dict>
</array>
```

## Temporary Exceptions

For direct distribution (outside Mac App Store), you can use temporary exceptions:

```xml
<!-- Access specific paths (NOT allowed on Mac App Store) -->
<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
<array>
    <string>/usr/local/bin/</string>
</array>
```

## Common Sandbox Rejection Reasons

| Issue | Solution |
|-------|----------|
| Accessing files without user consent | Use NSOpenPanel or security-scoped bookmarks |
| Network access without entitlement | Add `network.client` entitlement |
| Writing outside container | Use Powerbox (panels) or bookmarks |
| Apple Events without entitlement | Add `automation.apple-events` + target app in Info.plist |
| Hardcoded paths (e.g., `~/Desktop`) | Use system APIs (`FileManager.urls(for:)`) |

## Testing Sandbox

```bash
# Verify sandbox is active
codesign -dvvv --entitlements :- /path/to/MyApp.app

# Check sandbox violations in Console.app
# Filter by process name and "sandbox" or "deny"

# Run with sandbox enforcement in debug
# Product > Scheme > Edit Scheme > Run > Arguments
# Add environment variable: APP_SANDBOX_CONTAINER_ID = <bundle-id>
```

## Best Practices

1. **Enable sandbox early** - Retrofitting is painful; start sandboxed
2. **Request minimal entitlements** - Only what you actually need
3. **Always use security-scoped bookmarks** - For any persistent file access
4. **Handle access failures gracefully** - `startAccessingSecurityScopedResource` can return false
5. **Test in sandboxed mode** - Don't disable sandbox for debugging
6. **Use NSOpenPanel for user consent** - The sandbox Powerbox handles the rest
