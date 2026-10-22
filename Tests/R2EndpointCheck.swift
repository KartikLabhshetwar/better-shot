import Foundation

/// Answers every request locally, so nothing reaches Cloudflare, and records the host each one targeted.
final class R2StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hosts: [String] = []
    nonisolated(unsafe) static var reply: (status: Int, code: String) = (403, "AccessDenied")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.hosts.append(request.url?.host ?? "")
        let body = Data("<Error><Code>\(Self.reply.code)</Code><Message>\(Self.reply.code)</Message></Error>".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
enum R2EndpointCheck {
    @MainActor
    static func main() async {
        precondition(ProcessInfo.processInfo.environment["BETTERSHOT_TESTING"] == "1",
                     "Run through scripts/run-checks.sh to keep the real Keychain isolated")
        URLProtocol.registerClass(R2StubProtocol.self)

        func credentials(account: String = "acct", _ jurisdiction: R2Jurisdiction) -> R2Credentials {
            R2Credentials(accountID: account, bucket: "bucket", publicBaseURL: "https://share.example.com", useDirectLinks: false,
                          accessKeyID: "test-only-key", secretAccessKey: "test-only-secret", enabled: true, jurisdiction: jurisdiction)
        }

        func connectionError(_ credentials: R2Credentials) async -> String? {
            do {
                try await R2Uploader.testConnection(credentials: credentials)
                return nil
            } catch {
                return (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }

        let expected: [(R2Jurisdiction, String)] = [
            (.standard, "acct.r2.cloudflarestorage.com"),
            (.eu, "acct.eu.r2.cloudflarestorage.com"),
            (.us, "acct.us.r2.cloudflarestorage.com"),
            (.fedramp, "acct.fedramp.r2.cloudflarestorage.com"),
        ]
        for (jurisdiction, host) in expected {
            R2StubProtocol.hosts = []
            let message = await connectionError(credentials(jurisdiction)) ?? ""
            precondition(R2StubProtocol.hosts == [host], "\(jurisdiction) must reach \(host), got \(R2StubProtocol.hosts)")
            precondition(message.hasPrefix("AccessDenied: AccessDenied.") && message.contains("set Jurisdiction in Settings > Sharing") && message.contains(host),
                         "AccessDenied must point at the jurisdiction setting and name the host, got: \(message)")
        }

        R2StubProtocol.hosts = []
        _ = await connectionError(credentials(account: "acct.eu", .standard))
        precondition(R2StubProtocol.hosts == ["acct.eu.r2.cloudflarestorage.com"],
                     "the documented Account ID workaround must keep reaching the EU endpoint, got \(R2StubProtocol.hosts)")

        R2StubProtocol.reply = (404, "NoSuchKey")
        let missingProbe = await connectionError(credentials(.eu))
        precondition(missingProbe == nil, "a missing probe object at the EU endpoint is a working connection, got: \(missingProbe ?? "")")
        R2StubProtocol.reply = (403, "SignatureDoesNotMatch")
        let otherDenial = await connectionError(credentials(.eu)) ?? ""
        precondition(!otherDenial.contains("Jurisdiction"), "only AccessDenied suggests the jurisdiction, got: \(otherDenial)")

        let key = "bs_r2_jurisdiction"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = R2CredentialStore.shared
        precondition(store.jurisdiction == .standard, "an install without the setting keeps the standard endpoint")
        store.accountID = "acct"
        store.jurisdiction = .eu
        precondition(UserDefaults.standard.string(forKey: key) == "eu" && store.snapshot().host == "acct.eu.r2.cloudflarestorage.com",
                     "the chosen jurisdiction persists and reaches every request through the snapshot")
        store.accountID = ""
        UserDefaults.standard.removeObject(forKey: "bs_r2_accountID")

        print("R2 requests reach the bucket's jurisdiction endpoint and AccessDenied names it")
    }
}
