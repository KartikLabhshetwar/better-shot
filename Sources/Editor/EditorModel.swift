import AppKit
import SwiftUI

@MainActor
@Observable
final class EditorModel {
    var sourceImage: CGImage?
    var sourceURL: URL?
    var config = BeautifierConfig.default

    private var past: [Snapshot] = []
    private var future: [Snapshot] = []
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    private struct Snapshot {
        let config: BeautifierConfig
    }

    // MARK: - Load

    func loadImage(from url: URL) {
        sourceURL = url
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        sourceImage = image

        if let data = UserDefaults.standard.data(forKey: "bs_defaultBeautifierConfig"),
           let saved = try? JSONDecoder().decode(BeautifierConfig.self, from: data) {
            config = saved
        }
    }

    // MARK: - History

    func pushHistory() {
        let snap = Snapshot(config: config)
        past.append(snap)
        if past.count > 50 { past.removeFirst() }
        future.removeAll()
    }

    func undo() {
        guard let prev = past.popLast() else { return }
        future.insert(Snapshot(config: config), at: 0)
        config = prev.config
    }

    func redo() {
        guard !future.isEmpty else { return }
        let next = future.removeFirst()
        past.append(Snapshot(config: config))
        config = next.config
    }

    // MARK: - Config Updates

    func updateConfig(_ update: (inout BeautifierConfig) -> Void) {
        pushHistory()
        update(&config)
    }

    // MARK: - Render

    func renderFinal() -> CGImage? {
        guard let image = sourceImage else { return nil }
        return BeautifierRenderer.render(image: image, config: config)
    }

    // MARK: - Save Config as Default

    func saveConfigAsDefault() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "bs_defaultBeautifierConfig")
        }
    }
}
