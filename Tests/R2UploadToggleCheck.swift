import Foundation

@main
enum R2UploadToggleCheck {
    @MainActor
    static func main() async {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1",
                     "Run through scripts/run-checks.sh to keep the real Keychain isolated")
        let defaultsKeys = ["bs_r2_accountID", "bs_r2_bucket", "bs_r2_publicBaseURL", "bs_r2_enabled"]
        defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        defer { defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:)) }

        // Keys stay in memory: the Keychain is blocked under BETTERSHOT_TESTING.
        // An http:// URL makes any upload that gets past the toggle fail locally, never on the network.
        let store = R2CredentialStore.shared
        store.accountID = "test-account"
        store.bucket = "test-bucket"
        store.publicBaseURL = "http://share.example.com"
        store.accessKeyID = "test-only-key"
        store.secretAccessKey = "test-only-secret"
        precondition(store.isConfigured, "fixture credentials must count as configured")

        store.enabled = false
        precondition(!store.canShare, "uploads off must hide Share from the editors")
        let offID = UUID()
        let offMessage = await uploadError(itemID: offID)
        precondition(offMessage.contains("Uploads are off"),
                     "Share with Upload when I share off must not upload, got: \(offMessage)")
        precondition(R2Uploader.shared.uploadProgress[offID] == nil && !R2Uploader.shared.uploadingItems.contains(offID),
                     "a refused share never enters the uploader")

        store.enabled = true
        precondition(store.canShare, "configured and on must offer Share")
        let onMessage = await uploadError(itemID: UUID())
        precondition(onMessage != store.snapshot().shareBlocker && !onMessage.contains("Uploads are off"),
                     "uploads on must get past the toggle, got: \(onMessage)")

        precondition(R2CredentialStore.resolvedEnabled(stored: nil, hasKeys: true),
                     "0.4.3-0.5.6 saved keys without writing the toggle; those installs keep sharing")
        precondition(!R2CredentialStore.resolvedEnabled(stored: nil, hasKeys: false), "no keys, nothing to upload to")
        precondition(!R2CredentialStore.resolvedEnabled(stored: false, hasKeys: true), "an explicit off stays off")
        precondition(R2CredentialStore.resolvedEnabled(stored: true, hasKeys: true), "an explicit on stays on")

        print("upload toggle: off refuses to upload, on proceeds, legacy installs keep sharing")
    }

    @MainActor
    static func uploadError(itemID: UUID) async -> String {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("r2-toggle-check.png")
        do {
            _ = try await R2Uploader.shared.uploadShare(itemID: itemID, fileURL: file, title: nil)
            preconditionFailure("the fixture must never complete an upload")
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
