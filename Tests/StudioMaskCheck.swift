import CoreGraphics
import Foundation

@main
enum StudioMaskCheck {
    static func main() throws {
        let segment = RecordingMaskSegment()
        precondition(segment.rect == CGRect(x: 0.325, y: 0.325, width: 0.35, height: 0.35))
        precondition(segment.effect == .blur)
        precondition(segment.amount == RecordingMaskSegment.defaultAmount)

        var moved = segment
        moved.rect = CGRect(x: 0.9, y: -0.2, width: 0.5, height: 0.5)
        precondition(moved.rect.maxX <= 1 && moved.rect.minY >= 0)
        precondition(moved.rect.width >= RecordingVideoCrop.minimumSpan)

        precondition(segment.scaledAmount(forHeight: 1080) == 16)
        precondition(segment.scaledAmount(forHeight: 2160) == 32)
        var strong = segment
        strong.amount = 500
        precondition(strong.scaledAmount(forHeight: 1080) == RecordingMaskSegment.maximumAmount)
        var weakSegment = segment
        weakSegment.amount = 0
        precondition(weakSegment.scaledAmount(forHeight: 1080) == RecordingMaskSegment.minimumAmount)

        precondition(segment.isActive(at: 0) && segment.isActive(at: 9999))
        precondition(segment.editorRange(duration: 10) == 0...10)
        var ranged = segment
        ranged.start = 2
        ranged.end = 5
        precondition(ranged.isActive(at: 3))
        precondition(!ranged.isActive(at: 1) && !ranged.isActive(at: 6))
        precondition(ranged.editorRange(duration: 10) == 2...5)
        precondition(ranged.editorRange(duration: 4) == 2...4)
        precondition(ranged.editorRange(duration: 1) == 1...1)

        var pixelated = segment
        pixelated.effect = .pixelate
        pixelated.amount = 24
        let data = try JSONEncoder().encode([pixelated, ranged])
        let decoded = try JSONDecoder().decode([RecordingMaskSegment].self, from: data)
        precondition(decoded == [pixelated, ranged])
        precondition(decoded[0].start == nil && decoded[1].start == 2 && decoded[1].end == 5)

        let extent = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rect = RecordingMaskRenderer.pixelRect(for: segment, in: extent)
        precondition(abs(rect.minX - 0.325 * 1920) < 0.001)
        precondition(abs(rect.minY - (1 - 0.675) * 1080) < 0.001)

        print("StudioMaskCheck passed")
    }
}
