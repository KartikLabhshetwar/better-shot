import AppKit
import SwiftUI

@MainActor
@Observable
final class EditorModel {
    var sourceImage: CGImage?
    var sourceURL: URL?
    var previewImage: NSImage?
    var imageSize: CGSize = .zero
    var config = BeautifierConfig.default
    var toastMessage: String?

    // Annotation state
    var items: [AnnotationItem] = []
    var draftItem: AnnotationItem?
    var selectedItemIDs: Set<AnnotationItem.ID> = []
    var selectedItemID: AnnotationItem.ID? {
        get {
            selectedItemIDs.count == 1 ? selectedItemIDs.first : nil
        }
        set {
            if let newValue {
                selectedItemIDs = [newValue]
            } else {
                selectedItemIDs = []
            }
        }
    }
    var editingTextItemID: AnnotationItem.ID?
    var isTextPlacementArmed = false
    var selectionRect: CGRect?
    var selectedTool: AnnotationTool = .select
    var selectedSwatch: AnnotationSwatch = .red
    var strokeWidth: CGFloat = 4
    var redactionDensity: CGFloat = 0.55

    var textFontName: String = AnnotationTextMetrics.defaultFontName
    var textFontSize: CGFloat = 48
    var textIsBold: Bool = true
    var textIsItalic: Bool = false
    var textIsUnderline: Bool = false
    var textAlignment: NSTextAlignment = .left

    private var interaction: AnnotationInteraction?
    var history = AnnotationHistory()
    private var nextNumberedCircleValue = 1
    private let minimumItemSize: CGFloat = 0.006
    private(set) var statePath = AnnotationToolState.idle.path(for: .rectangle)

    // Config undo/redo
    private var configPast: [BeautifierConfig] = []
    private var configFuture: [BeautifierConfig] = []

    var canUndo: Bool { history.canUndo || !configPast.isEmpty }
    var canRedo: Bool { history.canRedo || !configFuture.isEmpty }

    var itemIDs: [AnnotationItem.ID] { items.map(\.id) }
    var selectionCount: Int { selectedItemIDs.count }

    var isTransformingExistingAnnotation: Bool {
        switch interaction {
        case .moving, .movingSelection, .resizing:
            true
        case .drawing, .selecting, .none:
            false
        }
    }

    var inspectedTool: AnnotationTool? {
        selectedItem?.tool ?? selectedItems.first?.tool ?? (selectedTool.createsAnnotation ? selectedTool : nil)
    }

    var isStrokeStyleAvailable: Bool {
        if selectedItems.isEmpty {
            return inspectedTool != .numberedCircle
        }
        return selectedItems.contains { $0.tool != .numberedCircle }
    }

    var isRedactionStyleAvailable: Bool {
        if selectedItems.isEmpty {
            return inspectedTool?.isRedactionTool == true || inspectedTool == .spotlight
        }
        return selectedItems.contains { $0.tool.isRedactionTool || $0.tool == .spotlight }
    }

    var isTextStyleAvailable: Bool {
        selectedTool == .text || selectedTextItem != nil
    }

    // MARK: - Load

    func loadImage(from url: URL) {
        let rawURL = CaptureOrchestrator.resolveRawSource(for: url)
        sourceURL = rawURL
        guard let source = CGImageSourceCreateWithURL(rawURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        sourceImage = image
        imageSize = CGSize(width: image.width, height: image.height)
        previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        config = AppPreferences.defaultBeautifierConfig

        items = []
        draftItem = nil
        selectedItemIDs = []
        editingTextItemID = nil
        isTextPlacementArmed = selectedTool == .text
        selectionRect = nil
        interaction = nil
        nextNumberedCircleValue = 1
        history.reset()
        RedactionImageProcessor.removeAllCachedPreviewImages()
        statePath = AnnotationToolState.idle.path(for: selectedTool)
    }

    // MARK: - Config Updates

    func updateConfig(_ update: (inout BeautifierConfig) -> Void) {
        configPast.append(config)
        if configPast.count > 50 { configPast.removeFirst() }
        configFuture.removeAll()
        update(&config)
    }

    // MARK: - Undo / Redo

    func undo() {
        if let restoredItems = history.undo(current: items) {
            items = restoredItems
            selectedItemIDs = []
            editingTextItemID = nil
            draftItem = nil
            interaction = nil
            selectionRect = nil
            syncNextNumberedCircleValue()
            statePath = AnnotationToolState.idle.path(for: selectedTool)
        } else if let prev = configPast.popLast() {
            configFuture.insert(config, at: 0)
            config = prev
        }
    }

    func redo() {
        if let restoredItems = history.redo(current: items) {
            items = restoredItems
            selectedItemIDs = []
            editingTextItemID = nil
            draftItem = nil
            interaction = nil
            selectionRect = nil
            syncNextNumberedCircleValue()
            statePath = AnnotationToolState.idle.path(for: selectedTool)
        } else if !configFuture.isEmpty {
            let next = configFuture.removeFirst()
            configPast.append(config)
            config = next
        }
    }

    // MARK: - Interaction Pipeline

    func beginInteraction(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        let isExtendingSelection = isMultiSelectionModifierPressed

        guard let point = normalizedPoint(location, in: imageFrame, boundedBy: boundaryFrame, clamped: false) else {
            if !isExtendingSelection { clearSelection() }
            return
        }

        if selectedTool == .select {
            if beginSelectionInteraction(at: point, in: imageFrame, preservingSelectedTool: true, extendingSelection: isExtendingSelection) { return }
            beginMarqueeSelection(at: point, extendingSelection: isExtendingSelection)
            return
        }

        if beginSelectionInteraction(at: point, in: imageFrame, preservingSelectedTool: false, extendingSelection: isExtendingSelection) { return }

        selectedItemIDs = []
        editingTextItemID = nil
        selectionRect = nil
        guard selectedTool != .text || isTextPlacementArmed else {
            interaction = nil
            statePath = AnnotationToolState.idle.path(for: selectedTool)
            return
        }

        beginDraftItem(at: point, within: annotationBounds(for: imageFrame, boundaryFrame: boundaryFrame))
    }

    func updateInteraction(to location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard let interaction,
              let point = normalizedPoint(location, in: imageFrame, boundedBy: boundaryFrame, clamped: true) else { return }
        let allowedBounds = annotationBounds(for: imageFrame, boundaryFrame: boundaryFrame)

        switch interaction {
        case .drawing(let startPoint):
            updateDraftItem(from: startPoint, to: point, within: allowedBounds, lockAspectRatio: isAspectRatioLocked)
        case .moving(let id, let startPoint, let originalItem):
            let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            updateItem(id: id, item: originalItem.offsetBy(clampedDelta(delta, for: originalItem.bounds, within: allowedBounds)))
        case .movingSelection(let ids, let startPoint, let originalItems):
            let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            let cd = clampedDelta(delta, for: groupBounds(for: originalItems), within: allowedBounds)
            for item in originalItems where ids.contains(item.id) {
                updateItem(id: item.id, item: item.offsetBy(cd))
            }
        case .resizing(let id, let handle, let originalItem):
            updateItem(id: id, item: resizedItem(originalItem, handle: handle, to: point, lockAspectRatio: isAspectRatioLocked))
        case .selecting(let startPoint, let originalSelection, let extendsSelection):
            updateMarqueeSelection(from: startPoint, to: point, originalSelection: originalSelection, extendsSelection: extendsSelection)
        }
    }

    func endInteraction(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        defer { interaction = nil }

        guard let interaction,
              let point = normalizedPoint(location, in: imageFrame, boundedBy: boundaryFrame, clamped: true) else {
            draftItem = nil
            return
        }
        let allowedBounds = annotationBounds(for: imageFrame, boundaryFrame: boundaryFrame)

        switch interaction {
        case .drawing(let startPoint):
            updateDraftItem(from: startPoint, to: point, within: allowedBounds, lockAspectRatio: isAspectRatioLocked)

            guard let item = draftItem,
                  item.isRenderable(minimumSize: minimumItemSize, allowEmptyText: item.tool == .text) else {
                draftItem = nil
                statePath = AnnotationToolState.idle.path(for: selectedTool)
                return
            }

            history.push(items)
            items.append(item)
            selectedItemID = item.id
            editingTextItemID = item.tool == .text ? item.id : nil
            if item.tool == .text {
                isTextPlacementArmed = false
            } else if item.tool == .numberedCircle {
                nextNumberedCircleValue += 1
            }
            draftItem = nil

        case .moving, .movingSelection, .resizing:
            break

        case .selecting(let startPoint, let originalSelection, let extendsSelection):
            updateMarqueeSelection(from: startPoint, to: point, originalSelection: originalSelection, extendsSelection: extendsSelection)
            selectionRect = nil
        }

        statePath = AnnotationToolState.idle.path(for: selectedTool)
    }

    // MARK: - Tool Actions

    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        editingTextItemID = nil
        isTextPlacementArmed = tool == .text
        statePath = AnnotationToolState.idle.path(for: tool)
    }

    func setSwatch(_ swatch: AnnotationSwatch) {
        selectedSwatch = swatch
        if !selectedItemIDs.isEmpty {
            history.push(items)
            updateSelectedItems { item in item.swatch = swatch }
        }
        if var d = draftItem { d.swatch = swatch; draftItem = d }
    }

    func setStrokeWidth(_ strokeWidth: CGFloat) {
        self.strokeWidth = strokeWidth
        if !selectedItemIDs.isEmpty {
            history.push(items)
            updateSelectedItems { item in item.strokeWidth = strokeWidth }
        }
        if var d = draftItem { d.strokeWidth = strokeWidth; draftItem = d }
    }

    func setRedactionDensity(_ density: CGFloat) {
        redactionDensity = density
        if !selectedItemIDs.isEmpty {
            history.push(items)
            updateSelectedItems { item in item.redactionDensity = density }
        }
        if var d = draftItem { d.redactionDensity = density; draftItem = d }
    }

    func deleteSelectedAnnotation() {
        guard !selectedItemIDs.isEmpty else { return }
        history.push(items)
        items.removeAll { selectedItemIDs.contains($0.id) }
        selectedItemIDs = []
        editingTextItemID = nil
        isTextPlacementArmed = false
        interaction = nil
        draftItem = nil
        selectionRect = nil
        syncNextNumberedCircleValue()
        statePath = AnnotationToolState.idle.path(for: selectedTool)
    }

    func selectAllAnnotations() {
        guard !items.isEmpty else { return }
        selectedItemIDs = Set(items.map(\.id))
        editingTextItemID = nil
        isTextPlacementArmed = false
        interaction = nil
        draftItem = nil
        selectionRect = nil
        selectedTool = .select
        statePath = AnnotationToolState.idle.path(for: selectedTool)
    }

    func clearAnnotations() {
        guard !items.isEmpty else { return }
        history.push(items)
        items.removeAll()
        selectedItemIDs = []
        editingTextItemID = nil
        draftItem = nil
        nextNumberedCircleValue = 1
    }

    func setText(_ text: String, for id: AnnotationItem.ID) {
        updateItem(id: id) { item in item.text = text }
    }

    func setTextViewContentSize(_ size: CGSize, for id: AnnotationItem.ID, imageFrame: CGRect, allowedBounds: CGRect) {
        guard interaction == nil else { return }
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }
        let normalizedWidth = size.width / imageFrame.width
        let normalizedHeight = size.height / imageFrame.height
        let minW = AnnotationTextMetrics.minimumNormalizedWidth(lineHeight: items.first(where: { $0.id == id })?.textLineHeight ?? AnnotationTextMetrics.defaultNormalizedLineHeight, imageSize: imageSize)
        updateItem(id: id) { item in
            let newWidth = min(max(normalizedWidth, minW), allowedBounds.width)
            let newHeight = min(max(normalizedHeight, item.textLineHeight), allowedBounds.height)
            let maxX = max(allowedBounds.minX, allowedBounds.maxX - newWidth)
            let maxY = max(allowedBounds.minY, allowedBounds.maxY - newHeight)
            item.rect = CGRect(
                x: min(max(item.rect.origin.x, allowedBounds.minX), maxX),
                y: min(max(item.rect.origin.y, allowedBounds.minY), maxY),
                width: newWidth,
                height: newHeight
            )
        }
    }

    func commitTextEditing() {
        guard let editingTextItemID else { return }
        if let item = items.first(where: { $0.id == editingTextItemID }),
           item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.removeAll { $0.id == editingTextItemID }
            selectedItemIDs.remove(editingTextItemID)
        }
        self.editingTextItemID = nil
        if selectedTool == .text {
            isTextPlacementArmed = true
        }
    }

    func hoveredAnnotation(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) -> AnnotationItem? {
        guard let point = normalizedPoint(location, in: imageFrame, boundedBy: boundaryFrame, clamped: false) else { return nil }
        return hitTest(point)
    }

    func containsInteractionPoint(_ location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) -> Bool {
        normalizedPoint(location, in: imageFrame, boundedBy: boundaryFrame, clamped: false) != nil
    }

    // MARK: - Text Style

    var selectedTextFontSize: CGFloat {
        get {
            guard let item = selectedTextItem else { return textFontSize }
            return AnnotationTextMetrics.renderedFontSize(lineHeight: item.textLineHeight, imagePixelHeight: imageSize.height).rounded()
        }
        set { setTextFontSize(newValue) }
    }

    var selectedTextFontName: String {
        get { selectedTextItem?.fontName ?? textFontName }
        set { setTextFontName(newValue) }
    }

    var selectedTextIsBold: Bool {
        get { selectedTextItem?.isBold ?? textIsBold }
        set { setTextBold(newValue) }
    }

    var selectedTextIsItalic: Bool {
        get { selectedTextItem?.isItalic ?? textIsItalic }
        set { setTextItalic(newValue) }
    }

    var selectedTextIsUnderline: Bool {
        get { selectedTextItem?.isUnderline ?? textIsUnderline }
        set { setTextUnderline(newValue) }
    }

    var selectedTextAlignment: NSTextAlignment {
        get { selectedTextItem?.textAlignment ?? textAlignment }
        set { setTextAlignment(newValue) }
    }

    private var selectedTextItem: AnnotationItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID && $0.tool == .text }
    }

    private func setTextFontSize(_ pointSize: CGFloat) {
        let clamped = max(pointSize, AnnotationTextMetrics.minimumFontSize)
        textFontSize = clamped
        guard let selectedItemID, selectedTextItem != nil else { return }
        guard imageSize.height > 0 else { return }
        let newLineHeight = clamped / (imageSize.height * AnnotationTextMetrics.fontScale)
        history.push(items)
        updateItem(id: selectedItemID) { item in item.textLineHeight = newLineHeight }
    }

    private func setTextFontName(_ name: String) {
        textFontName = name
        guard let selectedItemID, selectedTextItem != nil else { return }
        history.push(items)
        updateItem(id: selectedItemID) { item in item.fontName = name }
    }

    private func setTextBold(_ bold: Bool) {
        textIsBold = bold
        guard let selectedItemID, selectedTextItem != nil else { return }
        history.push(items)
        updateItem(id: selectedItemID) { item in item.isBold = bold }
    }

    private func setTextItalic(_ italic: Bool) {
        textIsItalic = italic
        guard let selectedItemID, selectedTextItem != nil else { return }
        history.push(items)
        updateItem(id: selectedItemID) { item in item.isItalic = italic }
    }

    private func setTextUnderline(_ underline: Bool) {
        textIsUnderline = underline
        guard let selectedItemID, selectedTextItem != nil else { return }
        history.push(items)
        updateItem(id: selectedItemID) { item in item.isUnderline = underline }
    }

    private func setTextAlignment(_ alignment: NSTextAlignment) {
        textAlignment = alignment
        guard let selectedItemID, selectedTextItem != nil else { return }
        history.push(items)
        updateItem(id: selectedItemID) { item in item.textAlignment = alignment }
    }

    // MARK: - Paste Image Overlay

    func pasteImageOverlay() {
        let pb = NSPasteboard.general
        guard let nsImage = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else { return }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        guard let pastedCGImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let source = sourceImage else { return }

        let srcW = CGFloat(source.width)
        let srcH = CGFloat(source.height)
        let pasteW = CGFloat(pastedCGImage.width)
        let pasteH = CGFloat(pastedCGImage.height)

        let scale = min(1.0, min(srcW * 0.8 / pasteW, srcH * 0.8 / pasteH))
        let drawW = pasteW * scale
        let drawH = pasteH * scale
        let drawX = (srcW - drawW) / 2
        let drawY = (srcH - drawH) / 2

        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: Int(srcW), height: Int(srcH),
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        ctx.draw(source, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
        ctx.draw(pastedCGImage, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        guard let composited = ctx.makeImage() else { return }
        sourceImage = composited
        previewImage = NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height))
    }

    // MARK: - Render

    func renderFinal() -> CGImage? {
        guard let image = sourceImage else { return nil }
        return BeautifierRenderer.render(image: image, config: config, annotations: items)
    }

    func saveConfigAsDefault() {
        AppPreferences.defaultBeautifierConfig = config
        toastMessage = "Saved as default"
    }

    // MARK: - Private Interaction Helpers

    private func beginSelectionInteraction(at point: CGPoint, in imageFrame: CGRect, preservingSelectedTool: Bool, extendingSelection: Bool) -> Bool {
        if !extendingSelection,
           let sel = selectedItem,
           sel.tool != .text,
           let resizeHandle = hitTestResizeHandle(point, in: imageFrame, item: sel) {
            applyStyleFromItem(sel, updateSelectedTool: !preservingSelectedTool)
            draftItem = nil
            history.push(items)
            interaction = .resizing(id: sel.id, handle: resizeHandle, originalItem: sel)
            statePath = AnnotationToolState.resizing.path(for: selectedTool)
            return true
        }

        guard let item = hitTest(point) else { return false }

        if extendingSelection {
            toggleSelection(of: item, preservingSelectedTool: preservingSelectedTool)
            draftItem = nil
            interaction = nil
            statePath = AnnotationToolState.idle.path(for: selectedTool)
            return true
        }

        let shouldPreserveMultipleSelection = selectedItemIDs.count > 1 && selectedItemIDs.contains(item.id)
        let shouldBeginTextEditing = item.tool == .text && selectedItemID == item.id && editingTextItemID != item.id

        if !shouldPreserveMultipleSelection { selectedItemID = item.id }

        applyStyleFromItem(item, updateSelectedTool: !preservingSelectedTool)
        draftItem = nil
        history.push(items)

        if shouldBeginTextEditing {
            editingTextItemID = item.id
            interaction = nil
            statePath = AnnotationToolState.idle.path(for: selectedTool)
            return true
        }

        editingTextItemID = nil

        if shouldPreserveMultipleSelection {
            interaction = .movingSelection(ids: selectedItemIDs, startPoint: point, originalItems: selectedItems)
            statePath = AnnotationToolState.translating.path(for: selectedTool)
        } else if item.tool != .text, let resizeHandle = hitTestResizeHandle(point, in: imageFrame, item: item) {
            interaction = .resizing(id: item.id, handle: resizeHandle, originalItem: item)
            statePath = AnnotationToolState.resizing.path(for: selectedTool)
        } else if isOptionPressed {
            let duplicate = AnnotationItem(
                tool: item.tool, rect: item.rect, points: item.points,
                swatch: item.swatch, strokeWidth: item.strokeWidth,
                redactionDensity: item.redactionDensity, text: item.text,
                textLineHeight: item.textLineHeight, fontName: item.fontName,
                isBold: item.isBold, isItalic: item.isItalic,
                isUnderline: item.isUnderline, textAlignment: item.textAlignment
            )
            items.append(duplicate)
            selectedItemID = duplicate.id
            interaction = .moving(id: duplicate.id, startPoint: point, originalItem: duplicate)
            statePath = AnnotationToolState.translating.path(for: selectedTool)
        } else {
            interaction = .moving(id: item.id, startPoint: point, originalItem: item)
            statePath = AnnotationToolState.translating.path(for: selectedTool)
        }

        return true
    }

    private func beginMarqueeSelection(at point: CGPoint, extendingSelection: Bool) {
        editingTextItemID = nil
        isTextPlacementArmed = false
        draftItem = nil
        selectionRect = CGRect(origin: point, size: .zero)
        interaction = .selecting(startPoint: point, originalSelection: extendingSelection ? selectedItemIDs : [], extendsSelection: extendingSelection)
        statePath = AnnotationToolState.drawing.path(for: selectedTool)
    }

    private func clearSelection() {
        selectedItemIDs = []
        editingTextItemID = nil
        isTextPlacementArmed = false
        interaction = nil
        draftItem = nil
        selectionRect = nil
        statePath = AnnotationToolState.idle.path(for: selectedTool)
    }

    private func beginDraftItem(at point: CGPoint, within allowedBounds: CGRect) {
        let textLineHeight: CGFloat = imageSize.height > 0
            ? textFontSize / (imageSize.height * AnnotationTextMetrics.fontScale)
            : AnnotationTextMetrics.defaultNormalizedLineHeight
        let itemRect: CGRect
        switch selectedTool {
        case .select: return
        case .text: itemRect = defaultTextRect(at: point, lineHeight: textLineHeight, within: allowedBounds)
        case .numberedCircle: itemRect = AnnotationNumberedCircleMetrics.defaultRect(centeredAt: point, imageSize: imageSize, within: allowedBounds)
        case .rectangle, .filledRectangle, .ellipse, .line, .arrow, .freehand, .pixelate, .blur, .spotlight:
            itemRect = CGRect(origin: point, size: .zero)
        }
        let itemText = selectedTool == .numberedCircle ? "\(nextNumberedCircleValue)" : ""

        draftItem = AnnotationItem(
            tool: selectedTool, rect: itemRect, points: initialPoints(for: selectedTool, at: point),
            swatch: selectedSwatch, strokeWidth: strokeWidth, redactionDensity: redactionDensity,
            text: itemText, textLineHeight: textLineHeight, fontName: textFontName,
            isBold: textIsBold, isItalic: textIsItalic, isUnderline: textIsUnderline, textAlignment: textAlignment
        )
        interaction = .drawing(startPoint: point)
        statePath = AnnotationToolState.drawing.path(for: selectedTool)
    }

    private func updateDraftItem(from startPoint: CGPoint, to point: CGPoint, within allowedBounds: CGRect, lockAspectRatio: Bool) {
        guard var draftItem else { return }
        switch selectedTool {
        case .select: break
        case .line:
            draftItem.points = [startPoint, point]
            draftItem.rect = boundingRect(for: draftItem.points)
        case .arrow:
            draftItem.points = [startPoint, midpoint(startPoint, point), point]
            draftItem.rect = boundingRect(for: draftItem.points)
        case .freehand:
            draftItem.points = freehandPoints(adding: point, to: draftItem.points)
            draftItem.rect = boundingRect(for: draftItem.points)
        case .numberedCircle:
            draftItem.rect = AnnotationNumberedCircleMetrics.defaultRect(centeredAt: startPoint, imageSize: imageSize, within: allowedBounds)
        case .rectangle, .filledRectangle, .ellipse, .pixelate, .blur, .spotlight:
            let aspectRatio = selectedTool.supportsAspectLock && lockAspectRatio ? squareAspectRatio : nil
            draftItem.rect = rect(from: startPoint, to: point, aspectRatio: aspectRatio)
        case .text:
            draftItem.rect = defaultTextRect(at: startPoint, lineHeight: draftItem.textLineHeight, within: allowedBounds)
        }
        self.draftItem = draftItem
    }

    private func updateMarqueeSelection(from startPoint: CGPoint, to point: CGPoint, originalSelection: Set<AnnotationItem.ID>, extendsSelection: Bool) {
        let rect = rect(from: startPoint, to: point).standardized
        selectionRect = rect
        let selectedByMarquee = Set(items.compactMap { item in item.bounds.intersects(rect) ? item.id : nil })
        selectedItemIDs = extendsSelection ? originalSelection.union(selectedByMarquee) : selectedByMarquee
        if let selectedItem { applyStyleFromItem(selectedItem, updateSelectedTool: false) }
    }

    private func hitTest(_ point: CGPoint) -> AnnotationItem? {
        items.reversed().first { item in item.hitTest(point, tolerance: 0.01) }
    }

    private var selectedItem: AnnotationItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    private var selectedItems: [AnnotationItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    private func toggleSelection(of item: AnnotationItem, preservingSelectedTool: Bool) {
        editingTextItemID = nil
        isTextPlacementArmed = false
        selectionRect = nil
        if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) } else { selectedItemIDs.insert(item.id) }
        if let selectedItem { applyStyleFromItem(selectedItem, updateSelectedTool: !preservingSelectedTool) }
        else if !selectedItemIDs.isEmpty { selectedSwatch = item.swatch; strokeWidth = item.strokeWidth; redactionDensity = item.redactionDensity }
    }

    private func hitTestResizeHandle(_ point: CGPoint, in imageFrame: CGRect, item: AnnotationItem) -> AnnotationResizeHandle? {
        let xTolerance = 14 / max(imageFrame.width, 1)
        let yTolerance = 14 / max(imageFrame.height, 1)
        if item.tool.usesEndpoints {
            let curveXTolerance = 18 / max(imageFrame.width, 1)
            let curveYTolerance = 18 / max(imageFrame.height, 1)
            return AnnotationResizeHandle.handles(for: item.tool).first { handle in
                guard let endpoint = handle.point(in: item) else { return false }
                let xt = handle == .control ? curveXTolerance : xTolerance
                let yt = handle == .control ? curveYTolerance : yTolerance
                return abs(point.x - endpoint.x) <= xt && abs(point.y - endpoint.y) <= yt
            }
        }
        return AnnotationResizeHandle.boxCases.first { handle in
            guard let corner = handle.corner(in: item.bounds) else { return false }
            return abs(point.x - corner.x) <= xTolerance && abs(point.y - corner.y) <= yTolerance
        }
    }

    private func applyStyleFromItem(_ item: AnnotationItem, updateSelectedTool: Bool = true) {
        if updateSelectedTool { selectedTool = item.tool }
        selectedSwatch = item.swatch
        strokeWidth = item.strokeWidth
        redactionDensity = item.redactionDensity
        if item.tool == .text {
            textFontName = item.fontName
            textFontSize = AnnotationTextMetrics.renderedFontSize(lineHeight: item.textLineHeight, imagePixelHeight: imageSize.height).rounded()
            textIsBold = item.isBold
            textIsItalic = item.isItalic
            textIsUnderline = item.isUnderline
            textAlignment = item.textAlignment
        }
    }

    func annotationBounds(for imageFrame: CGRect, boundaryFrame: CGRect) -> CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(
            x: (boundaryFrame.minX - imageFrame.minX) / imageFrame.width,
            y: (boundaryFrame.minY - imageFrame.minY) / imageFrame.height,
            width: boundaryFrame.width / imageFrame.width,
            height: boundaryFrame.height / imageFrame.height
        )
    }

    private func normalizedPoint(_ location: CGPoint, in imageFrame: CGRect, boundedBy boundaryFrame: CGRect, clamped: Bool) -> CGPoint? {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return nil }
        guard boundaryFrame.width > 0, boundaryFrame.height > 0 else { return nil }
        let point: CGPoint
        if clamped {
            point = CGPoint(
                x: min(max(location.x, boundaryFrame.minX), boundaryFrame.maxX),
                y: min(max(location.y, boundaryFrame.minY), boundaryFrame.maxY)
            )
        } else {
            guard boundaryFrame.contains(location) else { return nil }
            point = location
        }
        return CGPoint(
            x: (point.x - imageFrame.minX) / imageFrame.width,
            y: (point.y - imageFrame.minY) / imageFrame.height
        )
    }

    private var isAspectRatioLocked: Bool { NSEvent.modifierFlags.contains(.shift) }
    private var isOptionPressed: Bool { NSEvent.modifierFlags.contains(.option) }
    private var isMultiSelectionModifierPressed: Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.shift) || flags.contains(.command)
    }

    private var squareAspectRatio: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return imageSize.height / imageSize.width
    }

    private func rect(from startPoint: CGPoint, to endPoint: CGPoint, aspectRatio: CGFloat? = nil) -> CGRect {
        let adjustedEndPoint: CGPoint
        if let aspectRatio, aspectRatio > 0 {
            adjustedEndPoint = aspectLockedPoint(from: startPoint, to: endPoint, aspectRatio: aspectRatio)
        } else {
            adjustedEndPoint = endPoint
        }
        return CGRect(
            x: min(startPoint.x, adjustedEndPoint.x), y: min(startPoint.y, adjustedEndPoint.y),
            width: abs(adjustedEndPoint.x - startPoint.x), height: abs(adjustedEndPoint.y - startPoint.y)
        ).standardized
    }

    private func aspectLockedPoint(from anchor: CGPoint, to point: CGPoint, aspectRatio: CGFloat) -> CGPoint {
        let deltaX = point.x - anchor.x
        let deltaY = point.y - anchor.y
        let proposedWidth = abs(deltaX)
        let proposedHeight = abs(deltaY)
        guard proposedWidth > 0, proposedHeight > 0 else { return point }
        let width: CGFloat, height: CGFloat
        if proposedWidth / aspectRatio <= proposedHeight { let w = proposedWidth; let h = proposedWidth / aspectRatio; width = w; height = h }
        else { let h = proposedHeight; let w = proposedHeight * aspectRatio; width = w; height = h }
        return CGPoint(x: anchor.x + width * (deltaX < 0 ? -1 : 1), y: anchor.y + height * (deltaY < 0 ? -1 : 1))
    }

    private func resizedItem(_ originalItem: AnnotationItem, handle: AnnotationResizeHandle, to point: CGPoint, lockAspectRatio: Bool) -> AnnotationItem {
        if originalItem.tool.usesEndpoints {
            if originalItem.tool == .arrow, handle == .control {
                return arrowItem(originalItem, draggingCurveHandleTo: point)
            }
            return originalItem.withEndpoint(handle, movedTo: point)
        }
        let originalRect = originalItem.bounds
        let anchor = handle.oppositeCorner(in: originalRect)
        let constrainedPoint = handle.constrainedPoint(point, from: anchor, minimumSize: minimumItemSize)
        let aspectRatio: CGFloat? = originalItem.tool.supportsAspectLock && lockAspectRatio && originalRect.height > 0
            ? originalRect.width / originalRect.height : nil
        return originalItem.resized(to: rect(from: anchor, to: constrainedPoint, aspectRatio: aspectRatio))
    }

    private func arrowItem(_ item: AnnotationItem, draggingCurveHandleTo apex: CGPoint) -> AnnotationItem {
        guard let start = item.points.first, let end = item.points.last else { return item }
        let snappedApex = snappedArrowApex(apex, start: start, end: end)
        let control = AnnotationItem.arrowControlPoint(forApex: snappedApex, start: start, end: end)
        return item.withEndpoint(.control, movedTo: control)
    }

    private func snappedArrowApex(_ apex: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
        let sx = max(imageSize.width, 1), sy = max(imageSize.height, 1)
        let ax = apex.x * sx, ay = apex.y * sy
        let startX = start.x * sx, startY = start.y * sy
        let dx = end.x * sx - startX, dy = end.y * sy - startY
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return apex }
        let projection = ((ax - startX) * dx + (ay - startY) * dy) / lengthSquared
        let projX = startX + projection * dx, projY = startY + projection * dy
        let perpendicular = hypot(ax - projX, ay - projY)
        let snapThreshold = max(sqrt(lengthSquared) * 0.06, 6)
        guard perpendicular <= snapThreshold else { return apex }
        return CGPoint(x: projX / sx, y: projY / sy)
    }

    private func initialPoints(for tool: AnnotationTool, at point: CGPoint) -> [CGPoint] {
        switch tool {
        case .select: []
        case .line: [point, point]
        case .arrow: [point, point, point]
        case .freehand: [point]
        case .rectangle, .filledRectangle, .ellipse, .numberedCircle, .pixelate, .blur, .spotlight, .text: []
        }
    }

    private func defaultTextRect(at point: CGPoint, lineHeight: CGFloat = AnnotationTextMetrics.defaultNormalizedLineHeight, within allowedBounds: CGRect) -> CGRect {
        let height = lineHeight
        let width = AnnotationTextMetrics.minimumNormalizedWidth(lineHeight: height, imageSize: imageSize)
        let maxX = max(allowedBounds.minX, allowedBounds.maxX - width)
        let maxY = max(allowedBounds.minY, allowedBounds.maxY - height)
        return CGRect(
            x: min(max(point.x, allowedBounds.minX), maxX),
            y: min(max(point.y, allowedBounds.minY), maxY),
            width: width, height: height
        )
    }

    private func clampedDelta(_ delta: CGPoint, for bounds: CGRect, within allowedBounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(delta.x, allowedBounds.minX - bounds.minX), allowedBounds.maxX - bounds.maxX),
            y: min(max(delta.y, allowedBounds.minY - bounds.minY), allowedBounds.maxY - bounds.maxY)
        )
    }

    private func groupBounds(for items: [AnnotationItem]) -> CGRect {
        guard let first = items.first else { return .zero }
        return items.dropFirst().reduce(first.bounds) { bounds, item in bounds.union(item.bounds) }
    }

    func updateItem(id: AnnotationItem.ID, item: AnnotationItem) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = item
    }

    func updateItem(id: AnnotationItem.ID, mutate: (inout AnnotationItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        mutate(&item)
        items[index] = item
    }

    private func updateSelectedItems(mutate: (inout AnnotationItem) -> Void) {
        for index in items.indices where selectedItemIDs.contains(items[index].id) {
            mutate(&items[index])
        }
    }

    private func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in rect.union(CGRect(origin: point, size: .zero)) }
    }

    private func freehandPoints(adding point: CGPoint, to points: [CGPoint]) -> [CGPoint] {
        guard let last = points.last else { return [point] }
        let minimumSpacing: CGFloat = 0.0015
        guard hypot(point.x - last.x, point.y - last.y) >= minimumSpacing else { return points }
        var updatedPoints = points
        updatedPoints.append(point)
        return updatedPoints
    }

    private func syncNextNumberedCircleValue() {
        let currentMaximum = items.filter { $0.tool == .numberedCircle }.compactMap { Int($0.text) }.max() ?? 0
        nextNumberedCircleValue = currentMaximum + 1
    }

    private func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }
}
