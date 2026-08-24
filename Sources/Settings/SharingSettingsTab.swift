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
                Toggle("Upload captures to my own storage", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in save() }
            } header: {
                Text("Share Links")
            } footer: {
                Text("Off, BetterShot keeps everything on this Mac. On, sharing a capture uploads it to your Cloudflare R2 bucket and copies a link.")
            }

            Section {
                credentialField("Account ID", text: $accountID, prompt: "your-account-id")
                secureField("Access Key ID", text: $accessKeyID, prompt: "Access key ID")
                secureField("Secret Access Key", text: $secretAccessKey, prompt: "Secret access key")
                credentialField("Bucket", text: $bucket, prompt: "my-bucket")
                credentialField("Public Base URL", text: $publicBaseURL, prompt: "https://share.example.com")
            } header: {
                Text("Cloudflare R2")
            } footer: {
                Text("Create an API token in the Cloudflare dashboard under R2 \u{203A} Manage API Tokens, scoped to Object Read & Write. Your bucket needs public access turned on, or a custom domain bound to it, for links to open in a browser. Keys are stored in your login Keychain.")
            }
            .disabled(!enabled)

            Section {
                HStack(spacing: 12) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 44)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting || !enabled || !store.isConfigured)

                    switch testStatus {
                    case .idle:
                        EmptyView()
                    case .success:
                        Label("Connected. Share links are ready to use.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            } footer: {
                if enabled && !store.isConfigured {
                    Text("Fill in all five fields above to test the connection.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromStore() }
    }

    private func credentialField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, _ in save() }
        }
    }

    private func secureField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(label) {
            SecureField(label, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, _ in save() }
        }
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
