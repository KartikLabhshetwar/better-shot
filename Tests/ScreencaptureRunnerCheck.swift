import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stands in for `screencapture` with shell scripts, so no capture runs.
@main
enum ScreencaptureRunnerCheck {
    static func main() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreencaptureRunnerCheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("fixture.png")
        try writeFixture(to: png)

        // screencapture saves the PNG, then can wait up to 10 s on Spotlight before exiting.
        var output = dir.appendingPathComponent("saved.png").path
        var start = Date()
        var outcome = try await ScreencaptureRunner.run([output], output: output,
            executable: script("cp '\(png.path)' \"$1\"; sleep 5", in: dir))
        precondition(outcome == .saved, "a saved PNG reports saved, got \(outcome)")
        precondition(Date().timeIntervalSince(start) < 2, "a saved PNG must not wait for the process to exit")

        // A PNG still being written is not saved yet.
        output = dir.appendingPathComponent("partial.png").path
        outcome = try await ScreencaptureRunner.run([output], output: output,
            executable: script("head -c 40 '\(png.path)' > \"$1\"; sleep 1; cp '\(png.path)' \"$1\"; sleep 5", in: dir))
        precondition(outcome == .saved, "the completed PNG reports saved, got \(outcome)")
        let written = try Data(contentsOf: URL(fileURLWithPath: output)), fixture = try Data(contentsOf: png)
        precondition(written == fixture, "saved must wait until the PNG is complete")

        // Cancelling writes nothing, so the exit status decides.
        output = dir.appendingPathComponent("cancelled.png").path
        start = Date()
        outcome = try await ScreencaptureRunner.run([output], output: output,
            executable: script("exit 1", in: dir))
        precondition(outcome == .exited(status: 1, diagnostic: ""), "cancel reports the exit, got \(outcome)")

        output = dir.appendingPathComponent("failed.png").path
        outcome = try await ScreencaptureRunner.run([output], output: output,
            executable: script("echo 'no permission' >&2; exit 2", in: dir))
        precondition(outcome == .exited(status: 2, diagnostic: "no permission\n"), "failure keeps its diagnostic, got \(outcome)")

        print("ScreencaptureRunnerCheck passed")
    }

    private static func script(_ body: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("fake-\(UUID().uuidString).sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private static func writeFixture(to url: URL) throws {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
