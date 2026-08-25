# Accessibility Best Practices

VoiceOver, keyboard navigation, Dynamic Type, and accessibility standards for macOS.

## VoiceOver Support

### Container-First Navigation (WWDC25 229)

Mac VoiceOver is driven by keyboard shortcuts (VO+Right Arrow to the next element) and,
unlike iOS, navigates **by container** — moving quickly across the app and only focusing
into a container when the user asks. Mac UIs are denser, and containers nest into a
tree of accessibility elements, so container structure matters more than on iPhone.
Shape it deliberately, and avoid excessive nesting — every extra level slows navigation.

```swift
// ✅ GOOD: Group related controls into one navigable container
VStack {
    FirstView()
    SecondView()
}
.accessibilityElement(children: .contain)

// ✅ GOOD: Merge a title + Apply pair into a single element
HStack {
    PresetTitleView(preset: preset)
    Button("Apply") { apply() }
}
.accessibilityElement(children: .combine)
```

Measured win from the session's Format Inspector demo (WWDC25 229): a flat scroll area of
22 swipe stops became 15 top-level items with an 8-item presets group — VoiceOver users
skip the whole group in one keystroke unless they want it.

If the reading order feels wrong under VoiceOver, fix it with `accessibilitySortPriority` (WWDC25 229):

```swift
VStack {
    Text(book.author)
    Text(book.title)
        .accessibilitySortPriority(1)   // title read before author
    DescriptionView(book: book)
}
.accessibilityElement(children: .combine)
```

### SwiftUI Accessibility

```swift
// ✅ GOOD: Accessibility labels
Button(action: save) {
    Image(systemName: "square.and.arrow.down")
}
.accessibilityLabel("Save document")
.accessibilityHint("Saves the current document to disk")

// ✅ GOOD: Combining elements
HStack {
    Image(systemName: "person.fill")
    Text("John Doe")
    Text("john@example.com")
}
.accessibilityElement(children: .combine)
.accessibilityLabel("John Doe, john@example.com")

// ✅ GOOD: Custom accessibility for complex views
struct ArticleCard: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading) {
            Text(article.title)
                .font(.headline)
            Text(article.subtitle)
                .font(.subheadline)
            Text(article.date, style: .date)
                .font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(article.title), \(article.subtitle)")
        .accessibilityHint("Published \(article.date, style: .date)")
        .accessibilityAddTraits(.isButton)
    }
}
```

### AppKit Accessibility

```swift
// ✅ GOOD: Accessibility in AppKit
final class CustomButton: NSButton {
    override func accessibilityLabel() -> String? {
        "Save document"
    }

    override func accessibilityHelp() -> String? {
        "Saves the current document to disk"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func isAccessibilityElement() -> Bool {
        true
    }
}

// ✅ GOOD: Setting accessibility programmatically
imageView.setAccessibilityLabel("Profile picture")
imageView.setAccessibilityRole(.image)

textField.setAccessibilityLabel("Username")
textField.setAccessibilityPlaceholderValue("Enter your username")
```

### Accessibility Traits

```swift
// ✅ GOOD: Adding traits
.accessibilityAddTraits(.isButton)
.accessibilityAddTraits(.isSelected)
.accessibilityAddTraits(.isHeader)
.accessibilityAddTraits(.startsMediaSession)

// ✅ GOOD: Removing default traits
.accessibilityRemoveTraits(.isImage)

// ✅ GOOD: Custom actions
.accessibilityAction(named: "Mark as Read") {
    markAsRead()
}
.accessibilityAction(named: "Delete") {
    delete()
}
```

### Hidden Elements

```swift
// ✅ GOOD: Hide decorative elements from VoiceOver
Image(decorative: "background-pattern")
    .accessibilityHidden(true)

// ✅ GOOD: Skip navigation elements
Divider()
    .accessibilityHidden(true)

Spacer()
    .accessibilityHidden(true)
```

### Rotors and Default Focus (WWDC25 229)

Give VoiceOver users a jump list for the content that matters, instead of stepping
through every item ("Page 2 bookmarked. Page 3. Page 4. Page 5 bookmarked…"):

```swift
// ✅ GOOD: Bookmarks rotor — jump straight between bookmarked pages
List(pages) { page in
    PageListItemView(page: page)
}
.accessibilityRotor("Bookmarks") {
    ForEach(pages) { page in
        if page.isBookmarked {
            AccessibilityRotorEntry(page.title, id: page.id)
        }
    }
}
```

Suggest where VoiceOver should land when a new window or scene opens — the system still
respects the user's preference (WWDC25 229):

```swift
@AccessibilityFocusState(for: .voiceOver) var focusedForVoiceOver

SecondView()
    .accessibilityDefaultFocus($focusedForVoiceOver, true)
```

### Hover-Revealed Controls (WWDC25 229)

Hover-only controls are invisible to VoiceOver users. Mirror every hover affordance as an accessibility action — it also serves Switch Control and Voice Control:

```swift
// ❌ BAD: bookmark button only appears .onHover — unreachable without a pointer
// ✅ GOOD: same operation exposed as an action
VStack {
    ThumbnailView(page: page)
    Text(page.title)
}
.onHover { isHovering = $0 }
.accessibilityAction(named: page.isBookmarked ? "Remove Bookmark" : "Bookmark") {
    page.isBookmarked.toggle()
}
```

## Keyboard Navigation

### Focus Management

```swift
// ✅ GOOD: Focus state
struct LoginView: View {
    @FocusState private var focusedField: Field?

    enum Field {
        case username, password
    }

    var body: some View {
        Form {
            TextField("Username", text: $username)
                .focused($focusedField, equals: .username)

            SecureField("Password", text: $password)
                .focused($focusedField, equals: .password)

            Button("Login") {
                login()
            }
            .disabled(!isFormValid)
        }
        .onAppear {
            focusedField = .username
        }
        .onSubmit {
            switch focusedField {
            case .username:
                focusedField = .password
            case .password:
                if isFormValid {
                    login()
                }
            default:
                break
            }
        }
    }
}
```

### Keyboard Shortcuts

Keyboard shortcuts are an accessibility feature, not just a power-user nicety (WWDC25 229) — cover common tasks, not only exotic ones.

```swift
// ✅ GOOD: Keyboard shortcuts with VoiceOver announcements
Button("New Document") {
    createDocument()
}
.keyboardShortcut("n", modifiers: .command)
.accessibilityLabel("New Document")
.accessibilityHint("Keyboard shortcut: Command N")

// ✅ GOOD: Custom key equivalent in AppKit
button.keyEquivalent = "n"
button.keyEquivalentModifierMask = .command
button.setAccessibilityHelp("Keyboard shortcut: Command N")
```

### Tab Navigation

```swift
// ✅ GOOD: Ensure proper tab order
.focusable(true)  // Make view focusable
.defaultFocus($focusedField, .username)  // Set initial focus

// AppKit: Use nextKeyView
usernameField.nextKeyView = passwordField
passwordField.nextKeyView = loginButton
loginButton.nextKeyView = usernameField
```

## Dynamic Type

### SwiftUI Text Scaling

```swift
// ✅ GOOD: Dynamic Type support
Text("Heading")
    .font(.title)  // Automatically scales

Text("Body")
    .font(.body)

// ✅ GOOD: Custom font with Dynamic Type
Text("Custom")
    .font(.custom("MyFont", size: 17, relativeTo: .body))

// ❌ BAD: Fixed font size
Text("Fixed")
    .font(.system(size: 14))  // Won't scale!

// ✅ GOOD: Fixed size when necessary, but allow scaling
Text("Fixed")
    .font(.system(size: 14))
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)  // Limit maximum size
```

### Custom Scaling

```swift
// ✅ GOOD: Scale custom elements
@ScaledMetric private var iconSize: CGFloat = 24

Image(systemName: "star")
    .font(.system(size: iconSize))

// ✅ GOOD: Responsive layouts
@Environment(\.dynamicTypeSize) var dynamicTypeSize

var body: some View {
    Group {
        if dynamicTypeSize >= .xxxLarge {
            VStack {  // Stack vertically for large text
                icon
                label
            }
        } else {
            HStack {  // Stack horizontally for normal text
                icon
                label
            }
        }
    }
}
```

## Color Contrast

### WCAG Compliance

```swift
// ✅ GOOD: Use semantic colors with sufficient contrast
.foregroundStyle(.primary)     // Always has good contrast
.foregroundStyle(.secondary)   // Good contrast for secondary text

// ❌ BAD: Low contrast
Text("Important")
    .foregroundColor(.gray)  // May not have sufficient contrast

// ✅ GOOD: High contrast with background
Text("Important")
    .foregroundColor(.white)
    .padding()
    .background(.blue)  // Sufficient contrast
```

### Increase Contrast Mode

```swift
// ✅ GOOD: Support increased contrast
@Environment(\.colorSchemeContrast) var contrast

var body: some View {
    Text("Content")
        .foregroundStyle(
            contrast == .increased ? .primary : .secondary
        )
}

// ✅ GOOD: Adjust border thickness
.border(
    .primary,
    width: contrast == .increased ? 2 : 1
)
```

## Reduce Motion

### Respecting Motion Preferences

```swift
// ✅ GOOD: Respect reduce motion
@Environment(\.accessibilityReduceMotion) var reduceMotion

func animate() {
    if reduceMotion {
        // Instant transition
        isExpanded = true
    } else {
        // Animated transition
        withAnimation(.spring()) {
            isExpanded = true
        }
    }
}

// ✅ GOOD: Conditional animation
.animation(reduceMotion ? .none : .spring(), value: isExpanded)
```

### Alternative Feedback

```swift
// ✅ GOOD: Provide alternative feedback for motion
if reduceMotion {
    // Use color change or haptic instead of animation
    backgroundColor = .accentColor
} else {
    withAnimation {
        scale = 1.1
    }
}
```

## VoiceOver Testing

### Testing Checklist

```swift
// Test VoiceOver with:
// 1. Enable VoiceOver: Cmd+F5
// 2. Navigate with VO+arrow keys
// 3. Interact with VO+Space
// 4. Use rotor: VO+U

// ✅ Verify:
// - All interactive elements are accessible
// - Labels are descriptive and clear
// - Images have appropriate descriptions or are hidden
// - Custom controls have proper roles
// - Table views announce correctly
// - Forms can be filled out completely
// - Buttons announce their action
```

### VoiceOver Debugging

```swift
// ✅ GOOD: Debug accessibility in Xcode
// 1. Run app in Simulator
// 2. Settings > Accessibility > VoiceOver
// 3. Use Accessibility Inspector
// Automated audits (performAccessibilityAudit — macOS has .action and .parentChild
// audit types) and Nutrition Label evaluation: see ios/accessibility-audit

// Print accessibility tree (debugging)
#if DEBUG
view.accessibilityElements?.forEach { element in
    print("Label: \((element as? NSObject)?.accessibilityLabel() ?? "none")")
}
#endif
```

## Accessibility in Tables and Lists

### SwiftUI Lists

```swift
// ✅ GOOD: Accessible list items
List(articles) { article in
    ArticleRow(article: article)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(article.title)
        .accessibilityValue("By \(article.author), \(article.date, style: .date)")
        .accessibilityHint("Double-tap to open")
        .accessibilityAddTraits(.isButton)
}
.accessibilityLabel("Articles")
.accessibilityHint("\(articles.count) articles")
```

### AppKit Tables

```swift
// ✅ GOOD: Accessible table cells
extension ArticleViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let article = articles[row]
        let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as! ArticleCellView

        cell.configure(with: article)

        // Accessibility
        cell.setAccessibilityLabel(article.title)
        cell.setAccessibilityValue("By \(article.author)")
        cell.setAccessibilityRole(.cell)

        return cell
    }
}
```

## Custom Controls

### Accessible Custom Button

```swift
// ✅ GOOD: Custom button with full accessibility
struct CustomIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to activate")
    }
}
```

### Accessible Custom Slider

```swift
// ✅ GOOD: Custom slider with accessibility
struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geometry in
            // Custom slider UI
            Rectangle()
                .gesture(dragGesture)
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + step, range.upperBound)
            case .decrement:
                value = max(value - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }
}
```

## Accessibility Checklist

- [ ] All interactive elements have labels
- [ ] Related controls grouped into containers, without excessive nesting (Mac VoiceOver navigates container-first)
- [ ] Reading order corrected with `accessibilitySortPriority` where visual position misleads
- [ ] Hover-only controls mirrored as accessibility actions (VoiceOver never moves the pointer)
- [ ] Long lists offer custom rotors for key content; new windows suggest a default VoiceOver focus
- [ ] Images have descriptions or are marked decorative
- [ ] Buttons announce their action
- [ ] Forms can be completed with VoiceOver
- [ ] Keyboard navigation works throughout app
- [ ] Tab order is logical
- [ ] Keyboard shortcuts are accessible
- [ ] Text supports Dynamic Type
- [ ] Custom fonts scale with system settings
- [ ] Color contrast meets WCAG AA (4.5:1)
- [ ] Important info not conveyed by color alone
- [ ] Increased contrast mode supported
- [ ] Reduce motion preference respected
- [ ] Alternative feedback for animations
- [ ] Custom controls have proper roles
- [ ] Tables and lists are navigable
- [ ] Test with VoiceOver enabled
- [ ] Test with keyboard only
- [ ] Test with increased text sizes

## Resources

- [Accessibility on macOS](https://developer.apple.com/accessibility/macos/)
- [VoiceOver Testing Guide](https://developer.apple.com/documentation/accessibility/voiceover)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [WWDC: Creating Accessible Apps](https://developer.apple.com/videos/accessibility)
