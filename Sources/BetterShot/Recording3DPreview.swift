import AVFoundation
import CoreImage
import MetalKit
import SwiftUI

/// Uses the production GPU compositor when a project has 3D shots. The player
/// supplies decoded frames; no bitmap snapshots, CPU video copies, or extra decoder.
struct Recording3DPreview: NSViewRepresentable {
    let model: RecordingStudioModel
    let time: Double
    let revision: UInt
    let timeline: Recording3DTimeline

    func makeNSView(context: Context) -> Recording3DMetalView { Recording3DMetalView(model: model) }
    func updateNSView(_ view: Recording3DMetalView, context: Context) {
        view.update(time: time, revision: revision, timeline: timeline)
    }
    static func dismantleNSView(_ view: Recording3DMetalView, coordinator: ()) { view.detach() }
}

@MainActor
final class Recording3DMetalView: MTKView, MTKViewDelegate, AVPlayerItemOutputPullDelegate {
    private weak var model: RecordingStudioModel?
    private var screenItem: AVPlayerItem?
    private var cameraItem: AVPlayerItem?
    private let screenOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ])
    private let cameraOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ])
    private var screenFrame: CVPixelBuffer?
    private var cameraFrame: CVPixelBuffer?
    private var compositor: StudioFrameCompositor?
    private var queue: MTLCommandQueue?
    private var imageContext: CIContext?
    private var renderedRevision: UInt?
    private var renderedSize = CGSize.zero
    private var timeline = Recording3DTimeline.empty
    private var time: Double = 0
    private var revision: UInt = 0
    private var contentRevision: UInt = 0
    private var framesInFlight = 0
    private var failedRevision: UInt?
    private(set) var renderedFrameCount = 0
    private(set) var compositorBuildCount = 0
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(model: RecordingStudioModel) {
        self.model = model
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        enableSetNeedsDisplay = true
        isPaused = true
        autoResizeDrawable = true
        delegate = self
        queue = device?.makeCommandQueue()
        if let device { imageContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        screenOutput.setDelegate(self, queue: .main)
        cameraOutput.setDelegate(self, queue: .main)
        setAccessibilityLabel("Video preview")
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(time: Double, revision: UInt, timeline: Recording3DTimeline) {
        if self.revision != revision || self.timeline != timeline { contentRevision &+= 1 }
        self.time = time; self.revision = revision
        self.timeline = timeline
        guard let model else { return }
        if screenItem !== model.screenPlayer.currentItem {
            if let screenItem { screenItem.remove(screenOutput) }
            screenItem = model.screenPlayer.currentItem
            screenItem?.add(screenOutput)
            screenFrame = nil
        }
        if cameraItem !== model.cameraPlayer.currentItem {
            if let cameraItem { cameraItem.remove(cameraOutput) }
            cameraItem = model.cameraPlayer.currentItem
            cameraItem?.add(cameraOutput)
            cameraFrame = nil
        }
        needsDisplay = true
        screenOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
        cameraOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
    }

    func detach() {
        screenOutput.setDelegate(nil, queue: nil); cameraOutput.setDelegate(nil, queue: nil)
        screenItem?.remove(screenOutput); cameraItem?.remove(cameraOutput)
        screenItem = nil; cameraItem = nil
        screenFrame = nil; cameraFrame = nil; compositor = nil
        delegate = nil
    }

    nonisolated func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        Task { @MainActor [weak self] in self?.needsDisplay = true }
    }
    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    nonisolated func draw(in view: MTKView) { MainActor.assumeIsolated { renderFrame() } }

    private func renderFrame() {
        guard framesInFlight < 2, failedRevision != contentRevision, let model, drawableSize.width > 0, drawableSize.height > 0 else { return }
        guard let queue, let imageContext else { report(Recording3DBlurRenderer.Failure.unavailable); return }
        if let frame = screenOutput.copyPixelBuffer(forItemTime: model.screenPlayer.currentTime(), itemTimeForDisplay: nil) {
            screenFrame = frame
        }
        if let frame = cameraOutput.copyPixelBuffer(forItemTime: model.cameraPlayer.currentTime(), itemTimeForDisplay: nil) {
            cameraFrame = frame
        }
        guard let screenFrame else {
            screenOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.03)
            return
        }
        let size = CGSize(width: max(1, drawableSize.width.rounded()), height: max(1, drawableSize.height.rounded()))
        if compositor == nil || renderedRevision != revision || renderedSize != size {
            compositor = model.make3DPreviewCompositor(canvasSize: size)
            compositorBuildCount += 1
            renderedRevision = revision; renderedSize = size
        }
        guard let compositor, let drawable = currentDrawable, let command = queue.makeCommandBuffer() else { return }
        do {
            compositor.update3DTimeline(timeline)
            let image = try compositor.composedImage(screenFrame: screenFrame, cameraFrame: cameraFrame,
                editorTime: time, sourceTime: model.clipTimeline.sourceTime(at: time))
            imageContext.render(image, to: drawable.texture, commandBuffer: command,
                                bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
            command.present(drawable)
            framesInFlight += 1
            let submittedRevision = contentRevision
            let submittedTime = time
            command.addCompletedHandler { [weak self] buffer in
                withExtendedLifetime(image) { }
                let failure = buffer.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.framesInFlight -= 1
                    // A paused edit/seek can arrive while both drawable slots are busy.
                    if self.contentRevision != submittedRevision || self.time != submittedTime {
                        self.needsDisplay = true
                    }
                    if let failure {
                        if self.contentRevision == submittedRevision {
                            self.failedRevision = submittedRevision
                            self.model?.preview3DError = failure
                        }
                    } else {
                        self.renderedFrameCount += 1
                        if self.contentRevision == submittedRevision { self.model?.preview3DError = nil }
                    }
                }
            }
            command.commit()
        } catch { failedRevision = contentRevision; report(error) }
    }

    private func report(_ error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak model] in
            if model?.preview3DError != message { model?.preview3DError = message }
        }
    }
}
