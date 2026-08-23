import Foundation

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@MainActor
func startTimer(on counter: Counter) -> DispatchSourceTimer {
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
func run() {
    let counter = Counter()
    let timer = startTimer(on: counter)
    let deadline = Date().addingTimeInterval(2)
    while counter.count < 5 && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    timer.cancel()
    precondition(counter.count >= 5, "timer handler never fired off the main thread: got \(counter.count)")
    print("ok: background handler fired \(counter.count) times without an isolation trap")
}

MainActor.assumeIsolated { run() }
