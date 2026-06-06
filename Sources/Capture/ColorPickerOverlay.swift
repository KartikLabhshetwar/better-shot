import AppKit
import SwiftUI

@MainActor
final class ColorPickerOverlay {

    func pickColor() async -> String? {
        let sampler = NSColorSampler()
        let color = await withCheckedContinuation { (cont: CheckedContinuation<NSColor?, Never>) in
            sampler.show { selectedColor in
                cont.resume(returning: selectedColor)
            }
        }
        guard let color else { return nil }
        return hexFromColor(color)
    }

    private func hexFromColor(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
