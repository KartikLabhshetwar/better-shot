import SwiftUI

struct SharingSettingsTab: View {
    @State private var store = R2CredentialStore.shared

    @State private var enabled = false
    @State private var accountID = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var bucket = ""
    @State private var publicBaseURL = ""

    @State private var isTesting = false
    @State private var testStatus: TestStatus = .idle

    private enum TestStatus: Equatable {
        case idle
        case success
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable sharing", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in save() }

                HStack(spacing: 12) {
                    Text("Account ID")
                        .frame(width: 130, alignment: .leading)
                    TextField("Account ID", text: $accountID, prompt: Text("your-account-id"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: accountID) { _, _ in save() }
                }

                HStack(spacing: 12) {
                    Text("Access Key ID")
                        .frame(width: 130, alignment: .leading)
                    SecureField("Access Key ID", text: $accessKeyID, prompt: Text("Access key ID"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: accessKeyID) { _, _ in save() }
                }

                HStack(spacing: 12) {
                    Text("Secret Access Key")
                        .frame(width: 130, alignment: .leading)
                    SecureField("Secret Access Key", text: $secretAccessKey, prompt: Text("Secret access key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: secretAccessKey) { _, _ in save() }
                }

                HStack(spacing: 12) {
                    Text("Bucket")
                        .frame(width: 130, alignment: .leading)
                    TextField("Bucket", text: $bucket, prompt: Text("my-bucket"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: bucket) { _, _ in save() }
                }

                HStack(spacing: 12) {
                    Text("Public Base URL")
                        .frame(width: 130, alignment: .leading)
                    TextField("Public Base URL", text: $publicBaseURL, prompt: Text("https://share.example.com"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: publicBaseURL) { _, _ in save() }
                }
            } header: {
                Text("Cloudflare R2")
            } footer: {
                Text("Create an API token in the Cloudflare dashboard under R2 > Manage API Tokens, scoped to Object Read & Write. The bucket needs public access enabled, or a custom domain bound to it, for share links to resolve in a browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 40)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting || !store.isConfigured)

                    switch testStatus {
                    case .idle:
                        EmptyView()
                    case .success:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .failed(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromStore() }
    }

    private func loadFromStore() {
        enabled = store.enabled
        accountID = store.accountID
        accessKeyID = store.accessKeyID
        secretAccessKey = store.secretAccessKey
        bucket = store.bucket
        publicBaseURL = store.publicBaseURL
    }

    private func save() {
        store.enabled = enabled
        store.accountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        store.accessKeyID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        store.secretAccessKey = secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        store.bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        store.publicBaseURL = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        testStatus = .idle
    }

    private func testConnection() async {
        isTesting = true
        testStatus = .idle
        do {
            try await R2Uploader.testConnection(credentials: store.snapshot())
            testStatus = .success
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            testStatus = .failed(message)
        }
        isTesting = false
    }
}
