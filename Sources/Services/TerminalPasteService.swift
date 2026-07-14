import AppKit
import CoreGraphics
import Carbon

/// Pastes clipboard images into terminal apps as file paths on plain ⌘V, so
/// tools like Claude Code pick them up as `[Image #1]` — the same effect as
/// dragging the file into the terminal window.
///
/// When the frontmost app is a known terminal and the clipboard holds a pure
/// image (no text), ⌘V is swallowed by the global event tap, the image is
/// resolved to a file on disk, and a synthetic ⌘V pastes its shell-escaped
/// path as text. The original clipboard is restored right after, so the image
/// can still be pasted into GUI apps.
@MainActor
final class TerminalPasteService {
    static let shared = TerminalPasteService()

    /// Marks synthetic ⌘V events posted by this service so the event tap
    /// lets them through instead of intercepting them again.
    nonisolated static let syntheticEventUserData: Int64 = 0x42535450 // "BSTP"

    /// Apps where ⌘V with an image on the clipboard should become a file-path paste.
    private let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
    ]

    private let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp",
    ]

    /// Last file BetterShot itself copied to the clipboard, so ⌘V can paste
    /// the already-saved screenshot's path without writing a duplicate PNG.
    private var lastCopiedURL: URL?
    private var lastCopiedChangeCount: Int = -1

    private let saveDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/BetterShot", isDirectory: true)

    private init() {}

    /// Call after writing a saved screenshot to the clipboard.
    func noteCopiedToClipboard(_ url: URL) {
        lastCopiedURL = url
        lastCopiedChangeCount = NSPasteboard.general.changeCount
    }

    /// Called from the global event tap for a plain ⌘V key-down.
    /// Returns true when the paste was handled (the original ⌘V is swallowed).
    func interceptCommandV() -> Bool {
        guard AppPreferences.terminalPasteEnabled else { return false }
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              terminalBundleIDs.contains(bundleID)
        else { return false }
        guard let (text, fileURL) = pasteTextFromPasteboard() else { return false }

        DispatchQueue.main.async { [weak self] in
            self?.pasteAsText(text, representing: fileURL)
        }
        return true
    }

    // MARK: - Clipboard → file path

    /// Returns the text to paste (escaped image path(s)) plus the single file
    /// backing the clipboard image (when there is one), or nil when the
    /// clipboard content should be pasted normally.
    private func pasteTextFromPasteboard() -> (text: String, fileURL: URL?)? {
        let pb = NSPasteboard.general

        // Screenshot just captured by BetterShot: reuse the saved file.
        if pb.changeCount == lastCopiedChangeCount,
           let url = lastCopiedURL,
           FileManager.default.fileExists(atPath: url.path) {
            return (shellEscape(url.path) + " ", url)
        }

        // Copied file(s): paste their paths directly, but only when ALL are images.
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let images = urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            guard images.count == urls.count else { return nil }
            let text = images.map { shellEscape($0.path) }.joined(separator: " ") + " "
            return (text, images.count == 1 ? images[0] : nil)
        }

        // Text on the clipboard means the user copied text — don't interfere.
        if pb.string(forType: .string) != nil { return nil }

        // Raw image data (e.g. screenshot copied from another app): save as PNG.
        let pngData: Data?
        if let png = pb.data(forType: .png) {
            pngData = png
        } else if let tiff = pb.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff) {
            pngData = rep.representation(using: .png, properties: [:])
        } else {
            pngData = nil
        }
        guard let data = pngData else { return nil }

        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var url = saveDir.appendingPathComponent("paste-\(formatter.string(from: Date())).png")
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = saveDir.appendingPathComponent("paste-\(formatter.string(from: Date()))-\(counter).png")
            counter += 1
        }
        do {
            try data.write(to: url)
        } catch {
            NSLog("BetterShot: terminal paste failed to save image: \(error)")
            return nil
        }
        return (shellEscape(url.path) + " ", url)
    }

    /// Backslash-escape the same characters a terminal drag & drop would.
    private func shellEscape(_ path: String) -> String {
        let specials: Set<Character> = [
            " ", "'", "\"", "(", ")", "&", ";", "|", "<", ">",
            "$", "`", "\\", "!", "*", "?", "[", "]", "{", "}", "#",
        ]
        var out = ""
        for ch in path {
            if specials.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    // MARK: - Paste

    private func pasteAsText(_ text: String, representing fileURL: URL?) {
        let pb = NSPasteboard.general

        // Snapshot the current clipboard so it can be restored after the paste.
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        pb.clearContents()
        pb.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.userData = Self.syntheticEventUserData
        let vKey = CGKeyCode(kVK_ANSI_V)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        // Restore the original clipboard (the image) after the terminal has pasted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            pb.clearContents()
            pb.writeObjects(saved)
            if let self, let fileURL {
                // Restoring bumps changeCount — re-note the backing file so a
                // repeated ⌘V reuses it instead of saving a duplicate PNG.
                self.noteCopiedToClipboard(fileURL)
            }
        }
    }

    // MARK: - Housekeeping

    /// Removes paste PNGs older than 7 days. Call once on launch.
    func cleanupOldImages() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: saveDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for file in files where file.lastPathComponent.hasPrefix("paste-") && file.pathExtension.lowercased() == "png" {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
