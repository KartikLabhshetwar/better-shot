//
//  AnnotationEditorModel.swift
//  BetterShot
//

import AppKit
import Observation
import SwiftUI

/// The editor window's model.
///
/// Annotations themselves live in `engine` - the ported drawing-app editor - which owns the
/// document, the selection and the pointer state machine. This type keeps the things that are
/// BetterShot's rather than the engine's: the image being edited, the background recipe, crop, zoom
/// and the inspector's current style.
@MainActor
@Observable
final class AnnotationEditorModel {
    /// The shape engine. Not observable itself, so `revision` stands in for it.
    @ObservationIgnored let engine = AnnoEditor()
    /// Bumped on every engine change. Views read this to pick up edits the engine made.
    private(set) var revision = 0

    /// The display/history image being edited. Used to match the preview item
    /// and to locate the sidecar document.
    var sourceURL: URL?
    /// The untouched image the annotations are rendered on top of. When
    /// re-editing an existing document this is the preserved base image;
    /// otherwise it is the same as `sourceURL`.
    var baseImageURL: URL?
    var previewImage: NSImage?
    /// The preview image's pixels, for the canvas's redaction passes to sample.
    @ObservationIgnored private(set) var previewCGImage: CGImage?
    /// Whether the currently displayed `previewImage` is a downscaled copy of
    /// the source (low-resolution preview preference). Exports are unaffected.
    var isPreviewDownscaled = false
    var imageSize: CGSize = .zero

    var selectedTool: AnnotationTool = .rectangle
    var selectedSwatch: AnnotationSwatch = .red
    var strokeWidth: CGFloat = 4
    var redactionDensity: CGFloat = 0.55
    var backgroundSettings = AnnotationBackgroundSettings()
    var appliedBackgroundPresetID: AnnotationBackgroundPreset.ID?
    var errorMessage: String?
    var isSmartRedacting = false
    var smartRedactionMessage: String?

    // MARK: Crop
    /// Whether the modal crop overlay is currently active.
    var isCropping = false
    /// The working crop rectangle, normalized to the image (0...1, top-left
    /// origin). Only meaningful while `isCropping` is true.
    var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// The aspect-ratio constraint applied while cropping.
    var cropAspect: CropAspectRatio = .freeform

    // MARK: Zoom & pan
    /// When `true` the canvas is scaled to fit the available viewport (default).
    var zoomToFit = true
    /// Absolute display scale used when `zoomToFit` is false.
    var manualZoomScale: CGFloat = 1
    /// Pan offset (in view points) applied when the zoomed content overflows the viewport.
    var panOffset: CGSize = .zero
    /// The live viewport size, published by `AnnotationCanvas`.
    var viewportSize: CGSize = .zero
    /// The backing scale factor of the canvas, published by `AnnotationCanvas`.
    var displayScale: CGFloat = 2

    static let minZoomPercent = 10
    static let maxZoomPercent = 400

    /// While cropping, the image is fit with this much breathing room (in
    /// points) on every side so the crop resize handles - which are centered on
    /// the crop edges - never spill outside the interactive canvas bounds.
    static let cropHandleMargin: CGFloat = 26

    // Text style defaults (applied to new text, updated when selecting existing text)
    var textFontFamily: AnnoFontFamily = .pro
    var textFontSize: CGFloat = 48
    var textIsBold = true
    var textIsItalic = false
    var textIsUnderline = false
    var textAlignment: NSTextAlignment = .left

    /// A full snapshot of the editor's image state, captured before a crop so
    /// the operation can be undone/redone.
    private struct CropSnapshot {
        var baseImageURL: URL?
        var imageSize: CGSize
        var shapes: [AnnoShape]
        var bindings: [ArrowBinding]
    }

    private var cropUndoStack: [CropSnapshot] = []
    private var cropRedoStack: [CropSnapshot] = []
    private var ownedCropURLs: Set<URL> = []

    /// Smallest crop dimension, in normalized units, derived from a pixel floor.
    private let minimumCropPixels: CGFloat = 24

    /// Longest-edge cap (in pixels) for the downscaled editing preview.
    private let previewImageMaxPixelSize: CGFloat = 2880

    init() {
        engine.onChange = { [weak self] in
            self?.revision &+= 1
        }
    }

    // MARK: - Engine surface

    var shapes: [AnnoShape] { engine.shapes }
    var bindings: [ArrowBinding] { engine.document.bindings }
    var hasAnnotations: Bool { !engine.shapes.isEmpty }
    var selectionCount: Int { engine.selectedIds.count }
    var editingTextID: AnnoShapeID? { engine.editingTextId }

    var isTransformingExistingAnnotation: Bool {
        switch engine.interaction {
        case .translating, .resizing, .rotating, .draggingArrowHandle: true
        default: false
        }
    }

    private var selectedShape: AnnoShape? {
        engine.selectedIds.count == 1 ? engine.selectedShapes.first : nil
    }

    var inspectedTool: AnnotationTool? {
        selectedShape?.tool
            ?? engine.selectedShapes.first?.tool
            ?? (selectedTool.createsAnnotation ? selectedTool : nil)
    }

    var isColorStyleAvailable: Bool { isStyleAvailable { $0.supportsColorStyle } }
    var isStrokeStyleAvailable: Bool { isStyleAvailable { $0.supportsStrokeStyle } }
    var isRedactionStyleAvailable: Bool { isStyleAvailable { $0.supportsRedactionDensityStyle } }

    var hasInspectorStyleControls: Bool {
        isTextStyleAvailable || isColorStyleAvailable || isStrokeStyleAvailable || isRedactionStyleAvailable
    }

    private func isStyleAvailable(_ supportsStyle: (AnnotationTool) -> Bool) -> Bool {
        let selected = engine.selectedShapes
        if selected.isEmpty {
            return inspectedTool.map(supportsStyle) ?? false
        }
        return selected.contains { supportsStyle($0.tool) }
    }

    // MARK: - Loading

    func load(url: URL?, dismiss: DismissAction) {
        guard let url else {
            dismiss()
            return
        }

        removeOwnedCropFiles()
        applyAnnotationPreset()
        resetZoom()
        sourceURL = url
        let document = ScreenshotHistoryStore.shared.loadEditDocument(for: url)
        let candidateBaseURL = ScreenshotHistoryStore.baseImageURL(for: url)
        let renderSourceURL: URL
        if let document,
           FileManager.default.fileExists(atPath: candidateBaseURL.path) {
            renderSourceURL = candidateBaseURL
            backgroundSettings = document.backgroundSettings
            appliedBackgroundPresetID = nil
        } else {
            renderSourceURL = url
            let presetStore = AnnotationBackgroundPresetStore.shared
            let activePreset = presetStore.activePreset
            backgroundSettings = document?.backgroundSettings
                ?? activePreset?.settings
                ?? AppPreferences.defaultBeautifierConfig.annotationBackgroundSettings
            appliedBackgroundPresetID = document == nil ? activePreset?.id : nil
        }

        baseImageURL = renderSourceURL
        imageSize = ScreenshotImageLoader.imageSize(at: renderSourceURL) ?? .zero
        previewImage = makePreviewImage(from: renderSourceURL)
        previewCGImage = previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)

        engine.viewport = AnnoViewport(imageFrame: .zero, imageSize: imageSize)
        engine.replaceDocument(
            shapes: document?.shapes ?? [],
            bindings: document?.bindings ?? []
        )
        engine.tool = selectedTool

        isCropping = false
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        cropAspect = .freeform
        cropUndoStack = []
        cropRedoStack = []
        RedactionImageProcessor.removeAllCachedPreviewImages()
        errorMessage = nil
        smartRedactionMessage = nil

        if previewImage == nil || imageSize == .zero {
            errorMessage = "Unable to load screenshot."
        }

        markSaved()
    }

    private func makePreviewImage(from url: URL) -> NSImage? {
        if BetterShotPreferences.lowResolutionEditorPreview {
            isPreviewDownscaled = max(imageSize.width, imageSize.height) > previewImageMaxPixelSize
            return ScreenshotImageLoader.downsampledImage(at: url, maxPixelSize: previewImageMaxPixelSize)
        } else {
            isPreviewDownscaled = false
            return ScreenshotImageLoader.fullResolutionImage(at: url)
        }
    }

    func releaseEditorResources() {
        removeOwnedCropFiles()
        RedactionImageProcessor.removeAllCachedPreviewImages()
    }

    // MARK: - Unsaved changes

    /// Everything a commit would persist. The crop rides along as the base
    /// image URL, since cropping replaces the image the annotations render on
    /// rather than adding anything to the document.
    private struct EditSnapshot: Equatable {
        var baseImageURL: URL?
        var shapes: [AnnoShape]
        var bindings: [ArrowBinding]
        var background: StoredBackground
    }

    private var savedSnapshot: EditSnapshot?

    private func currentSnapshot() -> EditSnapshot {
        EditSnapshot(
            baseImageURL: baseImageURL,
            shapes: shapes,
            bindings: bindings,
            background: StoredBackground(backgroundSettings)
        )
    }

    /// Whether closing now would throw work away. The baseline is taken at the
    /// end of `load` rather than from an empty document, so a background
    /// preset applied automatically on open is not mistaken for a user edit.
    var hasUnsavedChanges: Bool {
        // The engine isn't observable; touching `revision` is what makes this
        // recompute when a shape is drawn, moved, or deleted.
        _ = revision
        guard sourceURL != nil, let savedSnapshot else { return false }
        return currentSnapshot() != savedSnapshot
    }

    /// Re-baselines after a successful commit, and at the end of a load.
    func markSaved() {
        savedSnapshot = currentSnapshot()
    }

    // MARK: - Pointer

    /// Keep the engine's camera in step with where the canvas is drawing the image.
    func updateViewport(imageFrame: CGRect) {
        engine.viewport = AnnoViewport(imageFrame: imageFrame, imageSize: imageSize)
    }

    private func pointer(at location: CGPoint) -> PointerInfo {
        let flags = NSEvent.modifierFlags
        let screenPoint = Vec(location)
        return PointerInfo(
            screenPoint: screenPoint,
            pagePoint: engine.screenToPage(screenPoint),
            shift: flags.contains(.shift),
            alt: flags.contains(.option),
            command: flags.contains(.command)
        )
    }

    func beginInteraction(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard !isCropping else { return }
        updateViewport(imageFrame: imageFrame)
        engine.pointerDown(pointer(at: location))
        selectedTool = engine.tool
        syncStyleFromSelection()
    }

    func updateInteraction(to location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard !isCropping else { return }
        updateViewport(imageFrame: imageFrame)
        engine.pointerMove(pointer(at: location))
        selectedTool = engine.tool
    }

    func endInteraction(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard !isCropping else { return }
        updateViewport(imageFrame: imageFrame)
        engine.pointerUp(pointer(at: location))
        selectedTool = engine.tool
        syncStyleFromSelection()
    }

    func hoveredAnnotation(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) -> AnnoShape? {
        guard boundaryFrame.contains(location) else { return nil }
        updateViewport(imageFrame: imageFrame)
        return engine.hitShape(at: engine.screenToPage(Vec(location)))
    }

    /// Whether a selection handle sits under the pointer, so the canvas can show a resize cursor.
    func hoveredHandle(at location: CGPoint, imageFrame: CGRect) -> AnnoSelectionHandle? {
        updateViewport(imageFrame: imageFrame)
        return engine.handle(at: Vec(location))
    }

    func containsInteractionPoint(_ location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) -> Bool {
        boundaryFrame.contains(location)
    }

    // MARK: - Tools and style

    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        engine.tool = tool
        saveAnnotationPreset()
    }

    func setSwatch(_ swatch: AnnotationSwatch) {
        selectedSwatch = swatch
        engine.currentSwatch = swatch
        saveAnnotationPreset()

        engine.applyStyleToSelection { shape in
            switch shape.kind {
            case var .geo(p): p.swatch = swatch; shape.kind = .geo(p)
            case var .draw(p): p.swatch = swatch; shape.kind = .draw(p)
            case var .arrow(p): p.swatch = swatch; shape.kind = .arrow(p)
            case var .text(p): p.swatch = swatch; shape.kind = .text(p)
            case var .numbered(p): p.swatch = swatch; shape.kind = .numbered(p)
            case .redaction, .highlight: break
            }
        }
    }

    func setStrokeWidth(_ width: CGFloat) {
        strokeWidth = width
        engine.currentStrokeWidth = Double(width)
        saveAnnotationPreset()

        let pageWidth = engine.pageStrokeWidth(Double(width))
        engine.applyStyleToSelection { shape in
            switch shape.kind {
            case var .geo(p): p.strokeWidth = pageWidth; shape.kind = .geo(p)
            case var .draw(p): p.strokeWidth = pageWidth; shape.kind = .draw(p)
            case var .arrow(p): p.strokeWidth = pageWidth; shape.kind = .arrow(p)
            default: break
            }
        }
    }

    func setRedactionDensity(_ density: CGFloat) {
        redactionDensity = density
        engine.currentRedactionDensity = Double(density)
        saveAnnotationPreset()

        engine.applyStyleToSelection { shape in
            if case var .redaction(p) = shape.kind {
                p.density = Double(density)
                shape.kind = .redaction(p)
            }
        }
    }

    /// Pull the inspector's values from whatever is selected, so selecting a shape shows its style.
    private func syncStyleFromSelection() {
        guard let shape = selectedShape else { return }
        if let swatch = shape.swatch, shape.tool.supportsColorStyle {
            selectedSwatch = swatch
            engine.currentSwatch = swatch
        }
        if shape.tool.supportsStrokeStyle, shape.strokeWidth > 0 {
            strokeWidth = CGFloat(engine.sliderStrokeWidth(shape.strokeWidth))
            engine.currentStrokeWidth = Double(strokeWidth)
        }
        if let props = shape.redactionProps {
            redactionDensity = CGFloat(props.density)
            engine.currentRedactionDensity = props.density
        }
        if let props = shape.textProps {
            textFontFamily = props.fontFamily
            textFontSize = CGFloat(props.fontSize)
            textIsBold = props.isBold
            textIsItalic = props.isItalic
            textIsUnderline = props.isUnderline
            textAlignment = props.align.nsTextAlignment
        }
    }

    // MARK: - Editing commands

    func deleteSelectedAnnotation() {
        engine.deleteSelected()
    }

    func selectAllAnnotations() {
        selectedTool = .select
        engine.selectAll()
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        engine.nudgeSelected(dx: Double(dx), dy: Double(dy))
    }

    func commitTextEditing() {
        engine.stopEditingText()
    }

    func setText(_ text: String, for id: AnnoShapeID) {
        engine.updateEditingText(id, to: text)
    }

    var canUndo: Bool {
        !isCropping && (engine.canUndo || !cropUndoStack.isEmpty)
    }

    var canRedo: Bool {
        !isCropping && (engine.canRedo || !cropRedoStack.isEmpty)
    }

    func undo() {
        guard !isCropping else { return }
        if engine.canUndo {
            engine.undo()
            return
        }
        undoCrop()
    }

    func redo() {
        guard !isCropping else { return }
        if engine.canRedo {
            engine.redo()
            return
        }
        redoCrop()
    }

    // MARK: - Smart redaction

    func smartRedact(using tool: AnnotationTool) {
        guard tool.isRedactionTool,
              !isSmartRedacting,
              let recognitionURL = baseImageURL ?? sourceURL else {
            return
        }

        let loadedSourceURL = sourceURL
        isSmartRedacting = true
        smartRedactionMessage = nil

        Task { @MainActor in
            let regions = await SmartRedactionRecognizer.sensitiveRegions(at: recognitionURL)

            guard sourceURL == loadedSourceURL,
                  baseImageURL == recognitionURL || sourceURL == recognitionURL else {
                isSmartRedacting = false
                return
            }

            applySmartRedactionRegions(regions, tool: tool)
            isSmartRedacting = false
        }
    }

    private func applySmartRedactionRegions(_ regions: [SmartRedactionRegion], tool: AnnotationTool) {
        // Recognition reports normalized rects; page space is image pixels.
        let renderable = regions.compactMap { region -> AnnoShape? in
            let rect = CGRect(
                x: region.bounds.minX * imageSize.width,
                y: region.bounds.minY * imageSize.height,
                width: region.bounds.width * imageSize.width,
                height: region.bounds.height * imageSize.height
            )
            guard rect.width >= 2, rect.height >= 2 else { return nil }
            var props = RedactionProps()
            props.kind = tool == .blur ? .blur : .pixelate
            props.density = Double(redactionDensity)
            props.w = Double(rect.width)
            props.h = Double(rect.height)
            return AnnoShape(x: Double(rect.minX), y: Double(rect.minY), kind: .redaction(props))
        }

        guard !renderable.isEmpty else {
            smartRedactionMessage = "No sensitive text found."
            return
        }

        engine.markUndo()
        for shape in renderable { engine.document.add(shape) }
        engine.selectedIds = Set(renderable.map(\.id))
        selectedTool = tool
        engine.tool = tool
        engine.notifyChanged()
        smartRedactionMessage = "Added \(renderable.count) redaction\(renderable.count == 1 ? "" : "s")."
    }

    // MARK: - Bounds

    func annotationBounds(for imageFrame: CGRect, boundaryFrame: CGRect) -> CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: (boundaryFrame.minX - imageFrame.minX) / imageFrame.width,
            y: (boundaryFrame.minY - imageFrame.minY) / imageFrame.height,
            width: boundaryFrame.width / imageFrame.width,
            height: boundaryFrame.height / imageFrame.height
        )
    }

    // MARK: - Presets

    private func applyAnnotationPreset() {
        let preset = AnnotationPresetStore.load()
        selectedTool = preset.selectedTool
        selectedSwatch = preset.swatch
        strokeWidth = CGFloat(preset.strokeWidth)
        redactionDensity = CGFloat(preset.redactionDensity)
        textFontFamily = AnnoFontFamily(rawValue: preset.textFontName) ?? .pro
        textFontSize = CGFloat(preset.textFontSize)
        textIsBold = preset.textIsBold
        textIsItalic = preset.textIsItalic
        textIsUnderline = preset.textIsUnderline
        textAlignment = preset.textAlignment

        engine.tool = selectedTool
        engine.currentSwatch = selectedSwatch
        engine.currentStrokeWidth = Double(strokeWidth)
        engine.currentRedactionDensity = Double(redactionDensity)
        engine.currentFontFamily = textFontFamily
        engine.currentTextFontSize = Double(textFontSize)
        engine.currentTextIsBold = textIsBold
        engine.currentTextIsItalic = textIsItalic
        engine.currentTextIsUnderline = textIsUnderline
        engine.currentTextAlign = TextAlign(textAlignment)
    }

    func saveAnnotationPreset() {
        let customSwatch = AnnotationSwatch.allCases.contains(selectedSwatch) ? nil : CodableSwatch(swatch: selectedSwatch)
        let preset = AnnotationStylePreset(
            selectedToolRawValue: selectedTool.rawValue,
            swatchID: selectedSwatch.id,
            customSwatch: customSwatch,
            strokeWidth: Double(strokeWidth),
            redactionDensity: Double(redactionDensity),
            textFontName: textFontFamily.rawValue,
            textFontSize: Double(textFontSize),
            textIsBold: textIsBold,
            textIsItalic: textIsItalic,
            textIsUnderline: textIsUnderline,
            textAlignmentRawValue: textAlignment.rawValue
        )
        AnnotationPresetStore.save(preset)
    }

    /// Applies the complete reusable background recipe to this editor.
    func applyBackgroundPreset(_ preset: AnnotationBackgroundPreset) {
        backgroundSettings = preset.settings
        appliedBackgroundPresetID = preset.id
    }
}

// MARK: - Crop

extension AnnotationEditorModel {
    /// Whether the image has been cropped in this editing session (and can be undone).
    var isCropped: Bool { !cropUndoStack.isEmpty }

    /// Pixel dimensions of the current crop selection.
    var cropPixelSize: CGSize {
        CGSize(
            width: (cropRect.width * imageSize.width).rounded(),
            height: (cropRect.height * imageSize.height).rounded()
        )
    }

    func beginCropping() {
        guard imageSize != .zero, !isCropping else { return }

        commitTextEditing()
        engine.selectedIds.removeAll()
        cropAspect = .freeform
        cropRect = CropRectEditor.unit
        fitCanvas()
        isCropping = true
    }

    func cancelCrop() {
        guard isCropping else { return }
        isCropping = false
        cropRect = CropRectEditor.unit
        cropAspect = .freeform
    }

    func toggleCropping() {
        isCropping ? cancelCrop() : beginCropping()
    }

    func resetCrop() {
        guard isCropping else { return }
        if let ratio = cropAspect.normalizedRatio(imageSize: imageSize) {
            cropRect = CropRectEditor.applyAspect(to: CropRectEditor.unit, aspect: ratio)
        } else {
            cropRect = CropRectEditor.unit
        }
    }

    func setCropAspect(_ aspect: CropAspectRatio) {
        cropAspect = aspect
        guard isCropping else { return }
        if let ratio = aspect.normalizedRatio(imageSize: imageSize) {
            cropRect = CropRectEditor.applyAspect(to: cropRect, aspect: ratio)
        }
    }

    func updateCrop(handle: CropHandle, toNormalized point: CGPoint) {
        guard isCropping else { return }
        let aspect = handle.isCorner ? cropAspect.normalizedRatio(imageSize: imageSize) : nil
        cropRect = CropRectEditor.resize(
            cropRect,
            handle: handle,
            to: point,
            aspect: aspect,
            minWidth: minimumCropWidth,
            minHeight: minimumCropHeight,
            fromCenter: isCropCenterResizeModifierPressed
        )
    }

    private var isCropCenterResizeModifierPressed: Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.option) || (flags.contains(.command) && flags.contains(.shift))
    }

    func moveCrop(byNormalized delta: CGSize) {
        guard isCropping else { return }
        cropRect = CropRectEditor.move(cropRect, by: delta)
    }

    /// Bake the crop into a new full-resolution base image, move the shapes with it, and exit crop
    /// mode. Page space is image pixels, so a crop is a translation plus a scale on every shape.
    func applyCrop() {
        guard isCropping else { return }

        let crop = cropRect.standardized.intersection(CropRectEditor.unit)
        defer {
            isCropping = false
            cropRect = CropRectEditor.unit
            cropAspect = .freeform
        }

        guard crop.width > 0.0001, crop.height > 0.0001 else { return }
        if crop.minX < 0.0005, crop.minY < 0.0005, crop.width > 0.999, crop.height > 0.999 { return }

        guard let baseURL = baseImageURL,
              let result = AnnotationImageCropper.crop(url: baseURL, normalizedRect: crop) else {
            errorMessage = "Unable to crop the image."
            return
        }

        guard let snapshot = currentCropSnapshot() else {
            try? FileManager.default.removeItem(at: result.url)
            errorMessage = "Unable to preserve the image for crop undo."
            return
        }

        let oldImageSize = imageSize
        let usedCrop = result.normalizedRect
        let newImageSize = result.pixelSize

        let offsetX = Double(usedCrop.minX * oldImageSize.width)
        let offsetY = Double(usedCrop.minY * oldImageSize.height)
        let scaleX = usedCrop.width > 0 ? Double(newImageSize.width) / Double(usedCrop.width * oldImageSize.width) : 1
        let scaleY = usedCrop.height > 0 ? Double(newImageSize.height) / Double(usedCrop.height * oldImageSize.height) : 1
        let uniform = (scaleX + scaleY) / 2

        let moved = engine.shapes.map { shape -> AnnoShape in
            var shape = shape
            shape.x = (shape.x - offsetX) * scaleX
            shape.y = (shape.y - offsetY) * scaleY
            scaleShapeContents(&shape, sx: scaleX, sy: scaleY, uniform: uniform)
            return shape
        }

        baseImageURL = result.url
        ownedCropURLs.insert(result.url)
        imageSize = newImageSize
        previewImage = makePreviewImage(from: result.url)
        previewCGImage = previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        engine.viewport = AnnoViewport(imageFrame: engine.viewport.imageFrame, imageSize: imageSize)
        engine.replaceDocument(shapes: moved, bindings: engine.document.bindings)

        cropUndoStack.append(snapshot)
        cropRedoStack.removeAll()

        resetZoom()
        errorMessage = nil
    }

    /// Scale a shape's own dimensions, so a crop that changes the image's resolution keeps
    /// annotations the same size relative to the picture.
    private func scaleShapeContents(_ shape: inout AnnoShape, sx: Double, sy: Double, uniform: Double) {
        switch shape.kind {
        case var .geo(p):
            p.w *= sx; p.h *= sy
            p.strokeWidth *= uniform
            p.cornerRadius *= uniform
            shape.kind = .geo(p)
        case var .redaction(p):
            p.w *= sx; p.h *= sy
            shape.kind = .redaction(p)
        case var .highlight(p):
            p.w *= sx; p.h *= sy
            shape.kind = .highlight(p)
        case var .numbered(p):
            p.diameter *= uniform
            shape.kind = .numbered(p)
        case var .draw(p):
            p.points = p.points.map { Vec($0.x * sx, $0.y * sy, $0.z) }
            p.strokeWidth *= uniform
            shape.kind = .draw(p)
        case var .arrow(p):
            p.start = Vec(p.start.x * sx, p.start.y * sy)
            p.end = Vec(p.end.x * sx, p.end.y * sy)
            p.bend *= uniform
            p.strokeWidth *= uniform
            shape.kind = .arrow(p)
        case var .text(p):
            p.fontSize *= uniform
            p.w *= sx
            shape.kind = .text(p)
        }
    }

    private func undoCrop() {
        guard let previous = cropUndoStack.last else { return }
        guard let current = currentCropSnapshot() else {
            errorMessage = "Unable to preserve the image for crop redo."
            return
        }
        cropUndoStack.removeLast()
        cropRedoStack.append(current)
        restore(previous)
    }

    private func redoCrop() {
        guard let next = cropRedoStack.last else { return }
        guard let current = currentCropSnapshot() else {
            errorMessage = "Unable to preserve the image for crop undo."
            return
        }
        cropRedoStack.removeLast()
        cropUndoStack.append(current)
        restore(next)
    }

    private func currentCropSnapshot() -> CropSnapshot? {
        let stableBaseURL: URL?
        if let baseImageURL {
            guard let snapshotURL = stableCropSnapshotURL(for: baseImageURL) else { return nil }
            stableBaseURL = snapshotURL
        } else {
            stableBaseURL = nil
        }

        return CropSnapshot(
            baseImageURL: stableBaseURL,
            imageSize: imageSize,
            shapes: engine.shapes,
            bindings: engine.document.bindings
        )
    }

    /// Crop history must never point at a History display URL, because annotation commits can
    /// replace that file while this editor stays open.
    private func stableCropSnapshotURL(for url: URL) -> URL? {
        if ownedCropURLs.contains(url) { return url }

        let fileExtension = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BetterShot_CropSnapshot_\(UUID().uuidString.prefix(8))")
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)
            ownedCropURLs.insert(destinationURL)
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            return nil
        }
    }

    private func restore(_ snapshot: CropSnapshot) {
        baseImageURL = snapshot.baseImageURL
        imageSize = snapshot.imageSize
        previewImage = snapshot.baseImageURL.flatMap(makePreviewImage(from:))
        previewCGImage = previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        engine.viewport = AnnoViewport(imageFrame: engine.viewport.imageFrame, imageSize: imageSize)
        engine.replaceDocument(shapes: snapshot.shapes, bindings: snapshot.bindings)
        resetZoom()
    }

    private func removeOwnedCropFiles() {
        for url in ownedCropURLs {
            try? FileManager.default.removeItem(at: url)
        }
        ownedCropURLs.removeAll()
    }

    private var minimumCropWidth: CGFloat {
        guard imageSize.width > 0 else { return 0.05 }
        return min(0.5, max(0.01, minimumCropPixels / imageSize.width))
    }

    private var minimumCropHeight: CGFloat {
        guard imageSize.height > 0 else { return 0.05 }
        return min(0.5, max(0.01, minimumCropPixels / imageSize.height))
    }
}
