import AppKit
import AVFoundation
import CoreImage
import Foundation

@testable import BetterShot

@MainActor
func checkRecordingMultiSourceCompositing(movieURL: URL) async throws {
    precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bettershotrec")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let project = RecordingSession(directoryURL: directory)
    let first = RecordingProjectSource(displayName: "Wide with camera", duration: 1)
    let second = RecordingProjectSource(displayName: "Square without camera", duration: 1)
    for source in [first, second] {
        let session = RecordingSession(directoryURL: source.sessionDirectory(in: directory))
        try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
        if source.id == first.id {
            try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        } else {
            let raw = AVURLAsset(url: movieURL)
            let track = try await raw.loadTracks(withMediaType: .video).first!
            let natural = try await track.load(.naturalSize)
            let rotated = AVMutableComposition()
            let video = rotated.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try video.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)),
                                      of: track, at: .zero)
            video.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: natural.height, ty: 0)
            let export = AVAssetExportSession(asset: rotated, presetName: AVAssetExportPresetPassthrough)!
            export.outputURL = session.screenURL
            export.outputFileType = .mov
            await withCheckedContinuation { continuation in
                export.exportAsynchronously { continuation.resume() }
            }
            precondition(export.status == .completed, "The rotated source fixture must be readable")
        }
        if source.id == first.id {
            try FileManager.default.copyItem(at: movieURL, to: session.cameraURL)
        }
        var style = RecordingStudioStyle()
        style.background = .solid(source.id == first.id ? .red : .green)
        style.padding = 0.15
        style.shadow = 0
        let timeline = RecordingClipTimeline(segments: [RecordingClipSegment(sourceStart: 1, sourceEnd: 3, speed: 2)])
        var document = RecordingEditDocument(style: style, zoomEnabled: false, zoomCues: [], clipTimeline: timeline)
        document.exportAspect = (source.id == second.id ? ExportAspectPreset.square : .wide16x9).rawValue
        if source.id == first.id {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 31_200)!
            tone.frameLength = 31_200
            for index in 0..<31_200 {
                tone.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 220 / 48_000) * 0.3)
            }
            let audioURL = session.directoryURL.appendingPathComponent("replacement.caf")
            try AVAudioFile(forWriting: audioURL, settings: format.settings).write(from: tone)
            document.replacementAudioFileName = audioURL.lastPathComponent
        } else {
            var silent = VideoCompressionSettings()
            silent.removeAudio = true
            document.exportSettings = silent
        }
        try session.writeEditDocument(document)
    }
    let sources = try await RecordingStudioSourceResolver.configurations(for: [first, second], in: project)
    let timeline = RecordingClipTimeline(segments: [
        RecordingClipSegment(sourceID: first.id, sourceStart: 0, sourceEnd: 1),
        RecordingClipSegment(sourceID: second.id, sourceStart: 0, sourceEnd: 1),
        RecordingClipSegment(sourceID: first.id, sourceStart: 0.5, sourceEnd: 1, speed: 2),
        RecordingClipSegment(sourceID: first.id, sourceStart: 0, sourceEnd: 0.5, speed: 0.5)
    ])
    let base = sources[0].configuration
    var settings = VideoCompressionSettings()
    settings.frameRate = .fps30
    let configuration = RecordingStudioExporter.Configuration(
        screenURL: base.screenURL, cameraURL: nil, cameraOffset: 0,
        style: base.style, viewportTimeline: base.viewportTimeline, pointerTimeline: nil,
        showsPressEffects: false, keystrokeTimeline: nil, keystrokePlacement: .bottomCenter,
        subtitleTimeline: nil, subtitleStyle: SubtitleBarStyle(), canvasSize: CGSize(width: 320, height: 180),
        clipTimeline: timeline, exportSettings: settings, sources: sources)
    let prepared = try await RecordingCompositionBuilder.prepareSources(sources)
    let composed = try RecordingCompositionBuilder.makeAsset(sources: prepared, timeline: timeline)
    let composedDuration = try await composed.load(.duration).seconds
    precondition(abs(composedDuration - timeline.duration) < 0.01, "Nested and outer speed must compound")

    let renderer = try await RecordingStudioMultiSourceRenderer(configuration: configuration, canvasSize: configuration.canvasSize)
    let context = CIContext(options: [.cacheIntermediates: false])
    func pixels(_ image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 320 * 180 * 4)
        context.render(image, toBitmap: &bytes, rowBytes: 320 * 4,
            bounds: CGRect(x: 0, y: 0, width: 320, height: 180), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return bytes
    }
    let previewWorker = RecordingMultiSourcePreviewWorker()
    for time in [0.2, 1.2, 2.1, 0.2] {
        let previewImage = try await previewWorker.image(configuration: configuration,
            size: configuration.canvasSize, revision: 0, time: time)
        let expectedImage = try renderer.composedImage(at: time)
        let expected = pixels(expectedImage)
        let actual = pixels(previewImage)
        let errors = zip(actual, expected).map { abs(Int($0) - Int($1)) }
        let maximumError = errors.max() ?? 0
        let meanError = Double(errors.reduce(0, +)) / Double(errors.count * 255)
        // Independent Core Image contexts may round rotated NV12→BGRA conversion by one 8-bit level.
        let matches = maximumError <= 1 && meanError < 0.00001
        if !matches {
            print("WORKER parity time=\(time), components=\(errors.filter { $0 != 0 }.count), max=\(maximumError), normalizedMean=\(meanError)")
            print("WORKER location \(RecordingStudioSourceResolver.location(at: time, timeline: timeline, sources: sources)!)")
            let snapshots = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/editor-snapshots")
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            for (name, image) in [("actual", previewImage), ("expected", expectedImage)] {
                let raster = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: 320, height: 180))!
                try NSBitmapImageRep(cgImage: raster).representation(using: .png, properties: [:])!
                    .write(to: snapshots.appendingPathComponent("multi-source-worker-\(name).png"))
            }
        }
        precondition(matches,
                     "Native preview worker must match the shared compositor within bounded 8-bit conversion rounding")
    }
    let beforeSwitch = pixels(try renderer.composedImage(at: 0.2))
    _ = try renderer.composedImage(at: 1.2)
    _ = try renderer.composedImage(at: 2.1)
    let replay = pixels(try renderer.composedImage(at: 0.2))
    precondition(beforeSwitch == replay, "Backward source playback must reset screen and camera decoding")
    let firstPNG = try await RecordingStudioExporter.previewPNG(configuration: configuration, editorTime: 0.2)
    let squarePNG = try await RecordingStudioExporter.previewPNG(configuration: configuration, editorTime: 1.2)
    precondition(firstPNG.size == CGSize(width: 320, height: 180) && squarePNG.size == firstPNG.size)
    let wide = NSBitmapImageRep(data: firstPNG.data)!
    let square = NSBitmapImageRep(data: squarePNG.data)!
    let wideEdge = wide.colorAt(x: 2, y: 90)!.usingColorSpace(.sRGB)!
    let squareEdge = square.colorAt(x: 2, y: 90)!.usingColorSpace(.sRGB)!
    precondition(wideEdge.redComponent > 0.8 && wideEdge.greenComponent < 0.4,
                 "Composed preview must use the active leaf's authored background")
    precondition(max(squareEdge.redComponent, squareEdge.greenComponent, squareEdge.blueComponent) < 0.05,
                 "Different authored aspects must fit in the root canvas without stretching")
    let leafPNG = try await RecordingStudioExporter.previewPNG(configuration: sources[1].configuration,
                                                               editorTime: 0.2, maximumDimension: 180)
    let leafImage = CIImage(data: leafPNG.data)!
    let reference = leafImage.transformed(by: CGAffineTransform(translationX: 70, y: 0))
        .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180)))
    let expectedRotation = pixels(reference)
    let actualRotation = pixels(CIImage(data: squarePNG.data)!)
    let rotationError = zip(actualRotation, expectedRotation).enumerated().filter { $0.offset % 4 != 3 }
        .reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) } / Double(320 * 180 * 3 * 255)
    precondition(rotationError < 0.08,
                 "Raw transformed decoding must match the independently oriented native leaf preview")

    var rootDocument = RecordingEditDocument(style: base.style, zoomEnabled: false, zoomCues: [], clipTimeline: timeline)
    rootDocument.sources = [first, second]
    let root = try await RecordingSessionRenderer.configuration(for: project, document: rootDocument)
    precondition(root.sources.count == 2 && root.clipTimeline == timeline && root.canvasSize == base.canvasSize,
                 "Root session renders must retain ordered clips and the first authored canvas")
    var override = RecordingSession(directoryURL: first.sessionDirectory(in: directory)).loadEditDocument()!
    var overrideStyle = override.style.value
    overrideStyle.background = .solid(.blue)
    override.style = StoredRecordingStudioStyle(overrideStyle)
    rootDocument.sourceDocuments = [first.id: override]
    let overridden = try await RecordingSessionRenderer.configuration(for: project, document: rootDocument)
    precondition(overridden.sources[0].configuration.style.background == .solid(.blue),
                 "Transactional leaf snapshots must override the immutable authored edit document")

    let output = try await RecordingStudioExporter().export(configuration) { _ in }
    defer { try? FileManager.default.removeItem(at: output) }
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration).seconds
    precondition(abs(duration - timeline.duration) < 0.05,
                 "Encoded duration \(duration) must match ordered timeline \(timeline.duration)")
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    for time in [0.2, 1.2, 2.1, 2.8] {
        let encoded = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        let actual = pixels(CIImage(cgImage: encoded))
        let expected = pixels(try renderer.composedImage(at: time))
        let error = zip(actual, expected).enumerated().filter { $0.offset % 4 != 3 }
            .reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) } / Double(320 * 180 * 3 * 255)
        precondition(error < 0.08, "Encoded export must match composed preview across switches and repeated source times")
    }
    try await checkAudio(asset)
    for format in [RecordingAudioFormat.m4a, .m4a, .m4a, .m4a, .m4a, .wav] {
        let audioOnlyURL = try await RecordingAudioExporter().export(.init(screenURL: base.screenURL,
            clipTimeline: timeline, replacementURL: nil, format: format, sources: sources)) { _ in }
        defer { try? FileManager.default.removeItem(at: audioOnlyURL) }
        let audioOnlyAsset = AVURLAsset(url: audioOnlyURL)
        let audioOnlyDuration = try await audioOnlyAsset.load(.duration).seconds
        precondition(abs(audioOnlyDuration - timeline.duration) < 0.05,
                     "Audio-only \(format) duration \(audioOnlyDuration) must match ordered timeline \(timeline.duration)")
        try await checkAudio(audioOnlyAsset)
    }
    print("PASS composed multi-source preview/export, authored aspect/audio/snapshot, nested speed and backward/repeated screen/camera frames")
}

private func checkAudio(_ asset: AVAsset) async throws {
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    precondition(!audioTracks.isEmpty, "Authored replacement audio must reach encoded export")
    let audioReader = try AVAssetReader(asset: asset)
    let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false
    ])
    audioReader.add(audioOutput)
    precondition(audioReader.startReading())
    let probes = [0.2, 0.85, 1.2, 2.8]
    var energy = [Double](repeating: 0, count: probes.count)
    var counts = [Int](repeating: 0, count: probes.count)
    while let sample = audioOutput.copyNextSampleBuffer() {
        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        var bytes = Data(count: CMBlockBufferGetDataLength(block))
        let status = bytes.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        }
        precondition(status == kCMBlockBufferNoErr)
        let description = CMSampleBufferGetFormatDescription(sample)!
        let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)!.pointee
        let channels = Int(format.mChannelsPerFrame)
        bytes.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: Float.self)
            for frame in 0..<CMSampleBufferGetNumSamples(sample) {
                let sampleTime = time + Double(frame) / format.mSampleRate
                for index in probes.indices where abs(sampleTime - probes[index]) < 0.05 {
                    for channel in 0..<channels {
                        let value = values[frame * channels + channel]
                        energy[index] += Double(value * value)
                        counts[index] += 1
                    }
                }
            }
        }
    }
    precondition(audioReader.status == .completed)
    precondition(counts[0] > 0 && counts[3] > 0 && energy[0] / Double(counts[0]) > 0.01
                 && energy[3] / Double(counts[3]) > 0.01,
                 "Replacement sound must survive outer retiming and repeated source ranges")
    precondition(energy[1] / Double(max(1, counts[1])) < 0.0001
                 && energy[2] / Double(max(1, counts[2])) < 0.0001,
                 "Short replacement audio and silent leaves must leave silent tails")
}
