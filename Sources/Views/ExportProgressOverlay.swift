import SwiftUI

/// Modal export status: a dimming scrim pushes the editor back while a determinate ring reports the render.
struct ExportProgressOverlay: View {
    let progress: Double
    let onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDeterminate: Bool { progress > 0 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ExportProgressRing(progress: progress, isDeterminate: isDeterminate)
                    .frame(width: 64, height: 64)

                VStack(spacing: 3) {
                    Text("Exporting")
                        .font(.system(size: 14, weight: .semibold))
                        .kerning(-0.1)

                    Text(isDeterminate ? "\(Int(progress * 100))%" : "Preparing\u{2026}")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: progress * 100))
                        .monospacedDigit()
                }

                if let onCancel {
                    InspectorPill("Cancel", action: onCancel)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .glassSurface(cornerRadius: 18, depth: .raised)
        }
        .transition(exportTransition)
    }

    /// Glass arrives as a material, so the blur and the scale resolve together instead of a flat fade.
    private var exportTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.94)).combined(with: .modifier(
                active: BlurIn(radius: 14),
                identity: BlurIn(radius: 0)
            ))
    }
}

private struct BlurIn: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private struct ExportProgressRing: View {
    let progress: Double
    let isDeterminate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 5)

            Circle()
                .trim(from: 0, to: isDeterminate ? max(0.02, progress) : 0.22)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(isDeterminate ? -90 : (sweep ? 270 : -90)))
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1), value: progress)
                .animation(
                    isDeterminate || reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false),
                    value: sweep
                )
        }
        .onAppear { sweep = true }
        .accessibilityElement()
        .accessibilityLabel("Exporting")
        .accessibilityValue(isDeterminate ? "\(Int(progress * 100)) percent" : "Preparing")
    }
}
