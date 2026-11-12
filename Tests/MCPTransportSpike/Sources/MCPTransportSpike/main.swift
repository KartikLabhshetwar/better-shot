import Foundation
import MCP
import NIOCore
import NIOHTTP1
import NIOPosix

// NIO serializes this handler's mutable request state on its channel event loop.
private final class MCPHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let transport: StatelessHTTPServerTransport
    private let bearerToken: String
    private var head: HTTPRequestHead?
    private var body = Data()

    init(transport: StatelessHTTPServerTransport, bearerToken: String) {
        self.transport = transport
        self.bearerToken = bearerToken
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let requestHead):
            head = requestHead
            body.removeAll(keepingCapacity: true)
        case .body(var buffer):
            guard head != nil else { return }
            guard body.count + buffer.readableBytes <= 1_048_576 else {
                head = nil
                respond(context: context, status: .payloadTooLarge, body: nil)
                return
            }
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            guard let head else { return }
            self.head = nil
            let port = context.channel.localAddress?.port
            let headers = Dictionary(
                head.headers.map { ($0.name, $0.value) },
                uniquingKeysWith: { _, last in last }
            )
            let request = MCP.HTTPRequest(
                method: head.method.rawValue,
                headers: headers,
                body: body,
                path: head.uri
            )

            Task { [transport, bearerToken, channel = context.channel] in
                let response: MCP.HTTPResponse
                if head.uri != "/mcp" {
                    response = .error(statusCode: 404, .invalidRequest("Not Found"))
                } else if request.header(HTTPHeaderName.host) != "127.0.0.1:\(port ?? -1)" {
                    response = .error(statusCode: 421, .invalidRequest("Host not allowed"))
                } else if request.header(HTTPHeaderName.authorization) != "Bearer \(bearerToken)" {
                    response = .error(statusCode: 401, .invalidRequest("Unauthorized"))
                } else {
                    response = await transport.handleRequest(request)
                }

                channel.eventLoop.execute {
                    switch response {
                    case .stream:
                        HTTPResponseWriter.write(
                            status: .notImplemented, headers: [:], body: nil, to: channel
                        )
                    default:
                        HTTPResponseWriter.write(response, to: channel)
                    }
                }
            }
        }
    }

    private func respond(context: ChannelHandlerContext, status: HTTPResponseStatus, body: Data?) {
        HTTPResponseWriter.write(status: status, headers: [:], body: body, to: context.channel)
    }
}

private enum HTTPResponseWriter {
    static func write(_ response: MCP.HTTPResponse, to channel: Channel) {
        write(
            status: HTTPResponseStatus(statusCode: response.statusCode),
            headers: HTTPHeaders(response.headers.map { ($0.key, $0.value) }),
            body: response.bodyData,
            to: channel
        )
    }

    static func write(
        status: HTTPResponseStatus,
        headers responseHeaders: HTTPHeaders,
        body: Data?,
        to channel: Channel
    ) {
        var headers = HTTPHeaders()
        for (name, value) in responseHeaders { headers.add(name: name, value: value) }
        headers.replaceOrAdd(name: "Content-Length", value: String(body?.count ?? 0))
        headers.replaceOrAdd(name: "Connection", value: "close")
        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: headers
        )
        channel.write(HTTPServerResponsePart.head(head), promise: nil)
        if let data = body {
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
            channel.close(promise: nil)
        }
    }

}

private func post(
    _ message: [String: Any],
    to endpoint: URL,
    bearerToken: String? = nil,
    origin: String? = nil
) async throws -> (HTTPURLResponse, [String: Any]?) {
    var request = URLRequest(url: endpoint, timeoutInterval: 5)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
    if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
    request.httpBody = try JSONSerialization.data(withJSONObject: message)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 10
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw SpikeError.badResponse }
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return (response, json)
}

private enum SpikeError: Error { case badResponse, assertion(String) }

@main
private enum MCPTransportSpike {
    static func main() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let transport = StatelessHTTPServerTransport()
        let bearerToken = UUID().uuidString
        let server = Server(
            name: "bettershot-transport-spike",
            version: "0.0.0-spike",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [
                Tool(
                    name: "ping",
                    description: "Return a fixed response to verify transport wiring.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    annotations: .init(readOnlyHint: true)
                ),
            ])
        }
        await server.withMethodHandler(CallTool.self) { params in
            guard params.name == "ping" else { throw MCPError.invalidRequest("Unknown tool") }
            return .init(content: [.text(text: "pong", annotations: nil, _meta: nil)])
        }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        MCPHTTPHandler(transport: transport, bearerToken: bearerToken)
                    )
                }
            }
        let listener: Channel
        do {
            listener = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
        do {
            try await server.start(transport: transport)
            guard let port = listener.localAddress?.port else { throw SpikeError.badResponse }
            let endpoint = URL(string: "http://127.0.0.1:\(port)/mcp")!
            let (initialized, initializeBody) = try await post([
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": [
                    "protocolVersion": "2025-11-25",
                    "capabilities": [String: Any](),
                    "clientInfo": ["name": "URLSession-spike", "version": "1"],
                ],
            ], to: endpoint, bearerToken: bearerToken)
            try require(initialized.statusCode == 200 && initializeBody?["result"] != nil, "initialize failed")

            let (acknowledged, _) = try await post([
                "jsonrpc": "2.0", "method": "notifications/initialized",
            ], to: endpoint, bearerToken: bearerToken)
            try require(acknowledged.statusCode == 202, "initialized notification failed")

            let (listed, listBody) = try await post([
                "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [String: Any](),
            ], to: endpoint, bearerToken: bearerToken)
            let result = listBody?["result"] as? [String: Any]
            let tools = result?["tools"] as? [[String: Any]] ?? []
            try require(listed.statusCode == 200 && tools.contains { $0["name"] as? String == "ping" }, "tools/list failed")

            let (called, callBody) = try await post([
                "jsonrpc": "2.0", "id": 3, "method": "tools/call",
                "params": ["name": "ping", "arguments": [String: Any]()],
            ], to: endpoint, bearerToken: bearerToken)
            let content = (callBody?["result"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            try require(called.statusCode == 200 && content.first?["text"] as? String == "pong", "tools/call failed")

            let (missingToken, _) = try await post([
                "jsonrpc": "2.0", "id": 4, "method": "tools/list", "params": [String: Any](),
            ], to: endpoint)
            try require(missingToken.statusCode == 401, "missing token was accepted")

            let (wrongToken, _) = try await post([
                "jsonrpc": "2.0", "id": 5, "method": "tools/list", "params": [String: Any](),
            ], to: endpoint, bearerToken: "wrong-token")
            try require(wrongToken.statusCode == 401, "wrong token was accepted")

            let (rejected, _) = try await post([
                "jsonrpc": "2.0", "id": 6, "method": "tools/list", "params": [String: Any](),
            ], to: endpoint, bearerToken: bearerToken, origin: "https://example.invalid")
            try require(rejected.statusCode == 403, "untrusted Origin was not rejected")

            let (oversized, _) = try await post([
                "jsonrpc": "2.0", "id": 7, "method": "tools/list", "params": [String: Any](),
                "padding": String(repeating: "x", count: 1_048_577),
            ], to: endpoint, bearerToken: bearerToken)
            try require(oversized.statusCode == 413, "oversized request was not rejected")

            await server.stop()
            try await listener.close().get()
            try await group.shutdownGracefully()
            print("PASS: MCP round-trip, auth, Origin and body-limit rejection; listener closed")
        } catch {
            await server.stop()
            try? await listener.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SpikeError.assertion(message) }
    }
}
