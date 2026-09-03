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

    @FocusState private var publicURLFocused: Bool
    @State private var showPublicURLProblem = false
    @State private var directLinksProblem: String?

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
                publicURLField
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
                // Deliberately not gated on isConfigured, which an empty Public Bucket URL
                // already fails: a dead switch cannot explain why it will not turn on.
                .onChange(of: useDirectLinks) { _, isOn in directLinksToggled(isOn) }

                if let directLinksProblem {
                    Label(directLinksProblem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    private var publicURLProblem: ShareBundle.PublicBaseURLProblem? {
        ShareBundle.validatePublicBaseURL(publicBaseURL)
    }

    private var publicURLField: some View {
        LabeledContent("Public Bucket URL") {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Public Bucket URL", text: $publicBaseURL, prompt: Text("https://share.example.com"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($publicURLFocused)
                    .onChange(of: publicBaseURL) { _, _ in publicURLChanged() }
                    .onChange(of: publicURLFocused) { _, focused in
                        // Judge the field only once the user moves on. Flagging while they
                        // type would call "https:/" a mistake mid-keystroke. An empty field
                        // is not a mistake yet either - the toggle below is what insists on it.
                        guard !focused else { return }
                        showPublicURLProblem = publicURLProblem != nil && publicURLProblem != .empty
                    }

                if showPublicURLProblem, let publicURLProblem {
                    Label(publicURLProblem.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Says what is blocked, not just what is wrong. The field's own message reads
    /// oddly under a switch, where the question is why the switch will not stay on.
    private static func blockedMessage(for problem: ShareBundle.PublicBaseURLProblem) -> String {
        problem == .empty
            ? "Add the Public Bucket URL above first - a direct link points straight at it."
            : problem.message
    }

    private func publicURLChanged() {
        save()

        // Direct links are built from this address and nothing else. Leaving the switch
        // on while it is unusable would promise a link the uploader cannot build, so it
        // goes off on its own. The switch moving is the feedback; the message below is
        // reserved for a tap, where the user has actually asked for something.
        if useDirectLinks, publicURLProblem != nil {
            // Store first: the assignment below echoes into directLinksToggled, which
            // compares against the store to tell a real tap from an echo.
            store.useDirectLinks = false
            useDirectLinks = false
            return
        }

        guard publicURLProblem == nil else { return }
        showPublicURLProblem = false
        directLinksProblem = nil
    }

    private func directLinksToggled(_ isOn: Bool) {
        // loadFromStore and the revert below both echo back through onChange.
        // Neither is the user pressing the switch.
        guard isOn != store.useDirectLinks else { return }

        guard isOn else {
            store.useDirectLinks = false
            directLinksProblem = nil
            return
        }

        // A direct link is built straight from this field, so an unusable address has to
        // be caught here rather than at share time, when the capture is already gone.
        if let publicURLProblem {
            directLinksProblem = Self.blockedMessage(for: publicURLProblem)
            showPublicURLProblem = publicURLProblem != .empty
            useDirectLinks = false
            return
        }

        directLinksProblem = nil
        store.useDirectLinks = true
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

        // A stored "on" can outlive the address it depends on, because the URL may have
        // been cleared in an earlier session. Nothing changes on appear, so no handler
        // would fire: reconcile here or the switch shows on against an empty field.
        // Silently - an error on a pane the user just opened is scolding, not helping.
        if useDirectLinks, publicURLProblem != nil {
            store.useDirectLinks = false
            useDirectLinks = false
        }
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
