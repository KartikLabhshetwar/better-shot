import CoreImage
import MetalKit
import SwiftUI

struct RecordingMultiSourcePreview: NSViewRepresentable {
    let model: RecordingStudioModel
    let time: TimeInterval
    let revision: UInt

    func makeNSView(context: Context) -> RecordingMultiSourceMetalView {
        RecordingMultiSourceMetalView(model: model)
    }

    func updateNSView(_ view: RecordingMultiSourceMetalView, context: Context) {
        view.update(time: time, revision: revision)
    }

    static func dismantleNSView(_ view: RecordingMultiSourceMetalView, coordinator: ()) { view.detach() }
}

/// Readers and compositors have one serial owner, including across backward seeks.
actor RecordingMultiSourcePreviewWorker {
    private var renderer: RecordingStudioMultiSourceRenderer?
    private var revision: UInt?
    private var size = CGSize.zero

    func image(configuration: RecordingStudioExporter.Configuration, size: CGSize,
               revision: UInt, time: TimeInterval) async throws -> CIImage {
        if renderer == nil || self.revision != revision || self.size != size {
            renderer = try await RecordingStudioMultiSourceRenderer(configuration: configuration, canvasSize: size)
            self.revision = revision
            self.size = size
        }
        try Task.checkCancellation()
        return try renderer!.composedImage(at: time)
    }
}

@MainActor
final class RecordingMultiSourceMetalView: MTKView, MTKViewDelegate {
    private weak var model: RecordingStudioModel?
    private let worker = RecordingMultiSourcePreviewWorker()
    private var renderTask: Task<Void, Never>?
    private var queue: MTLCommandQueue?
    private var imageContext: CIContext?
    private var configuration: RecordingStudioExporter.Configuration?
    private var revision: UInt?
    private var failedRevision: UInt?
    private var time: TimeInterval = 0
    private var framesInFlight = 0
    private var detached = false
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private(set) var renderedFrameCount = 0

    init(model: RecordingStudioModel) {
        self.model = model
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        enableSetNeedsDisplay = true
        isPaused = true
        autoResizeDrawable = true
        delegate = self
        queue = device?.makeCommandQueue()
        if let device { imageContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false]) }
        setAccessibilityLabel("Video preview")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(time: TimeInterval, revision: UInt) {
        if self.revision != revision || configuration == nil {
            configuration = model?.makeExportConfiguration(preview: true)
            self.revision = revision
        }
        self.time = time
        needsDisplay = true
    }

    func detach() {
        detached = true
        renderTask?.cancel()
        renderTask = nil
        delegate = nil
        configuration = nil
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        Task { @MainActor [weak self] in self?.needsDisplay = true }
    }

    nonisolated func draw(in view: MTKView) { MainActor.assumeIsolated { renderFrame() } }

    private func renderFrame() {
        guard !detached, renderTask == nil, framesInFlight < 2,
              let revision, failedRevision != revision, let configuration,
              drawableSize.width > 0, drawableSize.height > 0 else { return }
        guard queue != nil, imageContext != nil else {
            report(Recording3DBlurRenderer.Failure.unavailable, revision: revision)
            return
        }
        let size = CGSize(width: max(1, drawableSize.width.rounded()), height: max(1, drawableSize.height.rounded()))
        let submittedTime = time
        renderTask = Task { [weak self, worker] in
            do {
                let image = try await worker.image(configuration: configuration, size: size,
                                                   revision: revision, time: submittedTime)
                guard !Task.isCancelled, let self, !self.detached else { return }
                self.renderTask = nil
                // Content edits supersede decoded frames; playback keeps the newest completed frame.
                if self.revision == revision, self.drawableSize == size {
                    self.present(image, revision: revision, time: submittedTime, size: size)
                }
                if self.revision != revision || self.time != submittedTime || self.drawableSize != size {
                    self.needsDisplay = true
                }
            } catch {
                guard !Task.isCancelled, let self, !self.detached else { return }
                self.renderTask = nil
                self.report(error, revision: revision)
                if self.revision != revision { self.needsDisplay = true }
            }
        }
    }

    private func present(_ image: CIImage, revision: UInt, time: TimeInterval, size: CGSize) {
        guard let queue, let imageContext, let drawable = currentDrawable,
              let command = queue.makeCommandBuffer() else { needsDisplay = true; return }
        do {
            let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: command)
            destination.colorSpace = colorSpace
            let task = try imageContext.startTask(toRender: image, to: destination)
            command.present(drawable)
            framesInFlight += 1
            command.addCompletedHandler { [weak self] buffer in
                withExtendedLifetime((image, task)) { }
                let failure = buffer.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, !self.detached else { return }
                    self.framesInFlight -= 1
                    if let failure, self.revision == revision {
                        self.failedRevision = revision
                        self.model?.preview3DError = failure
                    } else if self.revision == revision {
                        self.renderedFrameCount += 1
                        self.model?.preview3DError = nil
                    }
                    // A paused seek or edit can arrive while drawable slots are occupied.
                    if self.revision != revision || self.time != time || self.drawableSize != size {
                        self.needsDisplay = true
                    }
                }
            }
            command.commit()
        } catch { report(error, revision: revision) }
    }

    private func report(_ error: Error, revision: UInt) {
        guard self.revision == revision else { return }
        failedRevision = revision
        model?.preview3DError = error.localizedDescription
    }
}
