import Foundation
import Security

/// Immutable snapshot of R2 credentials for passing across actor boundaries.
struct R2Credentials: Sendable {
    let accountID: String
    let bucket: String
    let publicBaseURL: String
    let useDirectLinks: Bool
    let accessKeyID: String
    let secretAccessKey: String
    let enabled: Bool

    var isConfigured: Bool {
        !accountID.isEmpty && !bucket.isEmpty && !publicBaseURL.isEmpty && !accessKeyID.isEmpty && !secretAccessKey.isEmpty
    }
}

/// Keychain-backed R2 config: secrets go to the Keychain, non-secret settings to UserDefaults.
@MainActor
@Observable
final class R2CredentialStore {
    static let shared = R2CredentialStore()

    private let defaults = UserDefaults.standard
    private static let keychainService = "com.bettershot.app.r2"

    private enum Keys {
        static let accountID = "bs_r2_accountID"
        static let bucket = "bs_r2_bucket"
        static let publicBaseURL = "bs_r2_publicBaseURL"
        static let useDirectLinks = "bs_r2_useDirectLinks"
        static let enabled = "bs_r2_enabled"
        static let accessKeyID = "accessKeyID"
        static let secretAccessKey = "secretAccessKey"
    }

    private(set) var _accountID: String = ""
    private(set) var _bucket: String = ""
    private(set) var _publicBaseURL: String = ""
    private(set) var _useDirectLinks: Bool = false
    private(set) var _enabled: Bool = false
    private(set) var _accessKeyID: String = ""
    private(set) var _secretAccessKey: String = ""
    private(set) var keychainAccess: KeychainAccess = .empty

    /// A blocked read means the keys are on disk but this build cannot open them, which looks nothing like never having set them.
    enum KeychainAccess: Equatable {
        case stored
        case empty
        case blocked(OSStatus)

        var isBlocked: Bool { if case .blocked = self { return true } else { return false } }
    }

    var accountID: String {
        get { _accountID }
        set {
            _accountID = newValue
            defaults.set(newValue, forKey: Keys.accountID)
        }
    }

    var bucket: String {
        get { _bucket }
        set {
            _bucket = newValue
            defaults.set(newValue, forKey: Keys.bucket)
        }
    }

    var publicBaseURL: String {
        get { _publicBaseURL }
        set {
            _publicBaseURL = newValue
            defaults.set(newValue, forKey: Keys.publicBaseURL)
        }
    }

    /// Off by default: an existing install keeps handing out viewer links until someone opts out.
    var useDirectLinks: Bool {
        get { _useDirectLinks }
        set {
            _useDirectLinks = newValue
            defaults.set(newValue, forKey: Keys.useDirectLinks)
        }
    }

    var enabled: Bool {
        get { _enabled }
        set {
            _enabled = newValue
            defaults.set(newValue, forKey: Keys.enabled)
        }
    }

    var accessKeyID: String {
        get { _accessKeyID }
        set {
            _accessKeyID = newValue
            keychainAccess = Self.setKeychainItem(key: Keys.accessKeyID, value: newValue)
        }
    }

    var secretAccessKey: String {
        get { _secretAccessKey }
        set {
            _secretAccessKey = newValue
            keychainAccess = Self.setKeychainItem(key: Keys.secretAccessKey, value: newValue)
        }
    }

    var isConfigured: Bool {
        !_accountID.isEmpty && !_bucket.isEmpty && !_publicBaseURL.isEmpty && !_accessKeyID.isEmpty && !_secretAccessKey.isEmpty
    }

    func snapshot() -> R2Credentials {
        R2Credentials(
            accountID: _accountID,
            bucket: _bucket,
            publicBaseURL: _publicBaseURL,
            useDirectLinks: _useDirectLinks,
            accessKeyID: _accessKeyID,
            secretAccessKey: _secretAccessKey,
            enabled: _enabled
        )
    }

    private init() {
        _accountID = defaults.string(forKey: Keys.accountID) ?? ""
        _bucket = defaults.string(forKey: Keys.bucket) ?? ""
        _publicBaseURL = defaults.string(forKey: Keys.publicBaseURL) ?? ""
        _useDirectLinks = defaults.bool(forKey: Keys.useDirectLinks)
        _enabled = defaults.bool(forKey: Keys.enabled)

        let accessKey = Self.getKeychainItem(key: Keys.accessKeyID)
        let secret = Self.getKeychainItem(key: Keys.secretAccessKey)
        _accessKeyID = accessKey.value ?? ""
        _secretAccessKey = secret.value ?? ""
        keychainAccess = Self.access(of: [accessKey.status, secret.status])
    }

    /// Wipes the stored keys so the next save writes a fresh item owned by this build, which is the only way past an access list a re-signed app no longer matches.
    func forgetStoredKeys() {
        Self.deleteKeychainItem(key: Keys.accessKeyID)
        Self.deleteKeychainItem(key: Keys.secretAccessKey)
        _accessKeyID = ""
        _secretAccessKey = ""
        keychainAccess = .empty
    }

    static func access(of statuses: [OSStatus]) -> KeychainAccess {
        if let blocked = statuses.first(where: { $0 != errSecSuccess && $0 != errSecItemNotFound }) {
            return .blocked(blocked)
        }
        return statuses.contains(errSecSuccess) ? .stored : .empty
    }

    static func explain(_ status: OSStatus) -> String {
        switch status {
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            "macOS asked for your Mac login password to unlock these keys and the request was cancelled."
        default:
            "The Keychain refused to open these keys (error \(status))."
        }
    }

    private static func setKeychainItem(key: String, value: String) -> KeychainAccess {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
        ]

        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = data
        return access(of: [SecItemAdd(newQuery as CFDictionary, nil)])
    }

    private static func deleteKeychainItem(key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
        ] as CFDictionary)
    }

    private static func getKeychainItem(key: String) -> (value: String?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return (nil, status)
        }

        return (String(data: data, encoding: .utf8), status)
    }
}
