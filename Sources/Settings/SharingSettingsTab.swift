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
    @State private var confirmingClearKeys = false

    private enum TestStatus: Equatable {
        case idle
        case success
        case failed(String)
    }

    private static let dashboardURL = URL(string: "https://dash.cloudflare.com/?to=/:account/r2")!

    var body: some View {
        SettingsPage {
            SettingsCard {
                statusRow
            }

            SettingsGroup("Cloudflare R2") {
                credentialField("Account ID", text: $accountID, prompt: "From the R2 overview page", saving: \.accountID)
                SettingsDivider()
                SettingRow("Jurisdiction", caption: "Match the bucket's jurisdiction in the R2 dashboard. Most buckets have none.") {
                    Picker("Jurisdiction", selection: $store.jurisdiction) {
                        ForEach(R2Jurisdiction.allCases, id: \.self) { jurisdiction in
                            Text(jurisdiction.title).tag(jurisdiction)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: store.jurisdiction) { _, _ in testStatus = .idle }
                }
                SettingsDivider()
                secureField("Access Key ID", text: $accessKeyID, prompt: "From your API token", saving: \.accessKeyID)
                SettingsDivider()
                secureField("Secret Access Key", text: $secretAccessKey, prompt: "Shown once when the token is created", saving: \.secretAccessKey)
                SettingsDivider()
                credentialField("Bucket", text: $bucket, prompt: "my-bucket", saving: \.bucket)
                SettingsDivider()
                publicURLField
            } accessory: {
                Link("Open R2 Dashboard", destination: Self.dashboardURL)
                    .font(.callout)
            } footer: {
                Text("In the dashboard, create a bucket, turn on public access or bind a custom domain to it, then create an API token under R2 \u{203A} Manage API Tokens with Object Read & Write. Public Bucket URL is that public address. Your files are served from there, and it is the only place they are stored. Keys are saved to your login Keychain and never leave this Mac.")
            }

            SettingsGroup("Sharing") {
                VStack(alignment: .leading, spacing: 0) {
                    SettingRow("Connection", caption: store.isConfigured ? "Checks that BetterShot can upload to this bucket." : "Fill in all five fields first.") {
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
                    }
                    testStatusLabel
                }

                SettingsDivider()

                SettingToggle("Upload when I share", caption: "Sharing a screenshot or recording uploads it to this bucket and copies a link.", isOn: $enabled)
                    .disabled(!store.isConfigured)
                    .onChange(of: enabled) { _, isOn in store.enabled = isOn }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 0) {
                    SettingToggle("Copy direct file links", caption: "Link straight to the file in your bucket instead of a viewer page on bettershot.site.", isOn: $useDirectLinks)
                        // Not gated on isConfigured, which an empty URL already fails: a dead switch cannot explain itself.
                        .onChange(of: useDirectLinks) { _, isOn in directLinksToggled(isOn) }

                    if let directLinksProblem {
                        problemLabel(directLinksProblem)
                    }
                }
            } footer: {
                Text("A successful test turns uploads on for you. With uploads off, everything stays on this Mac. A viewer link shows the title, a poster and a download button, and hides the filename behind a random ID; a direct link is the raw file, filename and all.")
            }
        }
        .onAppear { loadFromStore() }
        .alert("Clear saved keys?", isPresented: $confirmingClearKeys) {
            Button("Clear Keys", role: .destructive) {
                store.forgetStoredKeys()
                accessKeyID = ""
                secretAccessKey = ""
                testStatus = .idle
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to enter your API keys again to share captures. Existing cloud shares stay available.")
        }
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

                Button("Clear Locked Keys", role: .destructive) {
                    confirmingClearKeys = true
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
        VStack(alignment: .leading, spacing: 0) {
            SettingRow("Public Bucket URL") {
                TextField("Public Bucket URL", text: $publicBaseURL, prompt: Text("https://share.example.com"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .focused($publicURLFocused)
                    .onChange(of: publicBaseURL) { _, _ in publicURLChanged() }
                    .onChange(of: publicURLFocused) { _, focused in
                        // Only once the user moves on, or "https:/" is an error mid-keystroke.
                        guard !focused else { return }
                        showPublicURLProblem = publicURLProblem != nil && publicURLProblem != .empty
                    }
            }

            if showPublicURLProblem, let publicURLProblem {
                problemLabel(publicURLProblem.message)
            }
        }
    }

    @ViewBuilder
    private var testStatusLabel: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.bottom, 11)
        case .failed(let message):
            problemLabel(message)
        }
    }

    private func problemLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 11)
    }

    private static func blockedMessage(for problem: ShareBundle.PublicBaseURLProblem) -> String {
        problem == .empty
            ? "Add the Public Bucket URL above first - a direct link points straight at it."
            : problem.message
    }

    private func publicURLChanged() {
        save(publicBaseURL, to: \.publicBaseURL)

        if useDirectLinks, publicURLProblem != nil {
            // Store first, so the echo below sees the new value.
            store.useDirectLinks = false
            useDirectLinks = false
            return
        }

        guard publicURLProblem == nil else { return }
        showPublicURLProblem = false
        directLinksProblem = nil
    }

    private func directLinksToggled(_ isOn: Bool) {
        // loadFromStore and the revert below echo back through here; neither is a tap.
        guard isOn != store.useDirectLinks else { return }

        guard isOn else {
            store.useDirectLinks = false
            directLinksProblem = nil
            return
        }

        if let publicURLProblem {
            directLinksProblem = Self.blockedMessage(for: publicURLProblem)
            showPublicURLProblem = publicURLProblem != .empty
            useDirectLinks = false
            return
        }

        directLinksProblem = nil
        store.useDirectLinks = true
    }

    private func credentialField(_ label: String, text: Binding<String>, prompt: String, saving key: ReferenceWritableKeyPath<R2CredentialStore, String>) -> some View {
        SettingRow(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onChange(of: text.wrappedValue) { _, value in save(value, to: key) }
        }
    }

    private func secureField(_ label: String, text: Binding<String>, prompt: String, saving key: ReferenceWritableKeyPath<R2CredentialStore, String>) -> some View {
        SettingRow(label) {
            SecureField(label, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onChange(of: text.wrappedValue) { _, value in save(value, to: key) }
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

        // Nothing changes on appear, so no handler would fire: reconcile the stored value here.
        if useDirectLinks, publicURLProblem != nil {
            store.useDirectLinks = false
            useDirectLinks = false
        }
    }

    /// Writes only the edited field, so typing in one field never rewrites the stored Keychain keys.
    private func save(_ value: String, to key: ReferenceWritableKeyPath<R2CredentialStore, String>) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store[keyPath: key] != trimmed else { return }
        store[keyPath: key] = trimmed
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
