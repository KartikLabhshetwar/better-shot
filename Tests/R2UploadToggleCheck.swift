import Foundation

@main
enum R2UploadToggleCheck {
    @MainActor
    static func main() async {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1",
                     "Run through scripts/run-checks.sh to keep the real Keychain isolated")
        let defaultsKeys = ["bs_r2_accountID", "bs_r2_bucket", "bs_r2_publicBaseURL", "bs_r2_enabled", "bs_r2_enabledMigrated"]
        defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        defer { defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:)) }

        // Keys stay in memory: the Keychain is blocked under BETTERSHOT_TESTING.
        // An http:// URL makes any upload that gets past the toggle fail locally, never on the network.
        let store = R2CredentialStore.shared
        precondition(UserDefaults.standard.object(forKey: "bs_r2_enabled") as? Bool == false,
                     "the Keychain is blocked here, so this process's own first launch has no keys and must migrate to a persisted, explicit OFF")
        precondition(UserDefaults.standard.bool(forKey: "bs_r2_enabledMigrated"),
                     "the first launch must record that the migration ran")
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

        precondition(R2CredentialStore.resolvedEnabled(stored: nil, hasKeys: true, hasMigrated: false),
                     "an upgrader's first launch (no stored value, no migration yet) turns sharing on once")
        precondition(!R2CredentialStore.resolvedEnabled(stored: nil, hasKeys: false, hasMigrated: false),
                     "a fresh install's first launch has no keys, so migration resolves to off")
        precondition(!R2CredentialStore.resolvedEnabled(stored: nil, hasKeys: true, hasMigrated: true),
                     "once migrated, a missing value must never re-infer on from keys added afterward")
        precondition(!R2CredentialStore.resolvedEnabled(stored: false, hasKeys: true, hasMigrated: true),
                     "a new user who adds keys later without touching the toggle stays off across relaunches")
        precondition(!R2CredentialStore.resolvedEnabled(stored: false, hasKeys: true, hasMigrated: false),
                     "an explicit off is never overwritten, even mid-migration")
        precondition(R2CredentialStore.resolvedEnabled(stored: true, hasKeys: false, hasMigrated: true),
                     "an explicit on is never overwritten, even with keys since removed")

        print("upload toggle: off refuses to upload, on proceeds, upgraders turn on once, new users stay off")
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
