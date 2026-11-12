import AppKit
import SwiftUI

struct RecordingAgentAccessSettingsTab: View {
    @State private var access = RecordingAgentAccessController.shared
    @State private var isChanging = false
    @State private var confirmRotation = false
    @State private var copyError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Allow local AI agents to edit recordings", isOn: Binding(
                    get: { access.enabled },
                    set: { changeAccess(to: $0) }
                ))
                .disabled(isChanging)
                statusRow
            } header: {
                Text("Agent Access")
            } footer: {
                Text("Off by default. When on, BetterShot accepts authenticated requests only from this Mac. Agents can inspect and edit open recording projects, save them, and start exports.")
            }

            Section {
                LabeledContent("Endpoint") {
                    Text(access.endpoint.absoluteString)
                        .textSelection(.enabled)
                        .font(.system(.callout, design: .monospaced))
                }
                HStack(spacing: 10) {
                    Button("Copy Client Configuration", systemImage: "doc.on.doc") {
                        copyConfiguration()
                    }
                    .disabled(access.status != .ready || isChanging)
                    .accessibilityLabel("Copy Agent Access client configuration")

                    Button("Rotate Token…", systemImage: "arrow.triangle.2.circlepath") {
                        confirmRotation = true
                    }
                    .disabled(access.status != .ready || isChanging)
                    .accessibilityLabel("Rotate Agent Access token")
                    Spacer(minLength: 0)
                }
                if let copyError {
                    Label(copyError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("Connect an agent")
            } footer: {
                Text("The copied configuration contains a private bearer token. Add it to your agent's MCP server settings and keep it on this Mac. Rotating the token disconnects clients using the old one.")
            }
        }
        .formStyle(.grouped)
        .alert("Rotate Agent Access token?", isPresented: $confirmRotation) {
            Button("Rotate Token", role: .destructive) { rotateToken() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Agents using the current configuration will need a new copy after rotation.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch access.status {
        case .off:
            Label("Off", systemImage: "circle.slash")
                .foregroundStyle(.secondary)
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting local endpoint…")
            }
        case .ready:
            Label("Ready on this Mac", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button(access.enabled ? "Retry" : "Retry Revoking Token") {
                    isChanging = true
                    Task {
                        if access.enabled { await access.retry() }
                        else { await access.setEnabled(false) }
                        isChanging = false
                    }
                }
            }
        }
    }

    private func changeAccess(to enabled: Bool) {
        isChanging = true
        copyError = nil
        Task {
            await access.setEnabled(enabled)
            isChanging = false
        }
    }

    private func rotateToken() {
        isChanging = true
        copyError = nil
        Task {
            await access.rotateToken()
            isChanging = false
        }
    }

    private func copyConfiguration() {
        do {
            let configuration = try access.clientConfiguration()
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(configuration, forType: .string) else {
                copyError = "Could not copy the configuration. Try again."
                return
            }
            copyError = nil
        } catch {
            copyError = error.localizedDescription
        }
    }
}
