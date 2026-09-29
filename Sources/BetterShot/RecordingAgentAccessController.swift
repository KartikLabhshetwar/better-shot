import Foundation
import Observation
import Security

private enum RecordingAgentTokenStore {
    private static let service = "com.bettershot.app.agent-access"
    private static let account = "bearer-token"
    private static let testing = ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1"
    @MainActor private static var testToken: String?

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @MainActor static func load() throws -> String? {
        if testing { return testToken }
        var request = query
        request[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw TokenError.keychain(status)
        }
        return token
    }

    @MainActor static func rotate() throws -> String {
        var random = Data(count: 32)
        let status = random.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw TokenError.keychain(status) }
        let token = random.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        if testing {
            testToken = token
            return token
        }
        let data = Data(token.utf8)
        let saved = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if saved == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = data
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw TokenError.keychain(added)
            }
        } else if saved != errSecSuccess {
            throw TokenError.keychain(saved)
        }
        return token
    }

    @MainActor static func revoke() throws {
        if testing { testToken = nil; return }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenError.keychain(status)
        }
    }

    private enum TokenError: LocalizedError {
        case keychain(OSStatus)
        var errorDescription: String? {
            "The login Keychain could not save the Agent Access token. Unlock it and retry."
        }
    }
}

enum RecordingAgentAccessStatus: Equatable {
    case off
    case starting
    case ready
    case failed(String)
}

@MainActor
@Observable
final class RecordingAgentAccessController {
    static let shared = RecordingAgentAccessController()
    static let enabledKey = "bs_agentAccessEnabled"
    private static let testing = ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1"

    private(set) var enabled: Bool
    private(set) var status: RecordingAgentAccessStatus = .off
    private var listener: RecordingAgentHTTPListener?
    private var generation: UInt64 = 0

    var endpoint: URL { RecordingAgentHTTPListener.endpoint }

    private init() {
        enabled = Self.testing ? false : UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func startIfEnabled() async {
        guard enabled else { return }
        generation &+= 1
        let current = generation
        await start(generation: current)
    }

    func setEnabled(_ isEnabled: Bool) async {
        generation &+= 1
        let current = generation
        enabled = isEnabled
        if !Self.testing { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
        if !isEnabled { status = .off }
        await stopListener()
        guard generation == current else { return }
        if isEnabled {
            await start(generation: current)
        } else {
            do {
                try RecordingAgentTokenStore.revoke()
                status = .off
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func retry() async {
        guard enabled else { return }
        generation &+= 1
        let current = generation
        await stopListener()
        guard generation == current else { return }
        await start(generation: current)
    }

    func rotateToken() async {
        guard enabled else { return }
        generation &+= 1
        let current = generation
        await stopListener()
        guard generation == current else { return }
        do {
            let token = try RecordingAgentTokenStore.rotate()
            await start(generation: current, token: token)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stopForTermination() async {
        generation &+= 1
        await stopListener()
        status = .off
    }

    func clientConfiguration() throws -> String {
        guard enabled, status == .ready, let token = try RecordingAgentTokenStore.load() else {
            throw AccessError.notReady
        }
        return """
        {"mcpServers":{"bettershot":{"url":"\(endpoint.absoluteString)","headers":{"Authorization":"Bearer \(token)"}}}}
        """
    }

    private func start(generation current: UInt64, token suppliedToken: String? = nil) async {
        status = .starting
        let token: String
        do {
            token = try suppliedToken ?? RecordingAgentTokenStore.load() ?? RecordingAgentTokenStore.rotate()
        } catch {
            guard generation == current else { return }
            status = .failed(error.localizedDescription)
            return
        }
        do {
            let started = try await RecordingAgentHTTPListener.start(token: token)
            guard enabled, generation == current else {
                await started.stop()
                return
            }
            listener = started
            status = .ready
        } catch {
            guard generation == current else { return }
            status = .failed("Could not start Agent Access on \(endpoint.host ?? "loopback"):\(RecordingAgentHTTPListener.port). Check whether another app is using the port, then retry.")
        }
    }

    private func stopListener() async {
        guard let listener else { return }
        self.listener = nil
        await listener.stop()
    }

    private enum AccessError: LocalizedError {
        case notReady
        var errorDescription: String? { "Turn on Agent Access and wait until it is ready." }
    }
}
