import AppKit
import SwiftUI

/// Central model for the annotation editor. Manages image, beautifier config,
/// annotations, and undo/redo history.
@MainActor
@Observable
final class EditorModel {
    // Image
    var sourceImage: CGImage?
    var sourceURL: URL?

    // Beautifier
    var config = BeautifierConfig.default

    // Annotations
    var annotations: [AnnotationItem] = []
    var selectedAnnotationID: UUID?
    var activeTool: AnnotationTool = .select

    // Undo / Redo
    private var past: [Snapshot] = []
    private var future: [Snapshot] = []
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    private struct Snapshot {
        let config: BeautifierConfig
        let annotations: [AnnotationItem]
    }

    // MARK: - Load

    func loadImage(from url: URL) {
        sourceURL = url
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        sourceImage = image

        // Load saved default config
        if let data = UserDefaults.standard.data(forKey: "bs_defaultBeautifierConfig"),
           let saved = try? JSONDecoder().decode(BeautifierConfig.self, from: data) {
            config = saved
        }
    }

    // MARK: - History

    func pushHistory() {
        let snap = Snapshot(config: config, annotations: annotations)
        past.append(snap)
        if past.count > 50 { past.removeFirst() }
        future.removeAll()
    }

    func undo() {
        guard let prev = past.popLast() else { return }
        future.insert(Snapshot(config: config, annotations: annotations), at: 0)
        config = prev.config
        annotations = prev.annotations
    }

    func redo() {
        guard !future.isEmpty else { return }
        let next = future.removeFirst()
        past.append(Snapshot(config: config, annotations: annotations))
        config = next.config
        annotations = next.annotations
    }

    // MARK: - Config Updates

    func updateConfig(_ update: (inout BeautifierConfig) -> Void) {
        pushHistory()
        update(&config)
    }

    // MARK: - Annotations

    func addAnnotation(_ item: AnnotationItem) {
        pushHistory()
        annotations.append(item)
        selectedAnnotationID = item.id
    }

    func updateAnnotation(_ item: AnnotationItem) {
        pushHistory()
        if let idx = annotations.firstIndex(where: { $0.id == item.id }) {
            annotations[idx] = item
        }
    }

    func deleteAnnotation(id: UUID) {
        pushHistory()
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id { selectedAnnotationID = nil }
    }

    func deleteSelected() {
        if let id = selectedAnnotationID {
            deleteAnnotation(id: id)
        }
    }

    // MARK: - Render

    func renderFinal() -> CGImage? {
        guard let image = sourceImage else { return nil }
        let items = self.annotations
        return BeautifierRenderer.render(image: image, config: config) { ctx, imageRect in
            for annotation in items {
                AnnotationDrawing.draw(annotation, in: ctx, imageRect: imageRect)
            }
        }
    }

    // MARK: - Save Config as Default

    func saveConfigAsDefault() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "bs_defaultBeautifierConfig")
        }
    }
}
