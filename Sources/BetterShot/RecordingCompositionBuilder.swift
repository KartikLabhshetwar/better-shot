//
//  RecordingCompositionBuilder.swift
//  BetterShot
//
//  Shared gap-closing composition used by Studio playback and export.
//

import AVFoundation

nonisolated enum RecordingCompositionBuilder {
    static func makeAsset(
        from sourceAsset: AVAsset,
        timeline: RecordingClipTimeline,
        sourceDuration: TimeInterval
    ) throws -> AVAsset {
        let normalized = timeline.normalized(to: sourceDuration)
        if normalized.isUnedited(sourceDuration: sourceDuration) {
            return sourceAsset
        }

        let composition = AVMutableComposition()
        var insertionTime = CMTime.zero
        for clip in normalized.segments {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            try composition.insertTimeRange(range, of: sourceAsset, at: insertionTime)

            // Retiming here scales every track inserted above together
            // (video and audio alike), so a sped-up clip never drifts out
            // of sync the way independently retiming each track would.
            if abs(clip.speed - 1) > 0.000_001 {
                let insertedRange = CMTimeRange(start: insertionTime, duration: range.duration)
                let scaledDuration = CMTime(seconds: clip.editorDuration, preferredTimescale: 600)
                composition.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                insertionTime = insertionTime + scaledDuration
            } else {
                insertionTime = insertionTime + range.duration
            }
        }
        return composition
    }

    struct PreparedSource: @unchecked Sendable {
        struct Track {
            let track: AVAssetTrack
            let range: CMTimeRange
        }
        let id: UUID
        let duration: TimeInterval
        let asset: AVAsset
        let video: Track
        let audio: [Track]
    }

    static func prepareSources(_ sources: [RecordingStudioSourceConfiguration]) async throws -> [PreparedSource] {
        guard !sources.isEmpty, Set(sources.map(\.id)).count == sources.count else {
            throw RecordingStudioSourceResolver.ResolutionError.invalidSources
        }
        var result: [PreparedSource] = []
        for source in sources {
            try Task.checkCancellation()
            let configuration = source.configuration
            guard configuration.sources.isEmpty,
                  configuration.clipTimeline.segments.allSatisfy({ $0.sourceID == nil }) else {
                throw RecordingStudioSourceResolver.ResolutionError.nestedProject
            }
            let raw = AVURLAsset(url: configuration.screenURL)
            let duration = try await raw.load(.duration).seconds
            let authoredAsset: AVAsset
            if let replacementURL = configuration.audioReplacementURL {
                guard let video = try await raw.loadTracks(withMediaType: .video).first,
                      let replacement = await RecordingReplacementAudio.load(
                        url: replacementURL, displayName: replacementURL.lastPathComponent) else {
                    throw RecordingStudioSourceResolver.ResolutionError.missingSource
                }
                authoredAsset = try makeAsset(videoTrack: video,
                    timeline: configuration.clipTimeline, sourceDuration: duration,
                    replacementAudio: replacement)
            } else {
                authoredAsset = try makeAsset(from: raw,
                    timeline: configuration.clipTimeline, sourceDuration: duration)
            }
            guard let video = try await authoredAsset.loadTracks(withMediaType: .video).first else {
                throw RecordingStudioExporter.ExportError.noVideoTrack
            }
            var audio: [PreparedSource.Track] = []
            if !configuration.exportSettings.removeAudio {
                for track in try await authoredAsset.loadTracks(withMediaType: .audio) {
                    audio.append(PreparedSource.Track(track: track, range: try await track.load(.timeRange)))
                }
            }
            result.append(PreparedSource(id: source.id, duration: configuration.clipTimeline.duration,
                asset: authoredAsset, video: PreparedSource.Track(track: video, range: try await video.load(.timeRange)),
                audio: audio))
        }
        return result
    }

    static func makeAsset(sources: [RecordingStudioSourceConfiguration], timeline: RecordingClipTimeline) async throws -> AVAsset {
        try makeAsset(sources: await prepareSources(sources), timeline: timeline)
    }

    /// Prepared assets keep synchronous timeline edits independent of media loading.
    static func makeAsset(sources: [PreparedSource], timeline: RecordingClipTimeline) throws -> AVAsset {
        guard !sources.isEmpty, Set(sources.map(\.id)).count == sources.count else {
            throw RecordingStudioSourceResolver.ResolutionError.invalidSources
        }
        _ = try timeline.validated(sourceDurations: Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.duration) }))
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }
        var insertionTime = CMTime.zero
        for clip in timeline.segments {
            guard let source = sources.first(where: { $0.id == clip.sourceID }) else {
                throw RecordingStudioSourceResolver.ResolutionError.missingSource
            }
            let range = CMTimeRange(
                start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600))
            try video.insertTimeRange(range, of: source.video.track, at: insertionTime)
            // Separate audio tracks preserve silence and differing track counts between leaves.
            for track in source.audio {
                let available = CMTimeRangeGetIntersection(range, otherRange: track.range)
                if available.duration > .zero {
                    guard let destination = composition.addMutableTrack(withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw RecordingStudioExporter.ExportError.writerFailed(nil)
                    }
                    try destination.insertTimeRange(available, of: track.track,
                        at: insertionTime + (available.start - range.start))
                }
            }
            let scaledDuration = CMTime(seconds: clip.editorDuration, preferredTimescale: 600)
            composition.scaleTimeRange(CMTimeRange(start: insertionTime, duration: range.duration),
                                       toDuration: scaledDuration)
            insertionTime = insertionTime + scaledDuration
        }
        return composition
    }

    /// Playback asset whose soundtrack comes from an imported file instead
    /// of the recording's own audio. The video track arrives already
    /// resolved so Studio can rebuild the player item synchronously, the
    /// way it does on every trim.
    static func makeAsset(
        videoTrack: AVAssetTrack,
        timeline: RecordingClipTimeline,
        sourceDuration: TimeInterval,
        replacementAudio: RecordingReplacementAudio
    ) throws -> AVAsset {
        let normalized = timeline.normalized(to: sourceDuration)
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }

        var insertionTime = CMTime.zero
        for clip in normalized.segments {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            try video.insertTimeRange(range, of: videoTrack, at: insertionTime)

            if abs(clip.speed - 1) > 0.000_001 {
                let insertedRange = CMTimeRange(start: insertionTime, duration: range.duration)
                let scaledDuration = CMTime(seconds: clip.editorDuration, preferredTimescale: 600)
                video.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                insertionTime = insertionTime + scaledDuration
            } else {
                insertionTime = insertionTime + range.duration
            }
        }

        // The import is already the finished cut's soundtrack, so it lies
        // flat from zero rather than being re-cut through the clip list -
        // and is clipped to whatever the timeline still holds.
        let audioLength = min(replacementAudio.duration, insertionTime.seconds)
        if audioLength > 0,
           let audio = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try audio.insertTimeRange(
                CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: audioLength, preferredTimescale: 600)
                ),
                of: replacementAudio.track,
                at: .zero
            )
        }
        return composition
    }
}
