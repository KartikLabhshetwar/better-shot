import Foundation
import Security

@main
enum R2KeychainAccessCheck {
    @MainActor
    static func main() {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1",
                     "Run through scripts/run-checks.sh to keep the real Keychain isolated")
        let store = R2CredentialStore.shared
        precondition(store.keychainAccess == .empty && store.accessKeyID.isEmpty && store.secretAccessKey.isEmpty)
        store.accessKeyID = "test-only-key"
        precondition(store.keychainAccess == .blocked(errSecInteractionNotAllowed), "Tests cannot write to the Keychain")
        store.forgetStoredKeys()
        precondition(store.accessKeyID.isEmpty && store.keychainAccess == .empty)
        precondition(
            R2CredentialStore.access(of: [errSecSuccess, errSecSuccess]) == .stored,
            "two readable keys are stored"
        )
        precondition(
            R2CredentialStore.access(of: [errSecItemNotFound, errSecItemNotFound]) == .empty,
            "never having saved keys is empty, not blocked"
        )
        precondition(
            R2CredentialStore.access(of: [errSecAuthFailed, errSecItemNotFound]) == .blocked(errSecAuthFailed),
            "a cancelled keychain prompt is blocked, not empty"
        )
        precondition(
            R2CredentialStore.access(of: [errSecSuccess, errSecUserCanceled]) == .blocked(errSecUserCanceled),
            "one readable key does not excuse the other being locked"
        )
        precondition(
            R2CredentialStore.access(of: [errSecItemNotFound, errSecSuccess]) == .stored,
            "a half-written pair still counts as stored so the fields load"
        )
        precondition(
            R2CredentialStore.explain(errSecAuthFailed).contains("login password"),
            "the blocked message names the password macOS is actually asking for"
        )

        print("keychain access: empty, stored and blocked stay distinguishable")
    }
}
