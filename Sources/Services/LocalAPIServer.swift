import Foundation
import Network

/// Optional HTTP API for scripting the beautifier. Off by default, and bound to loopback only —
/// it is never reachable from the network.
@MainActor
@Observable
final class LocalAPIServer {
    static let shared = LocalAPIServer()

    nonisolated static let defaultPort: UInt16 = 17595

    /// The ports the preference accepts. Below 1024 needs root, so it would only ever fail to bind.
    nonisolated static let validPortRange: ClosedRange<Int> = 1024...65535

    private(set) var isRunning = false
    /// The port actually bound, which is the truth the UI should show — the stored preference may
    /// be out of range and fall back to `defaultPort`.
    private(set) var activePort: UInt16?
    private(set) var lastError: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.bettershot.localapi", qos: .userInitiated)

    private init() {}

    /// Starts or stops the server to match the current preference. Safe to call at any time.
    func applyPreferences() {
        if AppPreferences.localAPIEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        stop()

        let port = AppPreferences.localAPIPort
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port \(port)"
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Binding to the loopback address is what keeps this API local-only.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: endpointPort)

        do {
            let listener = try NWListener(using: parameters)
            let queue = self.queue

            listener.newConnectionHandler = { connection in
                LocalAPIConnection.serve(connection, on: queue)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handle(state: state)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        isRunning = false
        activePort = nil
        lastError = nil
    }

    private func handle(state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            activePort = listener?.port?.rawValue
            lastError = nil
        case .failed(let error):
            let port = AppPreferences.localAPIPort
            stop()
            lastError = Self.describe(error, port: port)
        case .cancelled:
            // A cancel arriving here is system-initiated: stop() detaches this handler
            // before cancelling, so without the reset the UI would keep showing a
            // bound port (and a stale error) for a listener that no longer exists.
            isRunning = false
            activePort = nil
            lastError = nil
        default:
            break
        }
    }

    private static func describe(_ error: NWError, port: UInt16) -> String {
        // The common failure by far is another process already holding the port.
        if case .posix(.EADDRINUSE) = error {
            return "Port \(port) is already in use. Pick a different port."
        }
        return error.localizedDescription
    }
}

// MARK: - Connection Handling

/// Reads one request per connection, answers it, and closes. Deliberately off the main actor so
/// that decoding and rendering never block the UI.
private enum LocalAPIConnection {

    /// Caps how much a single client can make us buffer.
    static let maxBodySize = 64 * 1024 * 1024

    static func serve(_ connection: NWConnection, on queue: DispatchQueue) {
        connection.start(queue: queue)

        Task.detached {
            let response: LocalAPIResponse
            do {
                let request = try await read(from: connection)
                response = reject(request) ?? LocalAPIRouter.route(request)
            } catch let error as LocalAPIRequest.ParseError {
                response = errorResponse(for: error)
            } catch {
                connection.cancel()
                return
            }

            try? await send(response.serialized, on: connection)
            connection.cancel()
        }
    }

    /// Rejects requests whose Host isn't loopback. Stops a web page from reaching the API by
    /// pointing a hostname it controls at 127.0.0.1 (DNS rebinding).
    private static func reject(_ request: LocalAPIRequest) -> LocalAPIResponse? {
        let rawHost = request.header("host") ?? ""
        // Host names are case-insensitive, so "LOCALHOST" has to pass the same check as "localhost".
        let host = rawHost.lowercased()
        let name: String
        if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
            name = String(host[host.index(after: host.startIndex)..<close])   // [::1]:port
        } else {
            name = String(host.prefix(while: { $0 != ":" }))
        }

        guard ["127.0.0.1", "localhost", "::1"].contains(name) else {
            return .error(403, "Host '\(rawHost)' is not allowed. The local API only answers loopback (127.0.0.1, localhost, ::1)")
        }
        return nil
    }

    private static func errorResponse(for error: LocalAPIRequest.ParseError) -> LocalAPIResponse {
        switch error {
        case .malformedHead:
            return .error(400, "Malformed HTTP request")
        case .headTooLarge:
            return .error(431, "Request headers too large")
        case .bodyTooLarge:
            return .error(413, "Request body exceeds \(maxBodySize / 1024 / 1024) MB")
        }
    }

    private static func read(from connection: NWConnection) async throws -> LocalAPIRequest {
        var buffer = Data()

        while true {
            if let request = try LocalAPIRequest.parse(buffer, maxBodySize: maxBodySize) {
                return request
            }

            let (chunk, isComplete) = try await receive(on: connection)
            if let chunk { buffer.append(chunk) }

            if isComplete {
                // Peer finished sending; one last parse decides between a request and a truncated one.
                if let request = try LocalAPIRequest.parse(buffer, maxBodySize: maxBodySize) {
                    return request
                }
                throw LocalAPIRequest.ParseError.malformedHead
            }
        }
    }

    private static func receive(on connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, isComplete))
                }
            }
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
