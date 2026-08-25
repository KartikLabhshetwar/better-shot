//
//  AnnotationInspectorSlider.swift
//  BetterShot
//

import Foundation
import SwiftUI

/// Display and editing rules for an inspector value. The bound value always
/// stays in model units; `multiplier` only transforms what the user sees and
/// types (for example, 0.45 is displayed as 45%).
struct InspectorValueFormat {
    let multiplier: CGFloat
    let fractionDigits: Int
    let suffix: String
    let showsPositiveSign: Bool
    let step: CGFloat
    let acceptedSuffixes: [String]

    static let integer = InspectorValueFormat(
        multiplier: 1,
        fractionDigits: 0,
        suffix: "",
        showsPositiveSign: false,
        step: 1,
        acceptedSuffixes: []
    )

    static let pixels = InspectorValueFormat(
        multiplier: 1,
        fractionDigits: 0,
        suffix: " px",
        showsPositiveSign: false,
        step: 1,
        acceptedSuffixes: ["pixels", "pixel", "px"]
    )

    static func percent(
        signed: Bool = false,
        fractionDigits: Int = 0
    ) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 100,
            fractionDigits: fractionDigits,
            suffix: "%",
            showsPositiveSign: signed,
            step: step(forFractionDigits: fractionDigits) / 100,
            acceptedSuffixes: ["%"]
        )
    }

    static func degrees(signed: Bool = false) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 1,
            fractionDigits: 0,
            suffix: "°",
            showsPositiveSign: signed,
            step: 1,
            acceptedSuffixes: ["degrees", "degree", "deg", "°"]
        )
    }

    static func decimal(fractionDigits: Int) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 1,
            fractionDigits: fractionDigits,
            suffix: "",
            showsPositiveSign: false,
            step: step(forFractionDigits: fractionDigits),
            acceptedSuffixes: []
        )
    }

    static func magnification(fractionDigits: Int) -> InspectorValueFormat {
        InspectorValueFormat(
            multiplier: 1,
            fractionDigits: fractionDigits,
            suffix: "×",
            showsPositiveSign: false,
            step: step(forFractionDigits: fractionDigits),
            acceptedSuffixes: ["×", "x"]
        )
    }

    func displayString(for value: CGFloat) -> String {
        let scaledValue = value * multiplier
        let number = formattedNumber(scaledValue)
        let sign = showsPositiveSign && roundedForDisplay(scaledValue) > 0 ? "+" : ""
        return sign + number + suffix
    }

    func editingString(for value: CGFloat) -> String {
        formattedNumber(value * multiplier)
    }

    func parse(_ text: String) -> CGFloat? {
        var numericText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")

        for acceptedSuffix in acceptedSuffixes {
            numericText = numericText.replacingOccurrences(
                of: acceptedSuffix,
                with: "",
                options: [.caseInsensitive, .anchored, .backwards]
            )
        }

        numericText = numericText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsed = try? FloatingPointFormatStyle<Double>.number
            .parseStrategy
            .parse(numericText), parsed.isFinite else {
            return nil
        }

        return CGFloat(parsed) / multiplier
    }

    private func formattedNumber(_ value: CGFloat) -> String {
        let normalizedValue = roundedForDisplay(value)
        return Double(normalizedValue).formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .grouping(.never)
        )
    }

    private func roundedForDisplay(_ value: CGFloat) -> CGFloat {
        let scale = CGFloat(pow(10, Double(fractionDigits)))
        let rounded = (value * scale).rounded() / scale
        return abs(rounded) < CGFloat.ulpOfOne ? 0 : rounded
    }

    private static func step(forFractionDigits fractionDigits: Int) -> CGFloat {
        1 / CGFloat(pow(10, Double(max(fractionDigits, 0))))
    }
}

/// A compact label-in-track scrubber paired with an exact editable value.
/// Hovering or focusing reveals calibrated markers and the current position;
/// the full left field remains draggable, so there is no tiny thumb to chase.
struct InspectorSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: InspectorValueFormat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var focusedPart: FocusedPart?
    @State private var draftText = ""
    @State private var editingBaselineText = ""
    @State private var valueSelection: TextSelection?
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
        format: InspectorValueFormat
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        HStack(spacing: 7) {
            GeometryReader { proxy in
                scrubTrack(width: proxy.size.width)
            }
            .frame(height: InspectorMetrics.sliderHeight)

            valueField
                .frame(width: InspectorMetrics.sliderValueWidth)
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
        let shape = RoundedRectangle(
            cornerRadius: InspectorMetrics.sliderRadius,
            style: .continuous
        )
        let revealsMarkers = isTrackHovering || isDragging || focusedPart == .track

        return ZStack(alignment: .leading) {
            shape.fill(trackFill)

            Rectangle()
                .fill(positionFill)
                .frame(width: width * normalizedProgress)
                .frame(maxHeight: .infinity)

            InspectorSliderMarkers(
                progress: normalizedProgress,
                zeroProgress: zeroProgress
            )
            .opacity(revealsMarkers ? 1 : 0)

            Text(title)
                .font(.inspectorValue)
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
                    isDragging = true
                    updateValue(for: drag.location.x, width: width)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onHover { isTrackHovering = $0 }
        .allowsHitTesting(isEnabled)
        .pointerStyle(isEnabled ? PointerStyle.columnResize : nil)
        .focusable(isEnabled)
        .focused($focusedPart, equals: .track)
        .onKeyPress(.leftArrow) {
            guard isEnabled else { return .ignored }
            adjustValue(by: -format.step)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard isEnabled else { return .ignored }
            adjustValue(by: format.step)
            return .handled
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.12),
            value: revealsMarkers
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format.displayString(for: value))
        .accessibilityHint("Drag horizontally to adjust, or edit the value field")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustValue(by: format.step)
            case .decrement:
                adjustValue(by: -format.step)
            @unknown default:
                break
            }
        }
    }

    private var valueField: some View {
        TextField(title, text: $draftText, selection: $valueSelection)
            .textFieldStyle(.plain)
            .font(.inspectorNumeric)
            .foregroundStyle(.primary.opacity(0.82))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
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
                adjustValue(by: format.step)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard isEnabled else { return .ignored }
                commitDraftText()
                adjustValue(by: -format.step)
                return .handled
            }
            .inspectorField(
                height: InspectorMetrics.sliderHeight,
                cornerRadius: InspectorMetrics.sliderRadius
            )
            .overlay {
                if focusedPart == .value {
                    RoundedRectangle(
                        cornerRadius: InspectorMetrics.sliderRadius,
                        style: .continuous
                    )
                    .stroke(Color.accentColor.opacity(0.72), lineWidth: 1)
                }
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
        InspectorControlPalette.trackFill(for: colorScheme)
    }

    private var positionFill: Color {
        if isDragging || focusedPart == .track {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }
        return InspectorControlPalette.selectionFill(for: colorScheme)
    }

    private func trackStroke(revealsMarkers: Bool) -> Color {
        if focusedPart == .track {
            return Color.accentColor.opacity(0.72)
        }
        return Color.primary.opacity(revealsMarkers ? 0.16 : 0.10)
    }

    private func updateValue(for locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }

        // Soft detent: a small sticky zone lands exactly on 0, and each side
        // of the track is remapped around it so near-zero values stay
        // reachable instead of being swallowed by the snap radius. Keyboard
        // and typed input stay precise and never snap.
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
                    let progress = min(
                        max((locationX - zeroX - detentRadius) / rightSpan, 0),
                        1
                    )
                    setValue(range.upperBound * progress)
                }
                return
            }
        }

        let progress = min(max(locationX / width, 0), 1)
        let proposedValue = range.lowerBound
            + progress * (range.upperBound - range.lowerBound)
        setValue(proposedValue)
    }

    private func adjustValue(by delta: CGFloat) {
        guard delta.isFinite else { return }
        setValue(value + delta)
    }

    private func setValue(_ proposedValue: CGFloat) {
        guard isEnabled,
              proposedValue.isFinite,
              range.lowerBound.isFinite,
              range.upperBound.isFinite else { return }

        // Keep pointer dragging continuous like the native sliders this
        // replaces. `step` is reserved for keyboard and accessibility nudges,
        // so existing preset/document precision is never silently quantized.
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
        valueSelection = TextSelection(range: editingText.startIndex..<editingText.endIndex)
    }

    private func commitDraftText() {
        guard draftText != editingBaselineText else {
            syncDraftText()
            return
        }

        guard let parsedValue = format.parse(draftText) else {
            syncDraftText()
            return
        }

        setValue(parsedValue)
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
                // Anchor the grid on the zero detent and grow outward, so the
                // zero mark is one of the evenly spaced markers instead of a
                // stray line sitting between decorative ticks.
                let zeroX = min(max(zeroProgress * size.width, 4), size.width - 4)
                for direction: CGFloat in [-1, 1] {
                    for step in 1...32 {
                        let x = zeroX + direction * CGFloat(step) * spacing
                        if direction > 0 && x > trailingX { break }
                        if direction < 0 && x < leadingX { break }
                        guard x >= leadingX, x <= trailingX else { continue }
                        drawMarker(
                            in: &context,
                            x: x,
                            centerY: centerY,
                            height: 10,
                            color: Color.primary.opacity(0.22),
                            lineWidth: 1
                        )
                    }
                }
                drawMarker(
                    in: &context,
                    x: zeroX,
                    centerY: centerY,
                    height: 14,
                    color: Color.primary.opacity(0.38),
                    lineWidth: 1.5
                )
            } else {
                let markerCount = 7
                for index in 0..<markerCount {
                    let fraction = CGFloat(index) / CGFloat(markerCount - 1)
                    let x = leadingX + fraction * (trailingX - leadingX)
                    drawMarker(
                        in: &context,
                        x: x,
                        centerY: centerY,
                        height: 10,
                        color: Color.primary.opacity(0.22),
                        lineWidth: 1
                    )
                }
            }

            let currentX = min(max(progress * size.width, 4), size.width - 4)
            drawMarker(
                in: &context,
                x: currentX,
                centerY: centerY,
                height: 18,
                color: Color.primary.opacity(0.68),
                lineWidth: 3
            )
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
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
    }
}
