import AppKit
import CoreImage

@main
enum TextRecognitionCheck {
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TextRecognitionCheck-\(UUID().uuidString)")

    static func fixture(_ lines: [String], qr: String? = nil) throws -> URL {
        let size = NSSize(width: 900, height: 160 + 60 * lines.count)
        let image = NSImage(size: size, flipped: false) { bounds in
            NSColor.white.setFill()
            bounds.fill()
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: NSPoint(x: qr == nil ? 20 : 220, y: bounds.height - 80 - CGFloat(index) * 60),
                                        withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
            }
            if let qr, let filter = CIFilter(name: "CIQRCodeGenerator") {
                filter.setValue(Data(qr.utf8), forKey: "inputMessage")
                let code = NSImage(size: NSSize(width: 180, height: 180))
                code.addRepresentation(NSCIImageRep(ciImage: filter.outputImage!.transformed(by: .init(scaleX: 6, y: 6))))
                code.draw(in: NSRect(x: 20, y: 20, width: 180, height: 180))
            }
            return true
        }
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    static func main() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var longestMainActorStall: TimeInterval = 0
        let heartbeat = Task { @MainActor in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                longestMainActorStall = max(longestMainActorStall, Date().timeIntervalSince(last))
                last = Date()
            }
        }

        let start = Date()
        let latin = try await ImageTextRecognizer.recognizeContent(at: fixture(["OCR PROBE 4711 Hello", "Second line here"]))
        assert(latin == "OCR PROBE 4711 Hello\nSecond line here", "Latin lines keep their order, got \(latin.debugDescription)")
        let firstScan = Date().timeIntervalSince(start)
        assert(firstScan < 10, "the first scan must not wait on model compilation, took \(firstScan)s")

        let cjk = try await ImageTextRecognizer.recognizeContent(at: fixture(["你好，世界", "日本語のテキスト"]))
        assert(cjk.contains("你好") && cjk.contains("日本語"), "CJK text needs no language setting, got \(cjk.debugDescription)")

        let cyrillic = try await ImageTextRecognizer.recognizeContent(at: fixture(["Привет мир", "Grüße aus München"]))
        assert(cyrillic.contains("Привет") && cyrillic.contains("München"), "Cyrillic and accented Latin, got \(cyrillic.debugDescription)")

        let code = try await ImageTextRecognizer.recognizeContent(at: fixture(["Scan me please"], qr: "https://bettershot.app/qr"))
        assert(code == "https://bettershot.app/qr\nScan me please", "barcode payload comes before text, got \(code.debugDescription)")

        let blank = try await ImageTextRecognizer.recognizeContent(at: fixture([]))
        assert(blank.isEmpty, "a blank image yields no text, got \(blank.debugDescription)")

        let missing = directory.appendingPathComponent("missing.png")
        do {
            _ = try await ImageTextRecognizer.recognizeContent(at: missing)
            assertionFailure("an unreadable image must throw")
        } catch {}

        heartbeat.cancel()
        assert(longestMainActorStall < 0.5, "recognition must not block the main actor, stalled \(longestMainActorStall)s")
        print("TextRecognitionCheck: Latin, CJK, Cyrillic, barcode, blank, and missing files; first scan \(String(format: "%.2f", firstScan))s, main actor stall \(String(format: "%.2f", longestMainActorStall))s")
    }
}
