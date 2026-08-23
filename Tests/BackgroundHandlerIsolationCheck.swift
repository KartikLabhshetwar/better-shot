import AppKit
import Foundation

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@main
enum BackgroundHandlerIsolationCheck {
    @MainActor
    static func startTimer(on counter: Counter) -> DispatchSourceTimer {
        let queue = DispatchQueue(label: "check.background.handler", qos: .utility)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        let handler: @Sendable () -> Void = { [weak counter] in
            precondition(!Thread.isMainThread, "handler must run off the main thread")
            counter?.bump()
        }
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }

    @MainActor
    static func checkPattern() {
        let counter = Counter()
        let timer = startTimer(on: counter)
        let deadline = Date().addingTimeInterval(2)
        while counter.count < 5 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        timer.cancel()
        precondition(counter.count >= 5, "timer handler never fired off the main thread: got \(counter.count)")
    }

    @MainActor
    static func checkRealRecorder() -> Int {
        let recorder = PointerCaptureRecorder()
        recorder.start(captureRect: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let file = recorder.stop()
        precondition(!file.travel.isEmpty, "pointer sampler never recorded a sample off the main thread")
        return file.travel.count
    }

    @MainActor
    static func run() {
        checkPattern()
        let samples = checkRealRecorder()
        print("ok: PointerCaptureRecorder sampled \(samples) points on its background queue without an isolation trap")
    }

    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
