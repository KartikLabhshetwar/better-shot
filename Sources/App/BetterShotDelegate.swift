import AppKit

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
                // Save raw recording to user's save directory
                let dir = AppPreferences.saveDirectory
                let stamp = Int(Date().timeIntervalSince1970 * 1000)
                let savedPath = "\(dir)/bettershot_\(stamp).mov"
                let savedURL = URL(fileURLWithPath: savedPath)

                do {
                    try FileManager.default.copyItem(at: url, to: savedURL)
                } catch {
                    print("Failed to save recording: \(error)")
                    return
                }

                // Compress via videokit if ffmpeg is available
                let processor = VideoProcessor.shared
                await processor.checkFFmpeg()

                var finalURL = savedURL
                if processor.ffmpegAvailable {
                    let compressedPath = "\(dir)/bettershot_\(stamp)_compressed.mov"
                    let opts = VideoProcessor.CompressOptions(
                        input_path: savedPath,
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
                        finalURL = URL(fileURLWithPath: outputPath)
                        // Remove uncompressed version
                        try? FileManager.default.removeItem(at: savedURL)
                        // Rename compressed to clean name
                        let cleanURL = URL(fileURLWithPath: savedPath)
                        try? FileManager.default.moveItem(at: finalURL, to: cleanURL)
                        finalURL = cleanURL
                    }
                }

                // Import to history
                let record = HistoryStore.shared.importCapture(from: finalURL)
                if let record {
                    let historyURL = HistoryStore.shared.urlForRecord(record)
                    if AppPreferences.showOverlayAfterCapture {
                        PreviewOverlay.shared.show(url: historyURL)
                    }
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
