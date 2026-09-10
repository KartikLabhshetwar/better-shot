import AppKit

// Finder uses points for icon placement. Include both 1× and 2× artwork.
let size = NSSize(width: 660, height: 440)
var representations: [NSBitmapImageRep] = []
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
        pixelsHigh: Int(size.height) * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(srgbRed: 0.965, green: 0.953, blue: 0.99, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    func text(_ value: String, top: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (value as NSString).draw(
            in: NSRect(x: 24, y: size.height - top - 40, width: size.width - 48, height: 40),
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        )
    }

    text("Welcome to BetterShot", top: 40,
         font: .systemFont(ofSize: 29, weight: .semibold),
         color: NSColor(srgbRed: 0.18, green: 0.14, blue: 0.25, alpha: 1))
    text("Drag BetterShot into Applications to install.", top: 85,
         font: .systemFont(ofSize: 15),
         color: NSColor(srgbRed: 0.38, green: 0.34, blue: 0.44, alpha: 1))

    let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 32, weight: .medium))!
        .withSymbolConfiguration(.init(paletteColors: [
            NSColor(srgbRed: 0.49, green: 0.27, blue: 0.83, alpha: 1)
        ]))!
    arrow.draw(in: NSRect(x: 310, y: 440 - 230 - 16, width: 40, height: 32))

    text("Then open BetterShot from Applications.", top: 367,
         font: .systemFont(ofSize: 13),
         color: NSColor(srgbRed: 0.38, green: 0.34, blue: 0.44, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    representations.append(bitmap)
}

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift dmg-background.swift output.tiff")
}
let image = NSImage(size: size)
representations.forEach { image.addRepresentation($0) }
let data = image.tiffRepresentation(using: .lzw, factor: 1)!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
