import AppKit
import SwiftUI

let fired = Notification.Name("EditorWindowCloseCheck.fire")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("EditorWindowCloseCheck: " + message + "\n").utf8))
    exit(1)
}

func pass(_ message: String) -> Never {
    FileHandle.standardOutput.write(Data(("EditorWindowCloseCheck: " + message + "\n").utf8))
    exit(0)
}

struct EditorStandIn: View {
    @State private var confirming = false
    @State private var hostWindow: NSWindow?

    var body: some View {
        Color.clear
            .frame(width: 320, height: 200)
            .hostWindow($hostWindow)
            .confirmationDialog("Delete this capture?", isPresented: $confirming) {
                Button("Delete", role: .destructive) {
                    Probe.keyWindowInsideAction = NSApp.keyWindow
                    Probe.hostWindowInsideAction = hostWindow
                    hostWindow?.close()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onReceive(NotificationCenter.default.publisher(for: fired)) { _ in confirming = true }
    }
}

enum Probe {
    nonisolated(unsafe) static var keyWindowInsideAction: NSWindow?
    nonisolated(unsafe) static var hostWindowInsideAction: NSWindow?
}

func allButtons(in view: NSView?) -> [NSButton] {
    guard let view else { return [] }
    var found: [NSButton] = []
    if let button = view as? NSButton { found.append(button) }
    for sub in view.subviews { found += allButtons(in: sub) }
    return found
}

final class CheckDelegate: NSObject, NSApplicationDelegate {
    var editor: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        editor = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        editor.title = "Editor"
        editor.contentView = NSHostingView(rootView: EditorStandIn())
        editor.makeKeyAndOrderFront(nil)

        let editor = self.editor!
        after(0.8) {
            NotificationCenter.default.post(name: fired, object: nil)
            after(1.2) {
                guard let sheet = editor.attachedSheet else { fail("confirmation sheet never presented") }
                guard let delete = allButtons(in: sheet.contentView).first(where: { $0.title == "Delete" }) else {
                    fail("sheet had no Delete button: \(allButtons(in: sheet.contentView).map(\.title))")
                }
                delete.performClick(nil)
                after(1.0) {
                    if Probe.hostWindowInsideAction !== editor {
                        fail("hostWindow inside the sheet action was not the editor window")
                    }
                    if Probe.keyWindowInsideAction === editor {
                        pass("keyWindow happened to be the editor, and hostWindow closed it")
                    }
                    if editor.isVisible {
                        fail("editor window stayed open after the destructive action")
                    }
                    pass("keyWindow inside the sheet action was the alert panel, hostWindow still closed the editor")
                }
            }
        }
    }
}

func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(work) }
}

@main
enum EditorWindowCloseCheck {
    static func main() {
        let app = NSApplication.shared
        let delegate = CheckDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)

        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            fail("timed out waiting for the window to close")
        }

        app.run()
    }
}
