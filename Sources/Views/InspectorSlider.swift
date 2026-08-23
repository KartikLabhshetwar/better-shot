import AppKit
import SwiftUI

enum InspectorSliderMetrics {
    static let height: CGFloat = 30
    static let valueWidth: CGFloat = 58
    static let radius: CGFloat = 8
}

struct InspectorSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: InspectorValueFormat
    var onEditingChanged: ((Bool) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var focusedPart: FocusedPart?
    @State private var draftText = ""
    @State private var editingBaselineText = ""
    @State private var isTrackHovering = false
    @State private var isDragging = false

    private enum FocusedPart: Hashable {
        case track
        case value
    }

    init(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: InspectorValueFormat,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        HStack(spacing: 7) {
            GeometryReader { proxy in
                scrubTrack(width: proxy.size.width)
            }
            .frame(height: InspectorSliderMetrics.height)

            valueField
                .frame(width: InspectorSliderMetrics.valueWidth)
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: syncDraftText)
        .onDisappear {
            if focusedPart == .value {
                commitDraftText()
            }
        }
        .onChange(of: value) { _, _ in
            syncDraftText()
        }
        .onChange(of: focusedPart) { oldPart, newPart in
            if newPart == .value {
                beginValueEditing()
            } else if oldPart == .value {
                commitDraftText()
            }
        }
    }

    private func scrubTrack(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: InspectorSliderMetrics.radius, style: .continuous)
        let revealsMarkers = isTrackHovering || isDragging || focusedPart == .track

        return ZStack(alignment: .leading) {
            shape.fill(trackFill)

            Rectangle()
                .fill(positionFill)
                .frame(width: width * normalizedProgress)
                .frame(maxHeight: .infinity)

            InspectorSliderMarkers(progress: normalizedProgress, zeroProgress: zeroProgress)
                .opacity(revealsMarkers ? 1 : 0)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(1)
                .padding(.horizontal, 10)
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(trackStroke(revealsMarkers: revealsMarkers), lineWidth: 0.5)
        }
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if focusedPart == .value {
                        commitDraftText()
                    }
                    focusedPart = .track
                    if !isDragging {
                        isDragging = true
                        onEditingChanged?(true)
                    }
                    updateValue(for: drag.location.x, width: width)
                }
                .onEnded { _ in
                    isDragging = false
                    onEditingChanged?(false)
                }
        )
        .onHover { hovering in
            isTrackHovering = hovering
            guard isEnabled else { return }
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .allowsHitTesting(isEnabled)
        .focusable(isEnabled)
        .focused($focusedPart, equals: .track)
        .onKeyPress(.leftArrow) {
            guard isEnabled else { return .ignored }
            nudgeValue(by: -format.step)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard isEnabled else { return .ignored }
            nudgeValue(by: format.step)
            return .handled
        }
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12), value: revealsMarkers)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format.displayString(for: value))
        .accessibilityHint("Drag horizontally to adjust, or edit the value field")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                nudgeValue(by: format.step)
            case .decrement:
                nudgeValue(by: -format.step)
            @unknown default:
                break
            }
        }
    }

    private var valueField: some View {
        TextField(title, text: $draftText)
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.primary.opacity(0.82))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .focused($focusedPart, equals: .value)
            .onSubmit {
                commitDraftText()
                focusedPart = nil
            }
            .onExitCommand {
                draftText = editingBaselineText
                focusedPart = nil
            }
            .onKeyPress(.upArrow) {
                guard isEnabled else { return .ignored }
                commitDraftText()
                nudgeValue(by: format.step)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard isEnabled else { return .ignored }
                commitDraftText()
                nudgeValue(by: -format.step)
                return .handled
            }
            .frame(height: InspectorSliderMetrics.height)
            .background(
                RoundedRectangle(cornerRadius: InspectorSliderMetrics.radius, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: InspectorSliderMetrics.radius, style: .continuous)
                    .stroke(
                        focusedPart == .value ? Color.accentColor.opacity(0.72) : fieldStroke,
                        lineWidth: focusedPart == .value ? 1 : 0.5
                    )
            }
            .accessibilityLabel("\(title) value")
            .help("Enter an exact value for \(title)")
    }

    private var normalizedProgress: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span.isFinite, span > 0, value.isFinite else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var zeroProgress: CGFloat? {
        guard range.lowerBound.isFinite,
              range.upperBound.isFinite,
              range.lowerBound < 0,
              range.upperBound > 0 else { return nil }
        return (0 - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var trackFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.04)
    }

    private var fieldFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }

    private var fieldStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var positionFill: Color {
        if isDragging || focusedPart == .track {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.075)
    }

    private func trackStroke(revealsMarkers: Bool) -> Color {
        if focusedPart == .track {
            return Color.accentColor.opacity(0.72)
        }
        return Color.primary.opacity(revealsMarkers ? 0.16 : 0.10)
    }

    private func updateValue(for locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }

        if let zeroProgress {
            let zeroX = zeroProgress * width
            let detentRadius: CGFloat = 3
            let leftSpan = zeroX - detentRadius
            let rightSpan = width - zeroX - detentRadius
            if leftSpan > 0, rightSpan > 0 {
                if abs(locationX - zeroX) <= detentRadius {
                    setValue(0)
                } else if locationX < zeroX {
                    let progress = min(max(locationX / leftSpan, 0), 1)
                    setValue(range.lowerBound * (1 - progress))
                } else {
                    let progress = min(max((locationX - zeroX - detentRadius) / rightSpan, 0), 1)
                    setValue(range.upperBound * progress)
                }
                return
            }
        }

        let progress = min(max(locationX / width, 0), 1)
        setValue(range.lowerBound + progress * (range.upperBound - range.lowerBound))
    }

    private func nudgeValue(by delta: CGFloat) {
        guard delta.isFinite else { return }
        onEditingChanged?(true)
        setValue(value + delta)
        onEditingChanged?(false)
    }

    private func setValue(_ proposedValue: CGFloat) {
        guard isEnabled,
              proposedValue.isFinite,
              range.lowerBound.isFinite,
              range.upperBound.isFinite else { return }

        let clampedValue = min(max(proposedValue, range.lowerBound), range.upperBound)
        guard clampedValue != value else { return }
        value = clampedValue
    }

    private func syncDraftText() {
        if focusedPart == .value {
            beginValueEditing()
        } else {
            draftText = format.displayString(for: value)
        }
    }

    private func beginValueEditing() {
        let editingText = format.editingString(for: value)
        editingBaselineText = editingText
        draftText = editingText
    }

    private func commitDraftText() {
        guard draftText != editingBaselineText, let parsedValue = format.parse(draftText) else {
            syncDraftText()
            return
        }

        onEditingChanged?(true)
        setValue(parsedValue)
        onEditingChanged?(false)
        editingBaselineText = format.editingString(for: value)
        syncDraftText()
    }
}

private struct InspectorSliderMarkers: View {
    let progress: CGFloat
    let zeroProgress: CGFloat?

    var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            let leadingX = min(max(size.width * 0.34, 68), size.width - 40)
            let trailingX = max(leadingX, size.width - 12)
            let spacing = max((trailingX - leadingX) / 6, 8)

            if let zeroProgress {
                let zeroX = min(max(zeroProgress * size.width, 4), size.width - 4)
                for direction: CGFloat in [-1, 1] {
                    for step in 1...32 {
                        let x = zeroX + direction * CGFloat(step) * spacing
                        if direction > 0 && x > trailingX { break }
                        if direction < 0 && x < leadingX { break }
                        guard x >= leadingX, x <= trailingX else { continue }
                        drawMarker(in: &context, x: x, centerY: centerY, height: 10, color: Color.primary.opacity(0.22), lineWidth: 1)
                    }
                }
                drawMarker(in: &context, x: zeroX, centerY: centerY, height: 14, color: Color.primary.opacity(0.38), lineWidth: 1.5)
            } else {
                let markerCount = 7
                for index in 0..<markerCount {
                    let fraction = CGFloat(index) / CGFloat(markerCount - 1)
                    let x = leadingX + fraction * (trailingX - leadingX)
                    drawMarker(in: &context, x: x, centerY: centerY, height: 10, color: Color.primary.opacity(0.22), lineWidth: 1)
                }
            }

            let currentX = min(max(progress * size.width, 4), size.width - 4)
            drawMarker(in: &context, x: currentX, centerY: centerY, height: 18, color: Color.primary.opacity(0.68), lineWidth: 3)
        }
        .allowsHitTesting(false)
    }

    private func drawMarker(
        in context: inout GraphicsContext,
        x: CGFloat,
        centerY: CGFloat,
        height: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: centerY - height / 2))
        path.addLine(to: CGPoint(x: x, y: centerY + height / 2))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
