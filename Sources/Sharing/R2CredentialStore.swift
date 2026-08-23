import Foundation
import Security

/// Immutable snapshot of R2 credentials for passing across actor boundaries.
struct R2Credentials: Sendable {
    let accountID: String
    let bucket: String
    let publicBaseURL: String
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
        static let enabled = "bs_r2_enabled"
        static let accessKeyID = "accessKeyID"
        static let secretAccessKey = "secretAccessKey"
    }

    private(set) var _accountID: String = ""
    private(set) var _bucket: String = ""
    private(set) var _publicBaseURL: String = ""
    private(set) var _enabled: Bool = false
    private(set) var _accessKeyID: String = ""
    private(set) var _secretAccessKey: String = ""

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
            Self.setKeychainItem(key: Keys.accessKeyID, value: newValue)
        }
    }

    var secretAccessKey: String {
        get { _secretAccessKey }
        set {
            _secretAccessKey = newValue
            Self.setKeychainItem(key: Keys.secretAccessKey, value: newValue)
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
            accessKeyID: _accessKeyID,
            secretAccessKey: _secretAccessKey,
            enabled: _enabled
        )
    }

    private init() {
        _accountID = defaults.string(forKey: Keys.accountID) ?? ""
        _bucket = defaults.string(forKey: Keys.bucket) ?? ""
        _publicBaseURL = defaults.string(forKey: Keys.publicBaseURL) ?? ""
        _enabled = defaults.bool(forKey: Keys.enabled)
        _accessKeyID = Self.getKeychainItem(key: Keys.accessKeyID) ?? ""
        _secretAccessKey = Self.getKeychainItem(key: Keys.secretAccessKey) ?? ""
    }

    private static func setKeychainItem(key: String, value: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
        ]

        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    private static func getKeychainItem(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
