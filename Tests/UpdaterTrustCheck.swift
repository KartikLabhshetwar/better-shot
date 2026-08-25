import Foundation
import Security

@main
enum UpdaterTrustCheck {
    static func main() {
        let accepted = [
            "https://github.com/KartikLabhshetwar/better-shot/releases/download/v0.3.7/BetterShot-0.3.7_arm64.dmg",
            "https://github.com/KartikLabhshetwar/better-shot/releases/download/v4.0.0/BetterShot-4.0.0_x86_64.dmg",
        ]
        for raw in accepted {
            precondition(AppUpdater.isTrustedAssetURL(URL(string: raw)!), "a genuine release asset must be trusted: \(raw)")
        }

        let rejected = [
            "http://github.com/KartikLabhshetwar/better-shot/releases/download/v1/x.dmg",
            "https://githubb.com/KartikLabhshetwar/better-shot/releases/download/v1/x.dmg",
            "https://github.com.evil.tld/KartikLabhshetwar/better-shot/releases/download/v1/x.dmg",
            "https://evil.example/KartikLabhshetwar/better-shot/releases/download/v1/x.dmg",
            "https://github.com/attacker/better-shot/releases/download/v1/x.dmg",
            "https://github.com/KartikLabhshetwar/other-repo/releases/download/v1/x.dmg",
            "https://github.com/KartikLabhshetwar/better-shot/issues/1/x.dmg",
            "file:///tmp/x.dmg",
        ]
        for raw in rejected {
            precondition(!AppUpdater.isTrustedAssetURL(URL(string: raw)!), "untrusted asset URL slipped through: \(raw)")
        }

        precondition(
            AppUpdater.signatureRejection(for: URL(fileURLWithPath: "/nonexistent/Nope.app")) != nil,
            "a missing bundle must be rejected, not installed"
        )

        let systemApp = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        if FileManager.default.fileExists(atPath: systemApp.path) {
            precondition(
                AppUpdater.signatureRejection(for: systemApp) != nil,
                "a validly signed app from another team must be rejected: the Team ID pin is what stops a swapped bundle"
            )
            precondition(satisfies(systemApp, "anchor apple"), "plumbing check: the same API must be able to say yes, or the rejection above proves nothing")
        }

        print("UpdaterTrustCheck: release URLs pinned to this repo, and only this team's signature installs")
    }

    private static func satisfies(_ bundle: URL, _ requirement: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess,
              let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
