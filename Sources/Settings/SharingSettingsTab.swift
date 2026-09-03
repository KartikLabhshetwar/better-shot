import SwiftUI

struct SharingSettingsTab: View {
    @State private var store = R2CredentialStore.shared

    @State private var enabled = false
    @State private var accountID = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var bucket = ""
    @State private var publicBaseURL = ""
    @State private var useDirectLinks = false

    @State private var isTesting = false
    @State private var testStatus: TestStatus = .idle

    private enum TestStatus: Equatable {
        case idle
        case success
        case failed(String)
    }

    private static let dashboardURL = URL(string: "https://dash.cloudflare.com/?to=/:account/r2")!

    var body: some View {
        Form {
            Section {
                statusRow
            }

            Section {
                credentialField("Account ID", text: $accountID, prompt: "From the R2 overview page")
                secureField("Access Key ID", text: $accessKeyID, prompt: "From your API token")
                secureField("Secret Access Key", text: $secretAccessKey, prompt: "Shown once when the token is created")
                credentialField("Bucket", text: $bucket, prompt: "my-bucket")
                credentialField("Public Bucket URL", text: $publicBaseURL, prompt: "https://share.example.com")
            } header: {
                HStack {
                    Text("Cloudflare R2")
                    Spacer()
                    Link("Open R2 Dashboard", destination: Self.dashboardURL)
                        .font(.callout)
                        .textCase(.none)
                }
            } footer: {
                Text("In the dashboard, create a bucket, turn on public access or bind a custom domain to it, then create an API token under R2 \u{203A} Manage API Tokens with Object Read & Write. Public Bucket URL is that public address - your files are served from there, and it is the only place they are stored. Keys are saved to your login Keychain and never leave this Mac.")
            }

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
                    .disabled(isTesting || !store.isConfigured)

                    switch testStatus {
                    case .idle:
                        if !store.isConfigured {
                            Text("Fill in all five fields first.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    case .success:
                        Label("Connected", systemImage: "checkmark.circle.fill")
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

                Toggle(isOn: $enabled) {
                    Text("Upload when I share")
                    Text("Sharing a screenshot or recording uploads it to this bucket and copies a link.")
                }
                .disabled(!store.isConfigured)
                .onChange(of: enabled) { _, isOn in store.enabled = isOn }

                Toggle(isOn: $useDirectLinks) {
                    Text("Copy direct file links")
                    Text("Link straight to the file in your bucket instead of a viewer page on bettershot.site.")
                }
                .disabled(!store.isConfigured)
                .onChange(of: useDirectLinks) { _, isOn in store.useDirectLinks = isOn }
            } footer: {
                Text("A successful test turns uploads on for you. With uploads off, everything stays on this Mac. A viewer link shows the title, a poster and a download button, and hides the filename behind a random ID; a direct link is the raw file, filename and all.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromStore() }
    }

    @ViewBuilder
    private var statusRow: some View {
        if case .blocked(let status) = store.keychainAccess {
            VStack(alignment: .leading, spacing: 8) {
                Label("Your saved keys are locked", systemImage: "key.slash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)

                Text("\(R2CredentialStore.explain(status)) This happens after BetterShot is rebuilt or reinstalled. Clear the old keys and paste them in again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Clear Locked Keys") {
                    store.forgetStoredKeys()
                    accessKeyID = ""
                    secretAccessKey = ""
                    testStatus = .idle
                }
            }
            .padding(.vertical, 2)
        } else if !store.isConfigured {
            statusLabel(
                "Share links are not set up",
                detail: "Add your Cloudflare R2 details below and every share becomes a link.",
                systemImage: "icloud.slash",
                tint: .secondary
            )
        } else if !enabled {
            statusLabel(
                "Set up, uploads are off",
                detail: "Turn on Upload when I share below and sharing will copy a link.",
                systemImage: "icloud",
                tint: .secondary
            )
        } else {
            statusLabel(
                "Share links are ready",
                detail: "Share a capture from the editor and the link lands on your clipboard. Shared captures are listed under Library.",
                systemImage: "checkmark.icloud.fill",
                tint: .green
            )
        }
    }

    private func statusLabel(_ title: String, detail: String, systemImage: String, tint: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3)
        }
        .padding(.vertical, 2)
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
        useDirectLinks = store.useDirectLinks
    }

    private func save() {
        store.accountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        store.accessKeyID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        store.secretAccessKey = secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        store.bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        store.publicBaseURL = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        testStatus = .idle
        if !store.isConfigured {
            enabled = false
        }
    }

    private func testConnection() async {
        isTesting = true
        testStatus = .idle
        do {
            try await R2Uploader.testConnection(credentials: store.snapshot())
            testStatus = .success
            enabled = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            testStatus = .failed(message)
        }
        isTesting = false
    }
}
