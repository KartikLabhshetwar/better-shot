import AVFoundation
import Foundation

nonisolated struct Clip: Identifiable, Equatable, Sendable {
    static let minimumDuration: TimeInterval = 0.2
    static let minimumSpeed: Double = 0.25
    static let maximumSpeed: Double = 4.0

    var id: UUID
    var sourceStart: TimeInterval
    var sourceEnd: TimeInterval
    var speed: Double

    init(id: UUID = UUID(), sourceStart: TimeInterval, sourceEnd: TimeInterval, speed: Double = 1) {
        self.id = id
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
    }

    var duration: TimeInterval { max(0, sourceEnd - sourceStart) }
    var editorDuration: TimeInterval { duration / min(max(speed, Self.minimumSpeed), Self.maximumSpeed) }
}

nonisolated struct ClipTimeline: Equatable, Sendable {
    var clips: [Clip]

    init(clips: [Clip]) { self.clips = clips }

    static func full(sourceDuration: TimeInterval) -> ClipTimeline {
        let safe = max(0, sourceDuration.isFinite ? sourceDuration : 0)
        guard safe > 0 else { return ClipTimeline(clips: []) }
        return ClipTimeline(clips: [Clip(sourceStart: 0, sourceEnd: safe)])
    }

    var duration: TimeInterval { clips.reduce(0) { $0 + $1.editorDuration } }

    func normalized(to sourceDuration: TimeInterval) -> [Clip] {
        let safe = max(0, sourceDuration.isFinite ? sourceDuration : 0)
        var seenIDs = Set<UUID>()
        return clips
            .compactMap { clip -> Clip? in
                let start = min(max(clip.sourceStart, 0), safe)
                let end = min(max(clip.sourceEnd, start), safe)
                guard end - start >= Clip.minimumDuration else { return nil }
                let id = seenIDs.insert(clip.id).inserted ? clip.id : UUID()
                let speed = min(max(clip.speed.isFinite ? clip.speed : 1, Clip.minimumSpeed), Clip.maximumSpeed)
                return Clip(id: id, sourceStart: start, sourceEnd: end, speed: speed)
            }
            .sorted { $0.sourceStart < $1.sourceStart }
    }

    func clipIndex(at sourceTime: TimeInterval) -> Int? {
        guard !clips.isEmpty else { return nil }
        if let index = clips.firstIndex(where: { $0.sourceStart <= sourceTime && sourceTime < $0.sourceEnd }) {
            return index
        }
        return sourceTime <= clips[0].sourceStart ? 0 : clips.count - 1
    }

    func editorRange(for id: UUID) -> Range<TimeInterval>? {
        var editorStart: TimeInterval = 0
        for clip in clips {
            let editorEnd = editorStart + clip.editorDuration
            if clip.id == id { return editorStart..<editorEnd }
            editorStart = editorEnd
        }
        return nil
    }

    func split(at sourceTime: TimeInterval) -> (clips: [Clip], selectedID: UUID)? {
        guard let index = clipIndex(at: sourceTime) else { return nil }
        let clip = clips[index]
        guard sourceTime - clip.sourceStart >= Clip.minimumDuration,
              clip.sourceEnd - sourceTime >= Clip.minimumDuration else { return nil }
        let trailingID = UUID()
        let leading = Clip(id: clip.id, sourceStart: clip.sourceStart, sourceEnd: sourceTime, speed: clip.speed)
        let trailing = Clip(id: trailingID, sourceStart: sourceTime, sourceEnd: clip.sourceEnd, speed: clip.speed)
        var next = clips
        next.replaceSubrange(index...index, with: [leading, trailing])
        return (next, trailingID)
    }

    func deleting(id: UUID) -> [Clip]? {
        guard clips.count > 1, clips.contains(where: { $0.id == id }) else { return nil }
        return clips.filter { $0.id != id }
    }

    func replacing(_ replacement: Clip) -> [Clip] {
        guard let index = clips.firstIndex(where: { $0.id == replacement.id }) else { return clips }
        var next = clips
        next[index] = replacement
        return next
    }

    func editorTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval? {
        var editorStart: TimeInterval = 0
        for clip in clips {
            if sourceTime >= clip.sourceStart - 0.000_001, sourceTime <= clip.sourceEnd + 0.000_001 {
                let offset = min(max(sourceTime - clip.sourceStart, 0), clip.duration)
                return editorStart + offset / min(max(clip.speed, Clip.minimumSpeed), Clip.maximumSpeed)
            }
            editorStart += clip.editorDuration
        }
        return nil
    }

    /// A deleted stretch has no place on the editor axis, so a source time inside one lands on the cut it left behind.
    func clampedEditorTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval {
        var editorStart: TimeInterval = 0
        for clip in clips {
            if sourceTime < clip.sourceStart { return editorStart }
            if sourceTime <= clip.sourceEnd {
                let speed = min(max(clip.speed, Clip.minimumSpeed), Clip.maximumSpeed)
                return editorStart + (sourceTime - clip.sourceStart) / speed
            }
            editorStart += clip.editorDuration
        }
        return editorStart
    }

    /// Preview plays the untouched asset, so a playhead that wanders into a deleted stretch has to be pushed to the next clip.
    func playbackTime(after sourceTime: TimeInterval) -> TimeInterval? {
        guard !clips.isEmpty else { return nil }
        guard !clips.contains(where: { $0.sourceStart <= sourceTime && sourceTime < $0.sourceEnd }) else { return nil }
        return clips.first { $0.sourceStart > sourceTime }?.sourceStart
    }

    func sourceTime(at editorTime: TimeInterval) -> TimeInterval {
        guard !clips.isEmpty, duration > 0 else { return 0 }
        let clamped = min(max(editorTime, 0), duration)
        var editorStart: TimeInterval = 0
        for (index, clip) in clips.enumerated() {
            let editorEnd = editorStart + clip.editorDuration
            if clamped < editorEnd || index == clips.count - 1 {
                let offset = min(max(clamped - editorStart, 0), clip.editorDuration)
                let speed = min(max(clip.speed, Clip.minimumSpeed), Clip.maximumSpeed)
                return min(clip.sourceStart + offset * speed, clip.sourceEnd)
            }
            editorStart = editorEnd
        }
        return 0
    }
}

nonisolated enum ClipCompositionBuilder {
    struct Built {
        let composition: AVMutableComposition
        let cameraTrackID: CMPersistentTrackID?
    }

    static func makeComposition(
        videoTrack: AVAssetTrack,
        audioTracks: [AVAssetTrack],
        camera: CameraSource?,
        clips: [Clip]
    ) throws -> Built {
        let composition = AVMutableComposition()

        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return Built(composition: composition, cameraTrackID: nil)
        }
        // Added before any `scaleTimeRange`, so a clip's speed change stretches the face cam by exactly as much as the screen.
        let compCameraTrack = camera.flatMap { _ in
            composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        let compAudioTracks = audioTracks.compactMap { source -> (AVAssetTrack, AVMutableCompositionTrack)? in
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            return (source, track)
        }

        var insertionTime = CMTime.zero
        for clip in clips {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            try compVideoTrack.insertTimeRange(range, of: videoTrack, at: insertionTime)
            for (source, compAudioTrack) in compAudioTracks {
                try? compAudioTrack.insertTimeRange(range, of: source, at: insertionTime)
            }
            if let camera, let compCameraTrack {
                insertCamera(camera, into: compCameraTrack, sourceRange: range, at: insertionTime)
            }

            if abs(clip.speed - 1) > 0.000_001 {
                let insertedRange = CMTimeRange(start: insertionTime, duration: range.duration)
                let scaledDuration = CMTime(seconds: clip.editorDuration, preferredTimescale: 600)
                composition.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                insertionTime = insertionTime + scaledDuration
            } else {
                insertionTime = insertionTime + range.duration
            }
        }
        return Built(composition: composition, cameraTrackID: compCameraTrack?.trackID)
    }

    /// The face cam file can end before the screen recording does, so whatever it cannot cover becomes empty timeline rather than a length mismatch.
    static func insertCamera(
        _ camera: CameraSource,
        into compCameraTrack: AVMutableCompositionTrack,
        sourceRange: CMTimeRange,
        at insertionTime: CMTime
    ) {
        let remaining = CMTimeMaximum(CMTimeSubtract(camera.duration, sourceRange.start), .zero)
        let usable = CMTimeMinimum(sourceRange.duration, remaining)
        if usable > .zero {
            try? compCameraTrack.insertTimeRange(
                CMTimeRange(start: sourceRange.start, duration: usable),
                of: camera.track,
                at: insertionTime
            )
        }
        let padding = CMTimeSubtract(sourceRange.duration, usable)
        if padding > .zero {
            compCameraTrack.insertEmptyTimeRange(CMTimeRange(start: CMTimeAdd(insertionTime, usable), duration: padding))
        }
    }
}

nonisolated struct CameraSource {
    let track: AVAssetTrack
    let duration: CMTime
}
