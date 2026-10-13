import AppKit

@main
enum EditorCloseGuardCheck {
    @MainActor
    static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
        _ = NSApplication.shared
        checkForwardingLifetime()
        checkCloseCleanup()
        print("EditorCloseGuardCheck: delegate forwarding survives owner release and detaches on close")
    }

    @MainActor
    private static func checkForwardingLifetime() {
        let window = makeWindow()
        let closeGuard = EditorCloseGuard()
        weak var original: WindowDelegateProbe?
        autoreleasepool {
            let delegate = WindowDelegateProbe()
            original = delegate
            window.delegate = delegate
            closeGuard.attach(to: window)
        }

        autoreleasepool {
            precondition(original != nil, "The guard must retain the delegate whose callbacks it advertises")
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            precondition(original?.becameKeyCount == 1, "AppKit notifications must reach the original delegate")
        }

        autoreleasepool {
            let delegate = original!
            closeGuard.detach()
            precondition(window.delegate === delegate, "Detaching must restore the original delegate")
        }
        precondition(original == nil, "Detaching must release the retained delegate")
        window.close()
    }

    @MainActor
    private static func checkCloseCleanup() {
        let window = makeWindow()
        let closeGuard = EditorCloseGuard()
        weak var original: WindowDelegateProbe?
        var closeCount = 0
        autoreleasepool {
            let delegate = WindowDelegateProbe()
            delegate.onClose = { closeCount += 1 }
            original = delegate
            window.delegate = delegate
            closeGuard.attach(to: window)
        }

        autoreleasepool { window.close() }
        precondition(closeCount == 1, "Closing must still notify the original delegate")
        precondition(original == nil, "Closing must release the original delegate without waiting for view disappearance")
        precondition(window.delegate !== closeGuard, "A closed window must no longer send callbacks to the guard")
        // Mirrors the queued focus notification that followed startup-window teardown on macOS 14.
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    }

    @MainActor
    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}

@MainActor
private final class WindowDelegateProbe: NSObject, NSWindowDelegate {
    var becameKeyCount = 0
    var onClose: () -> Void = {}

    func windowDidBecomeKey(_ notification: Notification) {
        becameKeyCount += 1
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
