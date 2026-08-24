import AppKit

@main
enum EditorCloseGuardCheck {
    @MainActor static var failures: [String] = []

    @MainActor
    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    @MainActor
    static func main() {
        let guardian = EditorCloseGuard.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let other = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)

        check(guardian.shouldClose(window), "an unregistered window must close without asking")

        var prompts = 0
        var hasEdits = true
        guardian.register(window) {
            guard hasEdits else { return true }
            prompts += 1
            return false
        }

        check(!guardian.shouldClose(window), "an edited window must not close on the first attempt")
        check(prompts == 1, "the close attempt must raise exactly one prompt, raised \(prompts)")
        check(guardian.shouldClose(other), "the guard must only hold back the window it was registered for")

        _ = guardian.shouldClose(window)
        check(prompts == 2, "every close attempt on an edited window prompts again, raised \(prompts)")

        hasEdits = false
        check(guardian.shouldClose(window), "a clean window must close straight away")
        check(prompts == 2, "a clean window must not prompt, raised \(prompts)")

        hasEdits = true
        guardian.unregister(window)
        check(guardian.shouldClose(window), "unregistering must release the window even while edited")
        check(prompts == 2, "an unregistered window must not prompt, raised \(prompts)")

        if failures.isEmpty {
            print("EditorCloseGuardCheck: all assertions passed")
        } else {
            failures.forEach { FileHandle.standardError.write(Data("FAIL: \($0)\n".utf8)) }
            exit(1)
        }
    }
}
