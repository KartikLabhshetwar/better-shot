import AppKit
import SwiftUI

/// Multi-recording roots expose arrangement here; effects belong to their authored source.
struct StudioSourcesInspector<ProjectControls: View>: View {
    @Bindable var model: RecordingStudioModel
    let onAddRecording: () -> Void
    let onEditRecording: (RecordingProjectSource) -> Void
    @ViewBuilder var projectControls: () -> ProjectControls

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recordings").font(.headline)
                    Spacer()
                    Button(action: onAddRecording) { Label("Add Recording", systemImage: "plus") }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Add recording from library")
                }
                Text("Edit a recording to change its background, cursor, camera, or effects. Changes apply to every clip using it.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.projectSources ?? []) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.displayName).font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(model.clipTimeline.segments.filter { $0.sourceID == source.id }.count) clips")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { onEditRecording(source) } label: {
                            Label("Edit Recording", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Edit recording \(source.displayName)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).studioEffectCard()
                }
                projectControls()
                Text("Trim, cut, change speed, and arrange clips on the main timeline.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
        .background(EditorChrome.workspace)
    }
}

struct StudioAddRecordingSheet: View {
    @Bindable var model: RecordingStudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var recordings: [RecordingSession] = []
    @State private var selectedURL: URL?
    @State private var task: Task<Void, Never>?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Recording").font(.title2.weight(.semibold))
            Text("Choose a recording from your BetterShot library. Its editable source is copied into this project.")
                .foregroundStyle(.secondary)
            if recordings.isEmpty {
                ContentUnavailableView("No other recordings", systemImage: "film.stack",
                    description: Text("Record another video in BetterShot, then open Add Recording again."))
            } else {
                List(selection: $selectedURL) {
                    ForEach(recordings, id: \.directoryURL) { session in
                        Label(session.displayName, systemImage: "film")
                            .tag(session.directoryURL)
                    }
                }
                .disabled(isPreparing)
                .accessibilityLabel("Recordings in BetterShot library")
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isPreparing { ProgressView().controlSize(.small); Text("Preparing recording…").font(.callout) }
                Spacer()
                Button("Cancel") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(errorMessage == nil ? "Add Recording" : "Retry") { append() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedURL == nil || isPreparing)
            }
        }
        .padding(24).frame(width: 540, height: 420)
        .interactiveDismissDisabled()
        .onAppear {
            recordings = RecordingSessionStore.allSessions()
                .filter { $0.directoryURL.standardizedFileURL != model.sessionURL.standardizedFileURL }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
        .onDisappear { task?.cancel() }
    }

    private func append() {
        guard let selectedURL, !isPreparing else { return }
        errorMessage = nil
        isPreparing = true
        let revision = model.editRevision
        task = Task {
            defer { isPreparing = false }
            do {
                guard RecordingSessionStore.allSessions().contains(where: { $0.directoryURL == selectedURL }) else {
                    throw RecordingAgentOperationError.unknownProject
                }
                let registry = StudioProjectRegistry.shared
                let snapshots = registry.snapshots(for: selectedURL)
                guard snapshots.count <= 1 else { throw RecordingAgentOperationError.ambiguousProject }
                let liveModel = snapshots.first.flatMap { registry.model(for: $0.handle) }
                if let liveModel {
                    guard liveModel.isLoaded, !liveModel.isSourceTransactionActive, !liveModel.sourceEditsInFlight,
                          !liveModel.isCroppingVideo, !liveModel.isEditingMasks,
                          !liveModel.clipSpeedDraft.hasActiveEdit else {
                        throw RecordingAgentOperationError.unavailable("Finish editing that recording in its Studio window, then retry.")
                    }
                }
                let incomingRevision = liveModel?.editRevision
                let prepared = try await model.prepareAppendRecording(from: selectedURL,
                    document: liveModel?.currentEditDocument)
                defer { prepared.discard() }
                guard !Task.isCancelled else { return }
                let latest = registry.snapshots(for: selectedURL)
                guard latest.count <= 1, latest.first?.handle == snapshots.first?.handle,
                      liveModel?.editRevision == incomingRevision,
                      liveModel?.isSourceTransactionActive != true, liveModel?.sourceEditsInFlight != true,
                      liveModel?.isCroppingVideo != true, liveModel?.isEditingMasks != true,
                      liveModel?.clipSpeedDraft.hasActiveEdit != true,
                      RecordingSessionStore.allSessions().contains(where: { $0.directoryURL == selectedURL }) else {
                    prepared.discard()
                    throw RecordingAgentOperationError.unavailable("The selected recording changed. Choose it again and retry.")
                }
                switch model.commitAppendRecording(prepared, expectedRevision: revision) {
                case .changed, .unchanged: dismiss()
                case .failed(let message): errorMessage = message
                }
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct StudioEditRecordingSheet: View {
    let root: RecordingStudioModel
    let source: RecordingProjectSource
    @State private var child: RecordingStudioModel
    @State private var task: Task<Void, Never>?
    @State private var isApplying = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var revision: UInt64

    init(root: RecordingStudioModel, source: RecordingProjectSource) {
        self.root = root
        self.source = source
        _revision = State(initialValue: root.editRevision)
        let document: RecordingEditDocument?
        do { document = try root.sourceDocumentForEditing(sourceID: source.id) }
        catch {
            document = nil
            _errorMessage = State(initialValue: error.localizedDescription)
        }
        _child = State(initialValue: RecordingStudioModel(
            url: source.sessionDirectory(in: root.sessionURL),
            embeddedDocument: document, isEmbeddedSource: true))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Recording: \(source.displayName)").font(.headline)
                    Text("Applies to every clip using this recording. Trim and arrange on the main timeline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isApplying { ProgressView().controlSize(.small) }
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                    .disabled(isApplying)
                Button("Apply", action: apply).keyboardShortcut(.defaultAction)
                    .disabled(!child.isLoaded || child.isCroppingVideo || child.isEditingMasks || isApplying)
            }.padding(16)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).padding(.horizontal, 16).padding(.bottom, 12)
            }
            Divider()
            RecordingStudioContent(model: child).disabled(isApplying)
        }
        .frame(minWidth: 960, minHeight: 640)
        .interactiveDismissDisabled()
        .task {
            guard errorMessage == nil else { return }
            await child.load()
            if Task.isCancelled { child.teardown() }
        }
        .onDisappear { task?.cancel(); child.teardown() }
    }

    private func cancel() {
        if child.hasUnsavedChanges || child.isCroppingVideo || child.isEditingMasks {
            let alert = NSAlert()
            alert.messageText = "Discard recording changes?"
            alert.informativeText = "Changes in this recording editor will be discarded. The project keeps its previous recording effects."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Keep Editing")
            alert.addButton(withTitle: "Discard Changes")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        dismiss()
    }

    private func apply() {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil
        task = Task {
            defer { isApplying = false }
            await child.waitForSourceEdits()
            guard !Task.isCancelled else { return }
            guard !child.sourceEditsInFlight else {
                errorMessage = "Audio or captions are still being prepared. Wait for them to finish, then retry."
                return
            }
            switch await root.applySourceDocument(child.currentEditDocument, sourceID: source.id, expectedRevision: revision) {
            case .changed:
                child.retainEmbeddedSourceFiles()
                dismiss()
            case .unchanged: dismiss()
            case .failed(let message): errorMessage = message
            }
        }
    }
}
