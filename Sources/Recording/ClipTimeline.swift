import AVFoundation
import CoreGraphics
import Foundation

/// What a speed change does to the clip's audio: drop it, resample it at pitch, or let it chipmunk the way tape does.
nonisolated enum ClipSpeedAudioMode: String, CaseIterable, Identifiable, Sendable {
    case mute
    case maintainPitch
    case matchSpeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mute: "Mute"
        case .maintainPitch: "Keep Pitch"
        case .matchSpeed: "Match Speed"
        }
    }

    var icon: String {
        switch self {
        case .mute: "speaker.slash"
        case .maintainPitch: "waveform"
        case .matchSpeed: "waveform.badge.plus"
        }
    }

    var pitchAlgorithm: AVAudioTimePitchAlgorithm {
        self == .matchSpeed ? .varispeed : .spectral
    }
}

/// How one clip hands over to the next: dissolve straight through, or dip to black in between.
nonisolated enum ClipTransitionKind: String, CaseIterable, Identifiable, Sendable {
    case crossFade
    case fadeThroughBlack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crossFade: "Crossfade"
        case .fadeThroughBlack: "Fade"
        }
    }

    var icon: String {
        switch self {
        case .crossFade: "square.on.square.intersection.dashed"
        case .fadeThroughBlack: "circle.lefthalf.filled"
        }
    }
}

nonisolated struct ClipTransition: Equatable, Sendable {
    static let minimumDuration: TimeInterval = 0.05
    static let defaultDuration: TimeInterval = 0.5

    var kind: ClipTransitionKind
    var duration: TimeInterval

    init(kind: ClipTransitionKind = .crossFade, duration: TimeInterval = ClipTransition.defaultDuration) {
        self.kind = kind
        self.duration = duration
    }
}

/// Which of the two recorded feeds the frame shows, and how they share the card.
nonisolated enum SceneMode: String, CaseIterable, Identifiable, Sendable {
    case screenAndCamera
    case screenOnly
    case cameraOnly
    case splitScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenAndCamera: "Both"
        case .screenOnly: "Screen"
        case .cameraOnly: "Camera"
        case .splitScreen: "Split"
        }
    }

    var icon: String {
        switch self {
        case .screenAndCamera: "person.crop.circle.badge.checkmark"
        case .screenOnly: "display"
        case .cameraOnly: "person.crop.square"
        case .splitScreen: "rectangle.split.2x1"
        }
    }

    var needsCamera: Bool { self != .screenOnly }

    /// The gap between split panes, as a share of the card's short edge, so the two halves read as two cards instead of one seam.
    static let splitGapFraction: CGFloat = 0.015

    /// The screen always takes the leading pane, so `flipped` says whether the axis points up the way CoreImage draws or down the way SwiftUI lays out.
    func layout(card: CGRect, bubble: CGRect, flipped: Bool = false) -> SceneLayout {
        switch self {
        case .screenAndCamera:
            return SceneLayout(screen: card, camera: bubble, cameraIsCircle: true)
        case .screenOnly:
            return SceneLayout(screen: card, camera: nil, cameraIsCircle: false)
        case .cameraOnly:
            return SceneLayout(screen: nil, camera: card, cameraIsCircle: false)
        case .splitScreen:
            let gap = min(card.width, card.height) * Self.splitGapFraction
            if card.width >= card.height {
                let width = (card.width - gap) / 2
                return SceneLayout(
                    screen: CGRect(x: card.minX, y: card.minY, width: width, height: card.height),
                    camera: CGRect(x: card.maxX - width, y: card.minY, width: width, height: card.height),
                    cameraIsCircle: false
                )
            }
            let height = (card.height - gap) / 2
            let low = CGRect(x: card.minX, y: card.minY, width: card.width, height: height)
            let high = CGRect(x: card.minX, y: card.maxY - height, width: card.width, height: height)
            return flipped
                ? SceneLayout(screen: high, camera: low, cameraIsCircle: false)
                : SceneLayout(screen: low, camera: high, cameraIsCircle: false)
        }
    }
}

nonisolated struct SceneLayout: Equatable, Sendable {
    var screen: CGRect?
    var camera: CGRect?
    var cameraIsCircle: Bool
}

nonisolated struct Clip: Identifiable, Equatable, Sendable {
    static let minimumDuration: TimeInterval = 0.2
    static let minimumSpeed: Double = 0.25
    static let maximumSpeed: Double = 4.0

    var id: UUID
    var sourceStart: TimeInterval
    var sourceEnd: TimeInterval
    var speed: Double
    var audioMode: ClipSpeedAudioMode
    /// The handover from the previous clip, ignored on the first clip because nothing precedes it.
    var transitionIn: ClipTransition?
    var scene: SceneMode

    init(
        id: UUID = UUID(),
        sourceStart: TimeInterval,
        sourceEnd: TimeInterval,
        speed: Double = 1,
        audioMode: ClipSpeedAudioMode = .maintainPitch,
        transitionIn: ClipTransition? = nil,
        scene: SceneMode = .screenAndCamera
    ) {
        self.id = id
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.speed = speed
        self.audioMode = audioMode
        self.transitionIn = transitionIn
        self.scene = scene
    }

    static func clampedSpeed(_ speed: Double) -> Double {
        min(max(speed.isFinite ? speed : 1, minimumSpeed), maximumSpeed)
    }

    var duration: TimeInterval { max(0, sourceEnd - sourceStart) }
    var editorDuration: TimeInterval { duration / Self.clampedSpeed(speed) }
}

nonisolated struct ClipTimeline: Equatable, Sendable {
    var clips: [Clip]

    init(clips: [Clip]) { self.clips = clips }

    static func full(sourceDuration: TimeInterval) -> ClipTimeline {
        let safe = max(0, sourceDuration.isFinite ? sourceDuration : 0)
        guard safe > 0 else { return ClipTimeline(clips: []) }
        return ClipTimeline(clips: [Clip(sourceStart: 0, sourceEnd: safe)])
    }

    var duration: TimeInterval {
        clips.reduce(0) { $0 + $1.editorDuration } - (0..<clips.count).reduce(0) { $0 + (effectiveTransition(at: $1)?.duration ?? 0) }
    }

    /// A transition eats the tail of one clip and the head of the next, so it can never take more than half of the shorter of the two.
    func maximumTransitionDuration(at index: Int) -> TimeInterval {
        guard index > 0, index < clips.count else { return 0 }
        let maximum = min(clips[index - 1].editorDuration, clips[index].editorDuration) / 2
        return maximum.isFinite ? maximum : 0
    }

    func effectiveTransition(at index: Int) -> ClipTransition? {
        guard index > 0, index < clips.count, var transition = clips[index].transitionIn else { return nil }
        guard transition.duration.isFinite, transition.duration > 0 else { return nil }
        let maximum = maximumTransitionDuration(at: index)
        guard maximum >= ClipTransition.minimumDuration else { return nil }
        transition.duration = min(max(transition.duration, ClipTransition.minimumDuration), maximum)
        return transition
    }

    var hasTransitions: Bool { (0..<clips.count).contains { effectiveTransition(at: $0) != nil } }

    /// Where each clip lands on the editor axis once the overlaps are taken out.
    var outputStarts: [TimeInterval] {
        var starts: [TimeInterval] = []
        var cursor: TimeInterval = 0
        for (index, clip) in clips.enumerated() {
            cursor -= effectiveTransition(at: index)?.duration ?? 0
            starts.append(cursor)
            cursor += clip.editorDuration
        }
        return starts
    }

    /// During an overlap two clips share the axis, and the incoming one wins, matching what the export shows.
    func clipIndex(atEditorTime editorTime: TimeInterval) -> Int? {
        let starts = outputStarts
        return starts.lastIndex { editorTime >= $0 } ?? (clips.isEmpty ? nil : 0)
    }

    func clip(atSourceTime time: TimeInterval) -> Clip? {
        clips.first { time >= $0.sourceStart && time < $0.sourceEnd }
    }

    func speed(atSourceTime time: TimeInterval) -> Double {
        guard let clip = clip(atSourceTime: time) else { return 1 }
        return Clip.clampedSpeed(clip.speed)
    }

    func audioMode(atSourceTime time: TimeInterval) -> ClipSpeedAudioMode {
        clip(atSourceTime: time)?.audioMode ?? .maintainPitch
    }

    func scene(atSourceTime time: TimeInterval) -> SceneMode {
        clip(atSourceTime: time)?.scene ?? .screenAndCamera
    }

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
                return Clip(
                    id: id,
                    sourceStart: start,
                    sourceEnd: end,
                    speed: speed,
                    audioMode: clip.audioMode,
                    transitionIn: clip.transitionIn,
                    scene: clip.scene
                )
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
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let start = outputStarts[index]
        return start..<(start + clips[index].editorDuration)
    }

    func split(at sourceTime: TimeInterval) -> (clips: [Clip], selectedID: UUID)? {
        guard let index = clipIndex(at: sourceTime) else { return nil }
        let clip = clips[index]
        guard sourceTime - clip.sourceStart >= Clip.minimumDuration,
              clip.sourceEnd - sourceTime >= Clip.minimumDuration else { return nil }
        let trailingID = UUID()
        let leading = Clip(
            id: clip.id,
            sourceStart: clip.sourceStart,
            sourceEnd: sourceTime,
            speed: clip.speed,
            audioMode: clip.audioMode,
            transitionIn: clip.transitionIn,
            scene: clip.scene
        )
        let trailing = Clip(
            id: trailingID,
            sourceStart: sourceTime,
            sourceEnd: clip.sourceEnd,
            speed: clip.speed,
            audioMode: clip.audioMode,
            scene: clip.scene
        )
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
        let starts = outputStarts
        for (index, clip) in clips.enumerated() {
            if sourceTime >= clip.sourceStart - 0.000_001, sourceTime <= clip.sourceEnd + 0.000_001 {
                let offset = min(max(sourceTime - clip.sourceStart, 0), clip.duration)
                return starts[index] + offset / Clip.clampedSpeed(clip.speed)
            }
        }
        return nil
    }

    /// A deleted stretch has no place on the editor axis, so a source time inside one lands on the cut it left behind.
    func clampedEditorTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval {
        let starts = outputStarts
        for (index, clip) in clips.enumerated() {
            if sourceTime < clip.sourceStart { return starts[index] }
            if sourceTime <= clip.sourceEnd {
                return starts[index] + (sourceTime - clip.sourceStart) / Clip.clampedSpeed(clip.speed)
            }
        }
        return duration
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
        guard let index = clipIndex(atEditorTime: clamped) else { return 0 }
        let clip = clips[index]
        let offset = min(max(clamped - outputStarts[index], 0), clip.editorDuration)
        return min(clip.sourceStart + offset * Clip.clampedSpeed(clip.speed), clip.sourceEnd)
    }
}

nonisolated enum ClipCompositionBuilder {
    struct Built {
        let composition: AVMutableComposition
        let videoTrackIDs: [CMPersistentTrackID]
        let cameraTrackID: CMPersistentTrackID?
        let audioMix: AVAudioMix?
    }

    private struct AudioLane {
        let source: AVAssetTrack
        let track: AVMutableCompositionTrack
        let mode: ClipSpeedAudioMode
    }

    private static let timescale: CMTimeScale = 600

    static func makeComposition(
        videoTrack: AVAssetTrack,
        audioTracks: [AVAssetTrack],
        camera: CameraSource?,
        clips: [Clip]
    ) throws -> Built {
        let composition = AVMutableComposition()
        let timeline = ClipTimeline(clips: clips)
        let starts = timeline.outputStarts
        let laneCount = timeline.hasTransitions ? 2 : 1
        let pitchModes = Set(clips.map(\.audioMode)).subtracting([.mute]).sorted { $0.rawValue < $1.rawValue }

        var videoLanes: [AVMutableCompositionTrack] = []
        var audioLanes: [[AudioLane]] = []
        for _ in 0..<laneCount {
            guard let lane = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return Built(composition: composition, videoTrackIDs: [], cameraTrackID: nil, audioMix: nil)
            }
            videoLanes.append(lane)
            audioLanes.append(pitchModes.flatMap { mode in
                audioTracks.compactMap { source in
                    composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                        .map { AudioLane(source: source, track: $0, mode: mode) }
                }
            })
        }
        let compCameraTrack = camera.flatMap { _ in
            composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        for (index, clip) in clips.enumerated() {
            let lane = index % laneCount
            let outputStart = CMTime(seconds: starts[index], preferredTimescale: timescale)
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: clip.sourceStart, preferredTimescale: timescale),
                duration: CMTime(seconds: clip.duration, preferredTimescale: timescale)
            )
            let editorDuration = CMTime(seconds: clip.editorDuration, preferredTimescale: timescale)

            try videoLanes[lane].insertTimeRange(sourceRange, of: videoTrack, at: outputStart)
            scale(videoLanes[lane], from: outputStart, sourceDuration: sourceRange.duration, to: editorDuration)

            for entry in audioLanes[lane] where entry.mode == clip.audioMode {
                try? entry.track.insertTimeRange(sourceRange, of: entry.source, at: outputStart)
                scale(entry.track, from: outputStart, sourceDuration: sourceRange.duration, to: editorDuration)
            }

            if let camera, let compCameraTrack {
                let handover = timeline.effectiveTransition(at: index)?.duration ?? 0
                let skipped = CMTime(seconds: handover * Clip.clampedSpeed(clip.speed), preferredTimescale: timescale)
                let cameraRange = CMTimeRange(
                    start: CMTimeAdd(sourceRange.start, skipped),
                    duration: CMTimeSubtract(sourceRange.duration, skipped)
                )
                let cameraStart = CMTimeAdd(outputStart, CMTime(seconds: handover, preferredTimescale: timescale))
                insertCamera(camera, into: compCameraTrack, sourceRange: cameraRange, at: cameraStart)
                scale(
                    compCameraTrack,
                    from: cameraStart,
                    sourceDuration: cameraRange.duration,
                    to: CMTimeSubtract(editorDuration, CMTime(seconds: handover, preferredTimescale: timescale))
                )
            }
        }

        let parameters = audioMixParameters(timeline: timeline, starts: starts, laneCount: laneCount, audioLanes: audioLanes)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return Built(
            composition: composition,
            videoTrackIDs: videoLanes.map(\.trackID),
            cameraTrackID: compCameraTrack?.trackID,
            audioMix: parameters.isEmpty ? nil : audioMix
        )
    }

    private static func scale(
        _ track: AVMutableCompositionTrack,
        from start: CMTime,
        sourceDuration: CMTime,
        to target: CMTime
    ) {
        guard sourceDuration > .zero, target > .zero, target != sourceDuration else { return }
        track.scaleTimeRange(CMTimeRange(start: start, duration: sourceDuration), toDuration: target)
    }

    /// The pitch algorithm is a per-track property, so each algorithm in use gets its own lane and the handover gains ride on the same parameters.
    private static func audioMixParameters(
        timeline: ClipTimeline,
        starts: [TimeInterval],
        laneCount: Int,
        audioLanes: [[AudioLane]]
    ) -> [AVAudioMixInputParameters] {
        var parameters: [AVMutableCompositionTrack: AVMutableAudioMixInputParameters] = [:]
        for lane in audioLanes {
            for entry in lane {
                let input = AVMutableAudioMixInputParameters(track: entry.track)
                input.audioTimePitchAlgorithm = entry.mode.pitchAlgorithm
                parameters[entry.track] = input
            }
        }

        for (index, clip) in timeline.clips.enumerated() {
            let incoming = audioLanes[index % laneCount].filter { $0.mode == clip.audioMode }
            guard let transition = timeline.effectiveTransition(at: index) else {
                let start = CMTime(seconds: starts[index], preferredTimescale: timescale)
                incoming.forEach { parameters[$0.track]?.setVolume(1, at: start) }
                continue
            }
            let start = CMTime(seconds: starts[index], preferredTimescale: timescale)
            let middle = CMTime(seconds: starts[index] + transition.duration / 2, preferredTimescale: timescale)
            let end = CMTime(seconds: starts[index] + transition.duration, preferredTimescale: timescale)
            let outgoing = audioLanes[(index - 1) % laneCount].filter { $0.mode == timeline.clips[index - 1].audioMode }

            switch transition.kind {
            case .crossFade:
                outgoing.forEach {
                    parameters[$0.track]?.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: start, end: end))
                }
                incoming.forEach {
                    parameters[$0.track]?.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: start, end: end))
                }
            case .fadeThroughBlack:
                outgoing.forEach {
                    parameters[$0.track]?.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: start, end: middle))
                }
                incoming.forEach {
                    parameters[$0.track]?.setVolume(0, at: start)
                    parameters[$0.track]?.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: middle, end: end))
                }
            }
        }
        return Array(parameters.values)
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
