import Darwin
import Foundation
import ImageIO
import MCP
import SwiftUI

@testable import BetterShot

@MainActor
func checkRecordingAgentAccess(movieURL: URL) async throws {
    let cancelledRequest = RecordingAgentRequestLease()
    precondition(cancelledRequest.isValid)
    cancelledRequest.invalidate()
    precondition(!cancelledRequest.isValid, "Revoked requests cannot start another tool")
    let session = RecordingSession(directoryURL: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".bettershotrec"))
    try FileManager.default.createDirectory(at: session.directoryURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: session.directoryURL) }
    try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
    let model = RecordingStudioModel(url: session.directoryURL)
    await model.load()
    defer { model.teardown() }
    guard let projectSnapshot = StudioProjectRegistry.shared.snapshot(for: session.directoryURL) else {
        preconditionFailure("Agent fixture must be an open project")
    }

    let access = RecordingAgentAccessController.shared
    precondition(!access.enabled && access.status == .off, "Agent Access must default off")
    let snapshots = URL(fileURLWithPath: ".build/editor-snapshots")
    try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        try snapshot(RecordingAgentAccessSettingsTab(), scheme: scheme, width: 520,
                     to: snapshots.appendingPathComponent("agent-access-\(scheme == .light ? "light" : "dark").png"),
                     height: 540)
    }
    await access.setEnabled(true)
    precondition(access.status == .ready, "Loopback listener must start")
    print("Agent endpoint: listener ready")
    for scheme in [ColorScheme.light, .dark] {
        try snapshot(RecordingAgentAccessSettingsTab(), scheme: scheme, width: 520,
                     to: snapshots.appendingPathComponent("agent-access-ready-\(scheme == .light ? "light" : "dark").png"),
                     height: 540)
    }
    let config = try JSONSerialization.jsonObject(with: Data(access.clientConfiguration().utf8)) as! [String: Any]
    let servers = config["mcpServers"] as! [String: Any]
    let bettershot = servers["bettershot"] as! [String: Any]
    let headers = bettershot["headers"] as! [String: String]
    let authorization = headers["Authorization"]!
    let endpoint = access.endpoint
    let urlSessionConfig = URLSessionConfiguration.ephemeral
    urlSessionConfig.timeoutIntervalForRequest = 8
    let urlSession = URLSession(configuration: urlSessionConfig)
    defer { urlSession.invalidateAndCancel() }

    func post(_ payload: [String: Any], token: String?, origin: String? = nil,
              host: String? = nil) async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let host { request.setValue(host, forHTTPHeaderField: "Host") }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await urlSession.data(for: request)
        return ((response as! HTTPURLResponse).statusCode,
                data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    let list: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": [:]]
    let missing = try await post(list, token: nil)
    precondition(missing.0 == 401)
    let wrong = try await post(list, token: "Bearer wrong")
    precondition(wrong.0 == 401)
    let origin = try await post(list, token: authorization, origin: "https://untrusted.invalid")
    precondition(origin.0 == 403)
    let host = try await post(list, token: authorization, host: "untrusted.invalid")
    precondition(host.0 == 421)
    var get = URLRequest(url: endpoint)
    get.httpMethod = "GET"
    let (_, getResponse) = try await urlSession.data(for: get)
    precondition((getResponse as! HTTPURLResponse).statusCode == 405)
    print("Agent endpoint: auth, Origin, Host, and method guards passed")
    let endpointPort = RecordingAgentHTTPListener.port
    let oversizedStatus = await Task.detached { [authorization, endpointPort] in
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        precondition(socketFD >= 0)
        defer { Darwin.close(socketFD) }
        var receiveTimeout = timeval(tv_sec: 3, tv_usec: 0)
        let timeoutSet = withUnsafePointer(to: &receiveTimeout) {
            Darwin.setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, $0,
                              socklen_t(MemoryLayout<timeval>.size))
        }
        precondition(timeoutSet == 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(endpointPort).bigEndian)
        address.sin_addr = in_addr(s_addr: in_addr_t(0x7f000001).bigEndian)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        precondition(connected == 0)
        let oversizedHead = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:\(endpointPort)\r\nAuthorization: \(authorization)\r\nContent-Length: 1048577\r\nConnection: close\r\n\r\n"
        let written = oversizedHead.withCString { Darwin.write(socketFD, $0, strlen($0)) }
        precondition(written == oversizedHead.utf8.count)
        var responseBytes = [UInt8]()
        while responseBytes.count < 512 && !String(decoding: responseBytes, as: UTF8.self).contains("\r\n") {
            var chunk = [UInt8](repeating: 0, count: 128)
            let received = Darwin.read(socketFD, &chunk, chunk.count)
            precondition(received > 0, "Timed out waiting for oversize HTTP status")
            responseBytes.append(contentsOf: chunk.prefix(received))
        }
        return String(decoding: responseBytes, as: UTF8.self)
    }.value
    precondition(oversizedStatus.hasPrefix("HTTP/1.1 413 "), "Oversize status: \(oversizedStatus.prefix(100))")
    print("Agent endpoint: oversized body rejected")

    let clientTransport = HTTPClientTransport(endpoint: endpoint, configuration: urlSessionConfig,
        streaming: false, requestModifier: { request in
            var request = request
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            return request
        })
    let client = Client(name: "bettershot-agent-test", version: "1")
    _ = try await client.connect(transport: clientTransport)
    let tools = try await client.listTools().tools
    precondition(tools.contains(where: { $0.name == "get_preview" }))
    let inspected = try await client.callTool(name: "inspect_timeline",
        arguments: ["handle": .string(projectSnapshot.handle.uuidString)])
    precondition(inspected.isError != true)
    await client.disconnect()
    print("Agent endpoint: SDK client initialized, listed, and called")

    var repeated = URLRequest(url: endpoint)
    repeated.httpMethod = "POST"
    repeated.setValue("application/json", forHTTPHeaderField: "Content-Type")
    repeated.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    repeated.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
    repeated.setValue(authorization, forHTTPHeaderField: "Authorization")
    repeated.httpBody = try JSONSerialization.data(withJSONObject: list)
    let concurrentRequest = repeated
    async let first = urlSession.data(for: concurrentRequest)
    async let second = urlSession.data(for: concurrentRequest)
    let (one, two) = try await (first, second)
    let firstStatus = (one.1 as! HTTPURLResponse).statusCode
    let secondStatus = (two.1 as! HTTPURLResponse).statusCode
    precondition(firstStatus == 200 && secondStatus == 200,
                 "Concurrent request statuses: \(firstStatus), \(secondStatus); " +
                 "bodies: \(String(data: one.0.prefix(256), encoding: .utf8) ?? "nontext"), " +
                 "\(String(data: two.0.prefix(256), encoding: .utf8) ?? "nontext")")
    let oneResult = try JSONSerialization.jsonObject(with: one.0) as! [String: Any]
    let twoResult = try JSONSerialization.jsonObject(with: two.0) as! [String: Any]
    precondition(oneResult["id"] as? Int == 1 && twoResult["id"] as? Int == 1,
                 "Independent clients may reuse a JSON-RPC request ID")
    print("Agent endpoint: concurrent same-ID requests passed")

    let previewPayload: [String: Any] = [
        "jsonrpc": "2.0", "id": 2, "method": "tools/call",
        "params": ["name": "get_preview", "arguments": [
            "handle": projectSnapshot.handle.uuidString,
            "expectedRevision": projectSnapshot.revision,
            "editorTime": 0.0
        ]]
    ]
    let preview = try await post(previewPayload, token: authorization)
    precondition(preview.0 == 200)
    let result = preview.1?["result"] as? [String: Any]
    precondition(result?["isError"] as? Bool != true)
    let metadata = result?["structuredContent"] as? [String: Any]
    precondition(metadata?["revision"] as? Int == Int(projectSnapshot.revision))
    let content = result?["content"] as? [[String: Any]]
    let image = content?.first(where: { $0["type"] as? String == "image" })
    precondition(image?["mimeType"] as? String == "image/png")
    let png = Data(base64Encoded: image?["data"] as? String ?? "")!
    precondition(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
    let source = CGImageSourceCreateWithData(png as CFData, nil)!
    let frame = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(frame.width <= 768 && frame.height <= 768)
    print("Agent endpoint: composed preview passed")

    func call(_ name: String, _ arguments: [String: Any], id: Int) async throws -> [String: Any] {
        let response = try await post([
            "jsonrpc": "2.0", "id": id, "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ], token: authorization)
        precondition(response.0 == 200)
        return response.1?["result"] as! [String: Any]
    }
    let handle = projectSnapshot.handle.uuidString
    let split = try await call("split_clip", ["handle": handle,
        "expectedRevision": projectSnapshot.revision,
        "editorTime": model.clipTimeline.duration / 2], id: 3)
    precondition(split["isError"] as? Bool != true)
    let splitTimeline = split["structuredContent"] as! [String: Any]
    let splitRevision = splitTimeline["revision"] as! Int
    precondition(splitRevision == Int(projectSnapshot.revision) + 1)
    let stale = try await call("split_clip", ["handle": handle,
        "expectedRevision": projectSnapshot.revision,
        "editorTime": model.clipTimeline.duration / 3], id: 4)
    precondition(stale["isError"] as? Bool == true)
    let staleError = (stale["structuredContent"] as! [String: Any])["error"] as! [String: Any]
    precondition(staleError["code"] as? String == "stale_revision")
    let undo = try await call("undo", ["handle": handle,
        "expectedRevision": splitRevision], id: 5)
    let undoTimeline = undo["structuredContent"] as! [String: Any]
    let currentRevision = undoTimeline["revision"] as! Int
    precondition(currentRevision == splitRevision + 1)
    let save = try await call("save_project", ["handle": handle,
        "expectedRevision": currentRevision], id: 6)
    let saveResult = save["structuredContent"] as! [String: Any]
    precondition(saveResult["saved"] as? Bool == true)

    let cachedMovie = session.directoryURL.appendingPathComponent("cached.mp4")
    try FileManager.default.copyItem(at: movieURL, to: cachedMovie)
    try session.installFinalVideo(movingFrom: cachedMovie, renderedFrom: model.currentEditDocument)
    let blockedSaveDirectory = session.directoryURL.appendingPathComponent("not-a-directory")
    try Data().write(to: blockedSaveDirectory)
    let oldSaveDirectory = AppPreferences.saveDirectory
    AppPreferences.saveDirectory = blockedSaveDirectory.path
    defer { AppPreferences.saveDirectory = oldSaveDirectory }
    let exportArguments: [String: Any] = ["handle": handle,
        "expectedRevision": currentRevision, "requestId": UUID().uuidString]
    let start = try await call("start_export", exportArguments, id: 7)
    precondition(start["isError"] as? Bool != true)
    let startedJob = start["structuredContent"] as! [String: Any]
    let jobID = startedJob["id"] as! String
    let repeatedStart = try await call("start_export", exportArguments, id: 8)
    precondition((repeatedStart["structuredContent"] as! [String: Any])["id"] as? String == jobID)
    var state = startedJob["state"] as! String
    for attempt in 0..<100 where state == "running" {
        try await Task.sleep(for: .milliseconds(20))
        let status = try await call("get_export_job", ["jobId": jobID], id: 9 + attempt)
        state = (status["structuredContent"] as! [String: Any])["state"] as! String
    }
    precondition(state == "failed", "A blocked export destination must retain a failed MCP job")
    print("Agent endpoint: stale edit, undo, save, and failed export passed")

    let successDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: successDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: successDirectory) }
    AppPreferences.saveDirectory = successDirectory.path
    let successfulArguments: [String: Any] = ["handle": handle,
        "expectedRevision": currentRevision, "requestId": UUID().uuidString]
    let successfulStart = try await call("start_export", successfulArguments, id: 200)
    let successfulJob = successfulStart["structuredContent"] as! [String: Any]
    let successfulID = successfulJob["id"] as! String
    let successfulRetry = try await call("start_export", successfulArguments, id: 201)
    precondition((successfulRetry["structuredContent"] as! [String: Any])["id"] as? String == successfulID)
    var successfulState = successfulJob
    for attempt in 0..<150 {
        if successfulState["state"] as? String != "running" { break }
        try await Task.sleep(for: .milliseconds(20))
        let response = try await call("get_export_job", ["jobId": successfulID], id: 202 + attempt)
        successfulState = response["structuredContent"] as! [String: Any]
    }
    precondition(successfulState["state"] as? String == "completed")
    let exportedName = successfulState["fileName"] as! String
    precondition(FileManager.default.fileExists(
        atPath: successDirectory.appendingPathComponent(exportedName).path))
    print("Agent endpoint: successful idempotent cached export passed")

    await access.rotateToken()
    precondition(access.status == .ready, "Rotation status: \(String(describing: access.status))")
    let revoked = try await post(list, token: authorization)
    precondition(revoked.0 == 401)
    let rotated = try JSONSerialization.jsonObject(with: Data(access.clientConfiguration().utf8)) as! [String: Any]
    let newToken = (((rotated["mcpServers"] as! [String: Any])["bettershot"] as! [String: Any])["headers"] as! [String: String])["Authorization"]!
    precondition(newToken != authorization)
    let withRotatedToken = try await post(list, token: newToken)
    precondition(withRotatedToken.0 == 200)
    print("Agent endpoint: token rotation passed")
    await access.setEnabled(false)
    precondition(!access.enabled && access.status == .off)
    print("Agent endpoint: listener disabled")
    do {
        _ = try await post(list, token: newToken)
        preconditionFailure("Disabling Agent Access must close the loopback listener")
    } catch is URLError {
        // The listener is closed; a fresh HTTP connection must be refused.
    }
    print("PASS Agent Access SDK client, concurrent IDs, composed preview, stale edit, save/export, auth, rotation, and shutdown")
}
