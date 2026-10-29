import Foundation
import MCP

/// MCP surface for the local Studio agent endpoint. Project access remains
/// limited to opaque IDs minted by `RecordingAgentOperations`.
enum RecordingAgentMCPTools {
    static func makeServer(operations: RecordingAgentOperations, lease: RecordingAgentRequestLease) async -> MCP.Server {
        let server = MCP.Server(
            name: "bettershot",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            instructions: "Edit only recordings in BetterShot’s recording library. Use the opaque project handle and current revision returned by inspect_timeline for every edit. Preview images show the composed Studio output. For clips with sourceId, sourceStart/sourceEnd use the leaf recording’s authored editor clock, and sources[].duration uses that same clock. editorTime/editorStart/editorEnd use the outer project clock. Clip speed compounds the leaf’s authored speed. Append individual recordings; nested multi-source projects cannot be appended.",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: definitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await call(params, operations: operations, lease: lease)
        }
        return server
    }

    private static let definitions: [Tool] = [
        tool("list_projects", "List BetterShot recordings available to open.", readOnly: true),
        tool("open_project", "Open a known recording in BetterShot and return its handle and timeline.", ["projectId": "string"]),
        tool("inspect_timeline", "Read the current timeline and revision for an open project.", ["handle": "string"], readOnly: true),
        tool("get_preview", "Render a bounded composed PNG preview at an editor timeline time.", ["handle": "string", "expectedRevision": "integer", "editorTime": "number"], readOnly: true),
        tool("append_recording", "Append an individual library recording once for this requestId; nested multi-source projects are unsupported. Concurrent retries share the result; failed IDs replay the failure, so use a new ID to retry preparation.", ["handle": "string", "expectedRevision": "integer", "projectId": "string", "requestId": "string"]),
        tool("reorder_clips", "Arrange every current clip exactly once in the supplied order.", ["handle": "string", "expectedRevision": "integer", "clipIds": "array"]),
        tool("split_clip", "Split the clip at an editor timeline time.", ["handle": "string", "expectedRevision": "integer", "editorTime": "number"]),
        tool("trim_clip", "Set a clip’s range. For sourceId clips, bounds use that source’s authored editor time and sources[].duration; legacy clips use raw source time.", ["handle": "string", "expectedRevision": "integer", "clipId": "string", "sourceStart": "number", "sourceEnd": "number"]),
        tool("delete_clip", "Remove a clip while retaining at least one playable clip.", ["handle": "string", "expectedRevision": "integer", "clipId": "string"]),
        tool("set_clip_speed", "Set a clip speed between 0.25× and 8×.", ["handle": "string", "expectedRevision": "integer", "clipId": "string", "speed": "number"]),
        tool("undo", "Undo the latest project edit.", ["handle": "string", "expectedRevision": "integer"]),
        tool("redo", "Redo the latest undone project edit.", ["handle": "string", "expectedRevision": "integer"]),
        tool("save_project", "Save the current open project.", ["handle": "string", "expectedRevision": "integer"]),
        tool("start_export", "Start an export once for this requestId; reuse that ID to safely retry.", ["handle": "string", "expectedRevision": "integer", "requestId": "string"]),
        tool("get_export_job", "Read the retained state of an export job.", ["jobId": "string"], readOnly: true),
        tool("cancel_export", "Cancel an active export job.", ["jobId": "string"]),
    ]

    private static func tool(
        _ name: String,
        _ description: String,
        _ properties: [String: String] = [:],
        readOnly: Bool = false
    ) -> Tool {
        let fields = properties.mapValues { type in
            Value.object(type == "array"
                ? ["type": .string(type), "items": .object(["type": .string("string")])]
                : ["type": .string(type)])
        }
        return Tool(
            name: name,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(fields),
                "required": .array(properties.keys.sorted().map(Value.string)),
                "additionalProperties": .bool(false),
            ]),
            annotations: .init(readOnlyHint: readOnly, destructiveHint: readOnly ? nil : true)
        )
    }

    private static func call(
        _ params: CallTool.Parameters,
        operations: RecordingAgentOperations,
        lease: RecordingAgentRequestLease
    ) async -> CallTool.Result {
        guard lease.isValid else {
            return failure("request_cancelled", "The request expired or Agent Access stopped before the operation began.")
        }
        do {
            let args = params.arguments ?? [:]
            switch params.name {
            case "list_projects": return try result(operations.listProjects())
            case "open_project": return try await result(operations.openProject(id: uuid(args, "projectId")))
            case "inspect_timeline": return try result(operations.inspect(handle: uuid(args, "handle")))
            case "get_preview":
                let preview = try await operations.preview(
                    handle: uuid(args, "handle"),
                    expectedRevision: revision(args),
                    at: number(args, "editorTime")
                )
                let metadata = try Value(preview.metadata)
                return .init(content: [.image(data: preview.png.base64EncodedString(), mimeType: "image/png")], structuredContent: Optional.some(metadata))
            case "append_recording":
                return try await result(operations.appendRecording(
                    handle: uuid(args, "handle"), expectedRevision: revision(args),
                    projectID: uuid(args, "projectId"), requestID: uuid(args, "requestId"), lease: lease
                ))
            case "reorder_clips":
                return try result(operations.reorderClips(handle: uuid(args, "handle"),
                    expectedRevision: revision(args), clipIDs: uuids(args, "clipIds")))
            case "split_clip":
                return try result(operations.split(handle: uuid(args, "handle"), expectedRevision: revision(args), at: number(args, "editorTime")))
            case "trim_clip":
                return try result(operations.trim(
                    handle: uuid(args, "handle"), expectedRevision: revision(args), clipID: uuid(args, "clipId"),
                    sourceStart: number(args, "sourceStart"), sourceEnd: number(args, "sourceEnd")
                ))
            case "delete_clip":
                return try result(operations.deleteClip(handle: uuid(args, "handle"), expectedRevision: revision(args), clipID: uuid(args, "clipId")))
            case "set_clip_speed":
                return try result(operations.setSpeed(handle: uuid(args, "handle"), expectedRevision: revision(args), clipID: uuid(args, "clipId"), speed: number(args, "speed")))
            case "undo": return try result(operations.undo(handle: uuid(args, "handle"), expectedRevision: revision(args)))
            case "redo": return try result(operations.redo(handle: uuid(args, "handle"), expectedRevision: revision(args)))
            case "save_project": return try result(operations.save(handle: uuid(args, "handle"), expectedRevision: revision(args)))
            case "start_export":
                return try result(operations.startExport(
                    handle: uuid(args, "handle"), expectedRevision: revision(args), requestID: uuid(args, "requestId")
                ))
            case "get_export_job": return try result(operations.exportJob(id: uuid(args, "jobId")))
            case "cancel_export": return try result(operations.cancelExportJob(id: uuid(args, "jobId")))
            default:
                throw RecordingAgentOperationError.invalidArgument("Unknown BetterShot tool.")
            }
        } catch is CancellationError {
            return error("request_cancelled", "The request was cancelled before it completed.")
        } catch let operationError as RecordingAgentOperationError {
            return error(operationError.code, operationError.errorDescription ?? "The operation failed.")
        } catch {
            return failure("operation_unavailable", "BetterShot could not complete the request. Check the Studio window and retry.")
        }
    }

    private static func result<T: Codable>(_ value: T) throws -> CallTool.Result {
        let structured = try Value(value)
        return .init(content: [.text(text: "ok", annotations: nil, _meta: nil)], structuredContent: Optional.some(structured))
    }

    private static func error(_ code: String, _ message: String) -> CallTool.Result {
        let content = Value.object(["error": .object(["code": .string(code), "message": .string(message)])])
        return .init(content: [.text(text: "\(code): \(message)", annotations: nil, _meta: nil)], structuredContent: Optional.some(content), isError: true)
    }

    private static func failure(_ code: String, _ message: String) -> CallTool.Result {
        error(code, message)
    }

    private static func uuid(_ args: [String: Value], _ key: String) throws -> UUID {
        guard let raw = args[key]?.stringValue, let value = UUID(uuidString: raw) else {
            throw RecordingAgentOperationError.invalidArgument("\(key) must be a UUID string.")
        }
        return value
    }

    private static func uuids(_ args: [String: Value], _ key: String) throws -> [UUID] {
        guard case let .array(values)? = args[key] else {
            throw RecordingAgentOperationError.invalidArgument("\(key) must be an array of UUID strings.")
        }
        return try values.map { value in try uuid([key: value], key) }
    }

    private static func revision(_ args: [String: Value]) throws -> UInt64 {
        guard let value = args["expectedRevision"]?.intValue, value >= 0 else {
            throw RecordingAgentOperationError.invalidArgument("expectedRevision must be a nonnegative integer.")
        }
        return UInt64(value)
    }

    private static func number(_ args: [String: Value], _ key: String) throws -> Double {
        guard let value = args[key]?.doubleValue ?? args[key]?.intValue.map(Double.init), value.isFinite else {
            throw RecordingAgentOperationError.invalidArgument("\(key) must be a finite number.")
        }
        return value
    }
}
