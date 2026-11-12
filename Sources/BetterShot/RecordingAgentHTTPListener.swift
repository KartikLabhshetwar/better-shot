import Foundation
import MCP
import NIOCore
import NIOHTTP1
import NIOPosix

/// A stopped or expired HTTP request cannot begin another tool operation,
/// even if the SDK still has a dispatched handler task after disconnecting.
@MainActor
final class RecordingAgentRequestLease {
    private let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    private var active = true

    var isValid: Bool { active && ContinuousClock.now < deadline }
    func invalidate() { active = false }
}

/// The released MCP transport matches response waiters by JSON-RPC ID. Give
/// each HTTP request its own server and transport so independent clients can
/// reuse ordinary IDs without crossing responses.
private actor RecordingAgentRequestRuntime {
    private struct ActiveRequest {
        let server: Server
        let lease: RecordingAgentRequestLease
    }
    private var requests = Set<UUID>()
    private var active: [UUID: ActiveRequest] = [:]
    private var stopped = false
    private let maximumConcurrentRequests = 4

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        guard !stopped else {
            return .error(statusCode: 503, .internalError("Agent Access is stopping"))
        }
        guard requests.count < maximumConcurrentRequests else {
            return .error(statusCode: 503, .internalError("Agent Access is busy; retry shortly"))
        }

        let id = UUID()
        requests.insert(id)
        defer { requests.remove(id) }
        let lease = await RecordingAgentRequestLease()
        let transport = StatelessHTTPServerTransport()
        let server = await RecordingAgentMCPTools.makeServer(operations: .shared, lease: lease)
        guard !stopped else {
            await lease.invalidate()
            return .error(statusCode: 503, .internalError("Agent Access is stopping"))
        }
        active[id] = ActiveRequest(server: server, lease: lease)
        defer { active.removeValue(forKey: id) }

        do {
            try await server.start(transport: transport)
        } catch {
            await lease.invalidate()
            await server.stop()
            return .error(statusCode: 500, .internalError("Agent Access could not start this request"))
        }

        let timer = Task {
            do {
                try await Task.sleep(for: .seconds(30))
                await lease.invalidate()
                await server.stop()
                return true
            } catch {
                return false
            }
        }
        let response = await transport.handleRequest(request)
        timer.cancel()
        let timedOut = await timer.value
        await lease.invalidate()
        await server.stop()
        if timedOut {
            return .error(statusCode: 504, .internalError("Agent request timed out; retry"))
        }
        if stopped {
            return .error(statusCode: 503, .internalError("Agent Access is stopping"))
        }
        return response
    }

    func stop() async {
        stopped = true
        let servers = Array(active.values)
        for request in servers { await request.lease.invalidate() }
        for request in servers { await request.server.stop() }
    }
}

nonisolated private final class RecordingAgentChannels: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [UUID: Channel] = [:]

    func add(_ channel: Channel) {
        let id = UUID()
        lock.withLock { channels[id] = channel }
        channel.closeFuture.whenComplete { [self] _ in
            lock.withLock { channels.removeValue(forKey: id) }
        }
    }

    func closeAll() async {
        let open = lock.withLock { Array(channels.values) }
        for channel in open { try? await channel.close().get() }
    }
}

// NIO confines its mutable parser state to the channel event loop. Work that
// can await runs in a Task, and responses hop back to that same event loop.
nonisolated private final class RecordingAgentHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let runtime: RecordingAgentRequestRuntime
    private let token: String
    private let port: Int
    private var head: HTTPRequestHead?
    private var body = Data()
    private var responded = false
    private static let maximumBodyBytes = 1_048_576

    init(runtime: RecordingAgentRequestRuntime, token: String, port: Int) {
        self.runtime = runtime
        self.token = token
        self.port = port
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !responded else { return }
        switch unwrapInboundIn(data) {
        case .head(let requestHead):
            guard head == nil else {
                reject(context, .badRequest)
                return
            }
            if let status = invalidHeadStatus(requestHead) {
                reject(context, status)
                return
            }
            head = requestHead
            body.removeAll(keepingCapacity: true)
        case .body(var buffer):
            guard head != nil else { return }
            guard buffer.readableBytes <= Self.maximumBodyBytes - body.count else {
                reject(context, .payloadTooLarge)
                return
            }
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            guard let head else { return }
            self.head = nil
            responded = true
            let request = MCP.HTTPRequest(
                method: head.method.rawValue,
                headers: Dictionary(head.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last }),
                body: body,
                path: head.uri
            )
            let channel = context.channel
            Task { [runtime] in
                let response = await runtime.handle(request)
                channel.eventLoop.execute {
                    switch response {
                    case .stream:
                        RecordingAgentHTTPWriter.write(status: .notImplemented, headers: [:], body: nil, to: channel)
                    default:
                        RecordingAgentHTTPWriter.write(response, to: channel)
                    }
                }
            }
        }
    }

    private func invalidHeadStatus(_ head: HTTPRequestHead) -> HTTPResponseStatus? {
        guard head.uri == "/mcp" else { return .notFound }
        guard head.method == .POST else { return .methodNotAllowed }
        let host = head.headers["Host"]
        guard host.count == 1, host[0] == "127.0.0.1:\(port)" else { return .misdirectedRequest }
        let origin = head.headers["Origin"]
        guard origin.isEmpty || (origin.count == 1 && origin[0] == "http://127.0.0.1:\(port)") else {
            return .forbidden
        }
        let authorization = head.headers["Authorization"]
        guard authorization.count == 1,
              Self.equalToken(authorization[0], "Bearer \(token)") else { return .unauthorized }
        let lengths = head.headers["Content-Length"]
        if lengths.count > 1 { return .badRequest }
        if let length = lengths.first {
            guard let count = Int(length), count >= 0 else { return .badRequest }
            if count > Self.maximumBodyBytes { return .payloadTooLarge }
        }
        return nil
    }

    private static func equalToken(_ candidate: String, _ expected: String) -> Bool {
        let lhs = Array(candidate.utf8)
        let rhs = Array(expected.utf8)
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs, rhs) { difference |= a ^ b }
        return difference == 0
    }

    private func reject(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus) {
        responded = true
        head = nil
        body.removeAll()
        RecordingAgentHTTPWriter.write(status: status, headers: [:], body: nil, to: context.channel)
    }
}

nonisolated private enum RecordingAgentHTTPWriter {
    static func write(_ response: MCP.HTTPResponse, to channel: Channel) {
        write(
            status: HTTPResponseStatus(statusCode: response.statusCode),
            headers: HTTPHeaders(response.headers.map { ($0.key, $0.value) }),
            body: response.bodyData,
            to: channel
        )
    }

    static func write(status: HTTPResponseStatus, headers responseHeaders: HTTPHeaders, body: Data?, to channel: Channel) {
        var headers = responseHeaders
        headers.replaceOrAdd(name: "Content-Length", value: String(body?.count ?? 0))
        headers.replaceOrAdd(name: "Connection", value: "close")
        if status == .methodNotAllowed { headers.replaceOrAdd(name: "Allow", value: "POST") }
        if status == .unauthorized { headers.replaceOrAdd(name: "WWW-Authenticate", value: "Bearer") }
        channel.write(HTTPServerResponsePart.head(.init(version: .http1_1, status: status, headers: headers)), promise: nil)
        if let body {
            var buffer = channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
            channel.close(promise: nil)
        }
    }
}

final class RecordingAgentHTTPListener {
    static let port = 39615
    static let endpoint = URL(string: "http://127.0.0.1:\(port)/mcp")!

    private let group: MultiThreadedEventLoopGroup
    private let listener: Channel
    private let channels: RecordingAgentChannels
    private let runtime: RecordingAgentRequestRuntime

    private init(group: MultiThreadedEventLoopGroup, listener: Channel,
                 channels: RecordingAgentChannels, runtime: RecordingAgentRequestRuntime) {
        self.group = group
        self.listener = listener
        self.channels = channels
        self.runtime = runtime
    }

    static func start(token: String) async throws -> RecordingAgentHTTPListener {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channels = RecordingAgentChannels()
        let runtime = RecordingAgentRequestRuntime()
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channels.add(channel)
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(RecordingAgentHTTPHandler(
                        runtime: runtime, token: token, port: port
                    ))
                }
            }
        do {
            let listener = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            return RecordingAgentHTTPListener(group: group, listener: listener,
                                              channels: channels, runtime: runtime)
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    func stop() async {
        await runtime.stop()
        try? await listener.close().get()
        await channels.closeAll()
        try? await group.shutdownGracefully()
    }
}
