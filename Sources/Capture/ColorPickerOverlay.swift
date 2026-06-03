import AppKit
import SwiftUI

@MainActor
final class ColorPickerOverlay {

    private var hudPanel: NSPanel?

    func pickColor() async -> String? {
        let sampler = NSColorSampler()
        let color = await withCheckedContinuation { (cont: CheckedContinuation<NSColor?, Never>) in
            sampler.show { selectedColor in
                cont.resume(returning: selectedColor)
            }
        }
        guard let color else { return nil }
        let hex = hexFromColor(color)
        showHUD(hex: hex, color: color)
        return hex
    }

    private func showHUD(hex: String, color: NSColor) {
        let mouseLocation = NSEvent.mouseLocation
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let hudView = NSHostingView(rootView: ColorHUDView(hex: hex, color: Color(nsColor: color)))
        panel.contentView = hudView

        panel.setFrameOrigin(NSPoint(
            x: mouseLocation.x - 90,
            y: mouseLocation.y + 20
        ))
        panel.orderFront(nil)
        hudPanel = panel

        Task {
            try? await Task.sleep(for: .seconds(2.0))
            panel.orderOut(nil)
            hudPanel = nil
        }
    }

    private func hexFromColor(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

private struct ColorHUDView: View {
    let hex: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )

            Text(hex)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)

            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
