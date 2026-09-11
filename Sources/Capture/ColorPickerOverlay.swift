import AppKit

@MainActor
final class ColorPickerOverlay {
    enum PickError: LocalizedError {
        case unsupportedColor

        var errorDescription: String? {
            "This color couldn’t be converted to RGB. Try picking another pixel."
        }
    }

    func pickColor() async throws -> String? {
        let sampler = NSColorSampler()
        let color = await withCheckedContinuation { (cont: CheckedContinuation<NSColor?, Never>) in
            sampler.show { selectedColor in
                cont.resume(returning: selectedColor)
            }
        }
        // AppKit completes asynchronously; retain the sampler until it calls back.
        return try withExtendedLifetime(sampler) {
            guard let color else { return nil }
            return try Self.hexFromColor(color)
        }
    }

    static func hexFromColor(_ color: NSColor) throws -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { throw PickError.unsupportedColor }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { throw PickError.unsupportedColor }
        let bytes = components.map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}
