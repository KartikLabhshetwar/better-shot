//
//  RecordingRecoveryCoordinator.swift
//  BetterShot
//
//  Discovers fragmented screen movies left by a crash or forced termination.
//  A missing manifest is the interrupted-session marker: normally finalized
//  recordings always write capture.json before they enter History.
//

import AppKit
import AVFoundation
@preconcurrency import CoreMedia

@MainActor
enum RecordingRecoveryCoordinator {
    static func recoverInterruptedRecordings() {
        Task {
            let candidates = RecordingSessionStore.allSessions().filter {
                $0.loadCaptureManifest() == nil
            }
            guard !candidates.isEmpty else { return }

            var recoveredCount = 0
            for session in candidates {
                guard let metadata = await playableMetadata(for: session.screenURL) else {
                    // Never delete uncertain footage. It remains in Recordings
                    // for manual inspection even when AVFoundation cannot open it.
                    continue
                }

                var manifest = CaptureManifest()
                manifest.duration = metadata.duration
                manifest.pixelWidth = metadata.width
                manifest.pixelHeight = metadata.height
                try? session.writeCaptureManifest(manifest)
                _ = await ScreenshotHistoryStore.shared.importRecordingSession(session)
                recoveredCount += 1
            }

            guard recoveredCount > 0 else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = recoveredCount == 1
                ? "Recovered an interrupted recording"
                : "Recovered \(recoveredCount) interrupted recordings"
            alert.informativeText = "The playable footage was preserved in History and can be reopened in BetterShot Studio."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private static func playableMetadata(for url: URL) async -> (duration: Double, width: Int, height: Int)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let durationTime = try? await asset.load(.duration) else {
            return nil
        }

        let seconds = CMTimeGetSeconds(durationTime)
        guard seconds.isFinite, seconds > 0.1 else { return nil }

        let size = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let transformed = size.applying(transform)
        return (
            duration: seconds,
            width: Int(abs(transformed.width)),
            height: Int(abs(transformed.height))
        )
    }
}
