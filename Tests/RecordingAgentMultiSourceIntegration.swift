import AVFoundation
import Foundation
import MCP

@testable import BetterShot

@MainActor
func checkRecordingAgentMultiSource(movieURL: URL) async throws {
    precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1")
    let library = RecordingSessionStore.recordingsDirectory
    precondition(library.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    func fixture() throws -> RecordingSession {
        let session = try RecordingSessionStore.createSession()
        try FileManager.default.copyItem(at: movieURL, to: session.screenURL)
        return session
    }
    let root = try fixture()
    let source = try fixture()
    defer {
        try? FileManager.default.removeItem(at: root.directoryURL)
        try? FileManager.default.removeItem(at: source.directoryURL)
    }
    let originalMovie = try Data(contentsOf: source.screenURL)
    let model = RecordingStudioModel(url: root.directoryURL)
    let sourceModel = RecordingStudioModel(url: source.directoryURL)
    await model.load()
    await sourceModel.load()
    defer { model.teardown(); sourceModel.teardown() }
    precondition(model.isLoaded && sourceModel.isLoaded)
    // Unsaved source edits must be snapshotted rather than reread from disk.
    sourceModel.style.padding = 0.17
    let sourceDocument = sourceModel.currentEditDocument
    let agent = RecordingAgentOperations.shared
    #if DEBUG
    defer { agent.appendPreparedForTesting = nil }
    #endif
    let projects = agent.listProjects()
    let sourceID = projects.first { $0.name == source.displayName }!.id
    let handle = StudioProjectRegistry.shared.snapshot(for: root.directoryURL)!.handle
    let initial = try agent.inspect(handle: handle)
    precondition(initial.sources.isEmpty && initial.clips.allSatisfy { $0.sourceId == nil })
    func expectError(_ code: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected \(code)") }
        catch let error as RecordingAgentOperationError { precondition(error.code == code) }
        catch { preconditionFailure("Unexpected error: \(error)") }
    }
    model.isAddingRecording = true
    expectError("operation_unavailable") {
        _ = try agent.split(handle: handle, expectedRevision: initial.revision, at: initial.duration / 2)
    }
    model.isAddingRecording = false
    model.isEditingSource = true
    expectError("operation_unavailable") {
        _ = try agent.save(handle: handle, expectedRevision: initial.revision)
    }
    model.isEditingSource = false
    let duplicateSource = RecordingStudioModel(url: source.directoryURL)
    await duplicateSource.load()
    do {
        _ = try await agent.appendRecording(handle: handle, expectedRevision: initial.revision,
            projectID: sourceID, requestID: UUID(), lease: RecordingAgentRequestLease())
        preconditionFailure("Ambiguous source editors must be rejected")
    } catch RecordingAgentOperationError.ambiguousProject {}
    duplicateSource.teardown()
    do {
        _ = try await agent.appendRecording(handle: handle, expectedRevision: initial.revision,
            projectID: UUID(), requestID: UUID(), lease: RecordingAgentRequestLease())
        preconditionFailure("Unknown library IDs must be rejected")
    } catch RecordingAgentOperationError.unknownProject {}
    let revoked = RecordingAgentRequestLease()
    revoked.invalidate()
    do {
        _ = try await agent.appendRecording(handle: handle, expectedRevision: initial.revision,
            projectID: sourceID, requestID: UUID(), lease: revoked)
        preconditionFailure("Revoked requests cannot append")
    } catch is CancellationError {}
    let requestID = UUID()
    let lease = RecordingAgentRequestLease()
    async let first = agent.appendRecording(handle: handle, expectedRevision: initial.revision,
        projectID: sourceID, requestID: requestID, lease: lease)
    async let concurrent = agent.appendRecording(handle: handle, expectedRevision: initial.revision,
        projectID: sourceID, requestID: requestID, lease: RecordingAgentRequestLease())
    let (appended, duplicate) = try await (first, concurrent)
    precondition(appended == duplicate && appended.revision == initial.revision + 1)
    precondition(appended.sources.count == 2 && appended.clips.count == 2)
    precondition(appended.clips.allSatisfy { clip in appended.sources.contains { $0.id == clip.sourceId } })
    let incomingSource = appended.sources.last!.id
    precondition(model.currentEditDocument.sourceDocuments?[incomingSource] == sourceDocument)
    let retried = try await agent.appendRecording(handle: handle, expectedRevision: initial.revision,
        projectID: sourceID, requestID: requestID, lease: RecordingAgentRequestLease())
    precondition(retried == appended, "Completed retries return their original receipt despite a stale input revision")
    do {
        _ = try await agent.appendRecording(handle: handle, expectedRevision: appended.revision,
            projectID: sourceID, requestID: requestID, lease: RecordingAgentRequestLease())
        preconditionFailure("A receipt cannot be reused with different arguments")
    } catch RecordingAgentOperationError.invalidArgument {}
    let failedRequestID = UUID()
    for _ in 0..<2 {
        do {
            _ = try await agent.appendRecording(handle: handle, expectedRevision: initial.revision,
                projectID: sourceID, requestID: failedRequestID, lease: RecordingAgentRequestLease())
            preconditionFailure("Failed request receipts must replay their original failure")
        } catch let RecordingAgentOperationError.staleRevision(expected, revision) {
            precondition(expected == initial.revision && revision == appended.revision)
        }
    }
    expectError("stale_revision") {
        _ = try agent.reorderClips(handle: handle, expectedRevision: initial.revision,
            clipIDs: appended.clips.map(\.id))
    }
    expectError("invalid_argument") {
        _ = try agent.reorderClips(handle: handle, expectedRevision: appended.revision,
            clipIDs: [appended.clips[0].id, appended.clips[0].id])
    }
    let unchanged = try agent.reorderClips(handle: handle, expectedRevision: appended.revision,
        clipIDs: appended.clips.map(\.id))
    precondition(unchanged.revision == appended.revision)
    let reordered = try agent.reorderClips(handle: handle, expectedRevision: appended.revision,
        clipIDs: appended.clips.reversed().map(\.id))
    precondition(reordered.clips.map(\.id) == appended.clips.reversed().map(\.id))
    let undone = try agent.undo(handle: handle, expectedRevision: reordered.revision)
    precondition(undone.clips == appended.clips)
    var current = try agent.redo(handle: handle, expectedRevision: undone.revision)
    precondition(current.clips == reordered.clips)
    // Outer clips may repeat and run backwards across sources: legacy neighbor bounds do not apply.
    current = try agent.trim(handle: handle, expectedRevision: current.revision,
        clipID: current.clips[0].id, sourceStart: 0.15, sourceEnd: current.clips[0].sourceEnd - 0.15)
    precondition(current.clips[0].sourceStart == 0.15)
    let preview = try await agent.preview(handle: handle, expectedRevision: current.revision,
        at: current.clips[1].editorStart + 0.1)
    precondition(!preview.png.isEmpty && preview.metadata.revision == current.revision)
    #if DEBUG
    let capacityDocument = model.currentEditDocument
    let capacitySourceIDs = Set(capacityDocument.sources!.map(\.id))
    let capacityRevision = model.editRevision
    let capacityRequests = (0..<4).map { _ in UUID() }
    let capacityLeases = (0..<4).map { _ in RecordingAgentRequestLease() }
    var capacityStaged: [URL] = []
    var releaseCapacity: [CheckedContinuation<Void, Never>] = []
    let (capacityStream, capacitySignal) = AsyncStream<Void>.makeStream()
    agent.appendPreparedForTesting = { prepared in
        capacityStaged += prepared.document.sources!.filter { !capacitySourceIDs.contains($0.id) }
            .map { $0.sessionDirectory(in: root.directoryURL) }
        await withCheckedContinuation { continuation in
            releaseCapacity.append(continuation)
            capacitySignal.yield(())
        }
    }
    let capacityTasks = capacityRequests.indices.map { index in
        Task { @MainActor in
            try await agent.appendRecording(handle: handle, expectedRevision: capacityRevision,
                projectID: sourceID, requestID: capacityRequests[index], lease: capacityLeases[index])
        }
    }
    var capacityIterator = capacityStream.makeAsyncIterator()
    for _ in capacityRequests { _ = await capacityIterator.next() }
    let capacityRetry = Task { @MainActor in
        try await agent.appendRecording(handle: handle, expectedRevision: capacityRevision,
            projectID: sourceID, requestID: capacityRequests[0], lease: RecordingAgentRequestLease())
    }
    await Task.yield()
    do {
        _ = try await agent.appendRecording(handle: handle, expectedRevision: capacityRevision,
            projectID: sourceID, requestID: UUID(), lease: RecordingAgentRequestLease())
        preconditionFailure("A fifth unique append must not prepare media")
    } catch RecordingAgentOperationError.unavailable {}
    precondition(releaseCapacity.count == 4 && capacityStaged.count == 4)
    for lease in capacityLeases { lease.invalidate() }
    for continuation in releaseCapacity { continuation.resume() }
    for task in capacityTasks + [capacityRetry] {
        do {
            _ = try await task.value
            preconditionFailure("Revoked preparations and identical retries must fail together")
        } catch is CancellationError {}
    }
    capacitySignal.finish()
    agent.appendPreparedForTesting = nil
    precondition(model.currentEditDocument == capacityDocument)
    precondition(capacityStaged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    do {
        _ = try await agent.appendRecording(handle: handle, expectedRevision: capacityRevision + 1,
            projectID: sourceID, requestID: UUID(), lease: RecordingAgentRequestLease())
        preconditionFailure("The new append must reach revision validation after pending slots are released")
    } catch RecordingAgentOperationError.staleRevision {}
    for failure in ["lease", "cancellation", "stale", "source_edit", "native", "timeout"] {
        let before = model.currentEditDocument
        let beforeSources = Set(before.sources!.map(\.id))
        let failureLease = RecordingAgentRequestLease()
        let failureRequest = UUID()
        let failureRevision = model.editRevision
        var staged: [URL] = []
        var preparations = 0
        agent.appendPreparedForTesting = { prepared in
            preparations += 1
            staged = prepared.document.sources!.filter { !beforeSources.contains($0.id) }
                .map { $0.sessionDirectory(in: root.directoryURL) }
            precondition(!staged.isEmpty && staged.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
            switch failure {
            case "lease": failureLease.invalidate()
            case "cancellation": withUnsafeCurrentTask { $0?.cancel() }
            case "timeout": try? await Task.sleep(for: .seconds(31))
            case "stale": model.style.padding += 0.01
            case "source_edit": sourceModel.style.padding += 0.01
            default: model.isEditingSource = true
            }
        }
        do {
            _ = try await agent.appendRecording(handle: handle, expectedRevision: failureRevision,
                projectID: sourceID, requestID: failureRequest, lease: failureLease)
            preconditionFailure("Append must reject a post-preparation \(failure) change")
        } catch is CancellationError {
            precondition(failure == "lease" || failure == "cancellation" || failure == "timeout")
        } catch let error as RecordingAgentOperationError {
            precondition(error.code == ((failure == "stale" || failure == "source_edit") ? "stale_revision" : "operation_unavailable"))
        }
        model.isEditingSource = false
        precondition(preparations == 1 && staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
            "A rejected append must remove all newly staged media")
        precondition(model.currentEditDocument.sources == before.sources && model.currentEditDocument.clips == before.clips)
        do {
            _ = try await agent.appendRecording(handle: handle, expectedRevision: failureRevision,
                projectID: sourceID, requestID: failureRequest, lease: RecordingAgentRequestLease())
            preconditionFailure("Failed request IDs cannot start another preparation")
        } catch {}
        precondition(preparations == 1)
        agent.appendPreparedForTesting = nil
    }
    #endif
    current = try agent.inspect(handle: handle)
    let access = RecordingAgentAccessController.shared
    await access.setEnabled(true)
    precondition(access.status == .ready)
    let configuration = try JSONSerialization.jsonObject(with: Data(access.clientConfiguration().utf8)) as! [String: Any]
    let servers = configuration["mcpServers"] as! [String: Any]
    let server = servers["bettershot"] as! [String: Any]
    let headers = server["headers"] as! [String: String]
    let authorization = headers["Authorization"]!
    let transport = HTTPClientTransport(endpoint: access.endpoint, configuration: .ephemeral,
        streaming: false, requestModifier: { request in
            var request = request
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            return request
        })
    let client = Client(name: "multi-source-agent-test", version: "1")
    _ = try await client.connect(transport: transport)
    let tools = try await client.listTools().tools
    precondition(tools.contains { $0.name == "append_recording" })
    let reorderTool = tools.first { $0.name == "reorder_clips" }!
    guard case let .object(schema) = reorderTool.inputSchema,
          case let .object(properties)? = schema["properties"],
          case let .object(clipSchema)? = properties["clipIds"] else {
        preconditionFailure("Reorder must advertise its typed array schema")
    }
    precondition(clipSchema["type"] == .string("array") && clipSchema["items"] == .object(["type": .string("string")]))
    let inspectRequest: RequestContext<CallTool.Result> = try await client.callTool(
        name: "inspect_timeline", arguments: ["handle": .string(handle.uuidString)])
    let inspected = try await inspectRequest.value
    guard case let .object(timeline)? = inspected.structuredContent,
          case let .array(sources)? = timeline["sources"] else {
        preconditionFailure("Inspection must expose the managed source catalog")
    }
    precondition(sources.count == 2)
    let reorderRequest: RequestContext<CallTool.Result> = try await client.callTool(name: "reorder_clips", arguments: [
        "handle": .string(handle.uuidString), "expectedRevision": .int(Int(current.revision)),
        "clipIds": .array(current.clips.map { .string($0.id.uuidString) })
    ])
    let reorderResult = try await reorderRequest.value
    precondition(reorderResult.isError != true && model.editRevision == current.revision)
    let appendRetryRequest: RequestContext<CallTool.Result> = try await client.callTool(name: "append_recording", arguments: [
        "handle": .string(handle.uuidString), "expectedRevision": .int(Int(initial.revision)),
        "projectId": .string(sourceID.uuidString), "requestId": .string(requestID.uuidString)
    ])
    let appendRetry = try await appendRetryRequest.value
    precondition(appendRetry.isError != true && model.editRevision == current.revision)
    #if DEBUG
    let disableRevision = model.editRevision
    let disableRequest = UUID()
    let existingSources = Set(model.projectSources!.map(\.id))
    var disableStaged: [URL] = []
    var releasePreparation: CheckedContinuation<Void, Never>?
    let (preparedStream, preparedSignal) = AsyncStream<Void>.makeStream()
    agent.appendPreparedForTesting = { prepared in
        disableStaged = prepared.document.sources!.filter { !existingSources.contains($0.id) }
            .map { $0.sessionDirectory(in: root.directoryURL) }
        await withCheckedContinuation { continuation in
            releasePreparation = continuation
            preparedSignal.yield(())
        }
    }
    let pendingHTTP = Task<CallTool.Result, Error> {
        let request: RequestContext<CallTool.Result> = try await client.callTool(name: "append_recording", arguments: [
            "handle": .string(handle.uuidString), "expectedRevision": .int(Int(disableRevision)),
            "projectId": .string(sourceID.uuidString), "requestId": .string(disableRequest.uuidString)
        ])
        return try await request.value
    }
    var preparedIterator = preparedStream.makeAsyncIterator()
    _ = await preparedIterator.next()
    await access.setEnabled(false)
    releasePreparation?.resume()
    do {
        _ = try await agent.appendRecording(handle: handle, expectedRevision: disableRevision,
            projectID: sourceID, requestID: disableRequest, lease: RecordingAgentRequestLease())
        preconditionFailure("Disabling Agent Access must revoke a prepared HTTP append")
    } catch is CancellationError {}
    _ = try? await pendingHTTP.value
    agent.appendPreparedForTesting = nil
    preparedSignal.finish()
    precondition(model.editRevision == disableRevision && !disableStaged.isEmpty)
    precondition(disableStaged.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    #else
    await access.setEnabled(false)
    #endif
    await client.disconnect()
    let exported = try await RecordingStudioExporter().export(model.makeExportConfiguration()) { _ in }
    defer { try? FileManager.default.removeItem(at: exported) }
    let exportedDuration = try await AVURLAsset(url: exported).load(.duration).seconds
    precondition(abs(exportedDuration - current.duration) < 0.05,
        "Agent-arranged clips must export through the production compositor")
    let saved = try agent.save(handle: handle, expectedRevision: current.revision)
    precondition(saved.saved)
    let savedDocument = model.currentEditDocument
    model.teardown()
    let reopened = RecordingStudioModel(url: root.directoryURL)
    await reopened.load()
    defer { reopened.teardown() }
    precondition(reopened.currentEditDocument == savedDocument)
    let sourceBytes = try Data(contentsOf: source.screenURL)
    precondition(sourceBytes == originalMovie, "Appending never changes original media")
    print("PASS agent multi-source append/retry/concurrent retry, source snapshot, reorder, trim, undo/redo, preview and save/reopen")
}
