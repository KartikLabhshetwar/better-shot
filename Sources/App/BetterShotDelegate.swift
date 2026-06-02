import AppKit
import AVFoundation

@MainActor
final class BetterShotDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ShortcutService.shared.registerAll()
        configureRecordingCallback()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShortcutService.shared.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func configureRecordingCallback() {
        ScreenRecorder.shared.onFinished = { @MainActor url in
            Task {
                let dir = AppPreferences.saveDirectory
                let stamp = Int(Date().timeIntervalSince1970 * 1000)

                // 1. Save raw video
                let videoPath = "\(dir)/bettershot_\(stamp).mov"
                let videoURL = URL(fileURLWithPath: videoPath)
                do {
                    try FileManager.default.copyItem(at: url, to: videoURL)
                } catch {
                    print("Failed to save recording: \(error)")
                    return
                }

                // 2. Compress via videokit if available
                let processor = VideoProcessor.shared
                await processor.checkFFmpeg()
                if processor.ffmpegAvailable {
                    let compressedPath = "\(dir)/bettershot_\(stamp)_c.mov"
                    let opts = VideoProcessor.CompressOptions(
                        input_path: videoPath,
                        output_path: compressedPath,
                        quality: "medium",
                        speed: "fast",
                        codec: "hevc",
                        resolution: "original",
                        remove_audio: true
                    )
                    if let result = await processor.compress(opts),
                       result.success,
                       let outputPath = result.output_path {
                        try? FileManager.default.removeItem(at: videoURL)
                        try? FileManager.default.moveItem(
                            at: URL(fileURLWithPath: outputPath),
                            to: videoURL
                        )
                    }
                }

                // 3. Extract first frame as PNG for the editor
                let frameURL = await Self.extractFrame(from: videoURL, stamp: stamp)

                // 4. Show preview overlay (clicking pen opens editor with the frame)
                if let frameURL {
                    PreviewOverlay.shared.show(url: frameURL)
                } else {
                    PreviewOverlay.shared.show(url: videoURL)
                }

                // Clean up temp recording
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func extractFrame(from videoURL: URL, stamp: Int) async -> URL? {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            let dir = AppPreferences.saveDirectory
            let framePath = "\(dir)/bettershot_\(stamp)_frame.png"
            let frameURL = URL(fileURLWithPath: framePath)

            guard let dest = CGImageDestinationCreateWithURL(
                frameURL as CFURL, "public.png" as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }

            return frameURL
        } catch {
            print("Failed to extract frame: \(error)")
            return nil
        }
    }
}
