import AppKit
import CoreGraphics
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Canvas coordinates are output pixels, with a top-left origin. Images keep
/// their original decoded pixels; fitting the editor never replaces the source.
struct CompositionScreenshot: Identifiable {
    let id: UUID
    let image: CGImage
    var name: String
    var frame: CGRect
    var cornerRadius: CGFloat
    var shadow: CGFloat
    var shadowStyle: AnnotationShadowStyle = .soft
}

enum ScreenshotCompositionLayout: String, CaseIterable, Identifiable {
    case row = "Row", column = "Column", grid = "Grid"
    var id: String { rawValue }
}

struct ScreenshotComposition {
    var revision = UUID()
    var size = CGSize(width: 2400, height: 1600)
    var padding: CGFloat = 100
    var spacing: CGFloat = 60
    var background: AnnotationBackgroundStyle = .none
    /// Back to front, matching Core Graphics drawing order.
    var screenshots: [CompositionScreenshot] = []

    var contentRect: CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: padding, dy: padding)
    }

    /// Small canvas placements must not silently discard Retina capture detail.
    /// Auto chooses one canvas scale that keeps every source at least native size.
    var sourceResolutionScale: CGFloat {
        screenshots.reduce(CGFloat(1)) { scale, item in
            max(scale, CGFloat(item.image.width) / max(1, item.frame.width),
                CGFloat(item.image.height) / max(1, item.frame.height))
        }
    }

    func fittedFrame(_ frame: CGRect) -> CGRect {
        let bounds = contentRect
        let ratio = min(1, bounds.width / max(1, frame.width), bounds.height / max(1, frame.height))
        let width = max(1, frame.width * ratio).rounded()
        let height = max(1, frame.height * ratio).rounded()
        return CGRect(x: min(max(frame.minX.rounded(), bounds.minX), bounds.maxX - width),
                      y: min(max(frame.minY.rounded(), bounds.minY), bounds.maxY - height),
                      width: width, height: height)
    }

    mutating func arrange(_ layout: ScreenshotCompositionLayout) {
        let count = screenshots.count
        guard count > 0 else { return }
        let columns = layout == .row ? count : layout == .column ? 1 : Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        // Large layer counts must never produce negative cells.
        let gap = min(spacing, contentRect.width / CGFloat(columns * 2), contentRect.height / CGFloat(rows * 2))
        let cell = CGSize(width: (contentRect.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                          height: (contentRect.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
        for index in screenshots.indices {
            let image = screenshots[index].image
            let scale = min(cell.width / CGFloat(image.width), cell.height / CGFloat(image.height))
            let width = max(1, floor(CGFloat(image.width) * scale))
            let height = max(1, floor(CGFloat(image.height) * scale))
            screenshots[index].frame = CGRect(
                x: (padding + CGFloat(index % columns) * (cell.width + gap) + (cell.width - width) / 2).rounded(),
                y: (padding + CGFloat(index / columns) * (cell.height + gap) + (cell.height - height) / 2).rounded(),
                width: width, height: height)
        }
    }
}

@MainActor @Observable
final class ScreenshotCompositionModel {
    private(set) var document = ScreenshotComposition()
    var selectedID: UUID?
    var errorMessage: String?
    private var undoStack: [ScreenshotComposition] = []
    private var redoStack: [ScreenshotComposition] = []
    private var editing = false
    private var recordedEdit = false
    private var exportedRevision: UUID?
    private let defaultLook: AnnotationBackgroundSettings

    init(defaultLook: AnnotationBackgroundSettings? = nil) {
        let defaultLook = defaultLook ?? AppPreferences.defaultBeautifierConfig.annotationBackgroundSettings
        self.defaultLook = defaultLook
        document.background = defaultLook.style
        document.padding = min(300, max(0, defaultLook.padding * 1600))
    }

    var selection: CompositionScreenshot? { document.screenshots.first { $0.id == selectedID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasUnexportedChanges: Bool { !document.screenshots.isEmpty && document.revision != exportedRevision }

    func beginEditing() { editing = true; recordedEdit = false }
    func endEditing() { editing = false; recordedEdit = false }

    func change(_ update: (inout ScreenshotComposition) -> Void) {
        if !editing || !recordedEdit {
            undoStack.append(document)
            if undoStack.count > 60 { undoStack.removeFirst() }
            redoStack.removeAll()
            recordedEdit = true
        }
        update(&document)
        document.revision = UUID()
    }

    func updateSelected(_ update: (inout CompositionScreenshot) -> Void) {
        guard let index = document.screenshots.firstIndex(where: { $0.id == selectedID }) else { return }
        change { update(&$0.screenshots[index]) }
    }

    func undo() {
        endEditing()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document); document = previous
        repairSelection()
    }

    func redo() {
        endEditing()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document); document = next
        repairSelection()
    }

    private func repairSelection() {
        if !document.screenshots.contains(where: { $0.id == selectedID }) { selectedID = document.screenshots.last?.id }
    }

    func markExported(_ revision: UUID) { exportedRevision = revision }

    func importImages(_ urls: [URL]) {
        var imported: [CompositionScreenshot] = []
        var failed: [String] = []
        var pixelCount = document.screenshots.reduce(0) { $0 + $1.image.width * $1.image.height }
        for url in urls {
            guard document.screenshots.count + imported.count < 24,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, Double(width) * Double(height) <= 64_000_000,
                  Double(pixelCount) + Double(width) * Double(height) <= 128_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else {
                failed.append(url.lastPathComponent); continue
            }
            pixelCount += image.width * image.height
            let scale = min(1, document.contentRect.width * 0.7 / CGFloat(image.width),
                            document.contentRect.height * 0.7 / CGFloat(image.height))
            let frame = document.fittedFrame(CGRect(x: document.padding + CGFloat(imported.count * 30),
                y: document.padding + CGFloat(imported.count * 30),
                width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
            imported.append(CompositionScreenshot(id: UUID(), image: image, name: url.lastPathComponent,
                frame: frame, cornerRadius: defaultLook.cornerRadius, shadow: defaultLook.shadow,
                shadowStyle: defaultLook.shadowStyle))
        }
        if !imported.isEmpty {
            change { $0.screenshots.append(contentsOf: imported) }
            selectedID = imported.last?.id
        }
        errorMessage = failed.isEmpty ? nil : "Could not import: \(failed.joined(separator: ", ")). Use a supported image, up to 24 images, 64 MP each and 128 MP total."
    }

    func moveSelection(by delta: Int) {
        guard let index = document.screenshots.firstIndex(where: { $0.id == selectedID }),
              document.screenshots.indices.contains(index + delta) else { return }
        change { $0.screenshots.swapAt(index, index + delta) }
    }

    func removeSelection() {
        change { $0.screenshots.removeAll { $0.id == selectedID } }
        selectedID = document.screenshots.last?.id
    }

    func resizeCanvas(_ size: CGSize) {
        change { doc in
            doc.size = CGSize(width: min(6000, max(400, size.width.rounded())),
                              height: min(6000, max(400, size.height.rounded())))
            doc.padding = min(doc.padding, min(doc.size.width, doc.size.height) / 4)
            for index in doc.screenshots.indices { doc.screenshots[index].frame = doc.fittedFrame(doc.screenshots[index].frame) }
        }
    }
}

nonisolated enum ScreenshotCompositionRenderer {
    static func outputSize(_ document: ScreenshotComposition, scale: CGFloat) throws -> CGSize {
        let width = (document.size.width * scale).rounded()
        let height = (document.size.height * scale).rounded()
        guard scale.isFinite, scale > 0, width.isFinite, height.isFinite,
              width >= 1, height >= 1, width <= 16384, height <= 16384,
              width * height <= 64_000_000 else {
            throw NSError(domain: "BetterShot.Composition", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Export is limited to 64 megapixels and 16,384 pixels per edge. Choose a smaller canvas or export scale."])
        }
        return CGSize(width: width, height: height)
    }

    static func render(_ document: ScreenshotComposition, scale: CGFloat) throws -> CGImage {
        let size = try outputSize(document, scale: scale)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        context.scaleBy(x: scale, y: scale)
        AnnotationBackgroundRenderer.drawBackground(document.background, in: CGRect(origin: .zero, size: document.size), context: context)
        context.interpolationQuality = .high
        for item in document.screenshots {
            // Snap in final output pixels, including non-integer Auto scales.
            // Subpixel translation otherwise filters even a native-size image.
            let pixelWidth = max(1, (item.frame.width * scale).rounded())
            let pixelHeight = max(1, (item.frame.height * scale).rounded())
            let rect = CGRect(x: (item.frame.minX * scale).rounded() / scale,
                              y: (size.height - (item.frame.maxY * scale).rounded()) / scale,
                              width: pixelWidth / scale, height: pixelHeight / scale)
            let radius = min(rect.width, rect.height) * item.cornerRadius
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            AnnotationBackgroundRenderer.drawShadow(path: path, knockoutPath: path, strength: item.shadow,
                                                    style: item.shadowStyle, context: context)
            context.saveGState()
            context.addPath(path); context.clip()
            context.interpolationQuality = pixelWidth == CGFloat(item.image.width)
                && pixelHeight == CGFloat(item.image.height) ? .none : .high
            context.draw(item.image, in: rect)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    static func export(_ document: ScreenshotComposition, scale: CGFloat, to url: URL) throws {
        let image = try render(document, scale: scale)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: url, options: .atomic)
    }
}
