import Foundation

@main
enum ShareLinkCheck {
    static func expect(_ condition: Bool, _ label: String) {
        precondition(condition, label)
    }

    static func decodeBase64URL(_ value: String) -> String? {
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func checkSlug() {
        let id = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let slug = ShareBundle.slug(for: id)
        expect(slug.count == 22, "slug should be 22 characters, got \(slug.count)")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        expect(slug.unicodeScalars.allSatisfy { allowed.contains($0) }, "slug is not URL-safe: \(slug)")
        expect(ShareBundle.slug(for: id) == slug, "slug should be stable for the same UUID")
        expect(ShareBundle.slug(for: UUID()) != slug, "slug should differ for a different UUID")
        expect(ShareBundle.objectPrefix(id: slug) == "s/\(slug)/", "unexpected object prefix")
    }

    static func checkPageURL() {
        let slug = "abcDEF-123_xyz"
        expect(ShareBundle.pageURL(id: slug, publicBaseURL: "http://cdn.example.com") == nil, "http origins must be rejected")
        expect(ShareBundle.pageURL(id: slug, publicBaseURL: "") == nil, "empty origins must be rejected")

        guard let url = ShareBundle.pageURL(id: slug, publicBaseURL: "https://cdn.example.com/") else {
            fatalError("an https origin should produce a share URL")
        }
        expect(url.absoluteString.hasPrefix("\(ShareBundle.pageBaseURL)/s/\(slug)?b="), "unexpected share URL: \(url)")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let encoded = components?.queryItems?.first(where: { $0.name == "b" })?.value else {
            fatalError("the share URL should carry a b query item")
        }
        expect(!encoded.contains("+") && !encoded.contains("/") && !encoded.contains("="), "b must be base64url: \(encoded)")
        expect(decodeBase64URL(encoded) == "https://cdn.example.com", "b should round-trip to the trimmed origin")
    }

    static func checkManifestEncoding() throws {
        let manifest = ShareManifest(
            version: ShareManifest.currentVersion,
            id: "abc123",
            kind: "video",
            title: "Standup",
            media: "clip.mp4",
            poster: ShareBundle.posterFilename,
            mimeType: "video/mp4",
            width: 1920,
            height: 1080,
            durationSeconds: 12.5,
            byteSize: 4096,
            createdAt: "2026-08-24T10:00:00Z",
            appVersion: nil
        )

        let data = try JSONEncoder().encode(manifest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("manifest should encode to a JSON object")
        }

        expect(json["appVersion"] == nil, "nil fields must be omitted so the web schema stays optional-clean")
        expect(json["version"] as? Int == 1, "version must match the web SHARE_MANIFEST_VERSION")
        expect(json["kind"] as? String == "video", "kind must be video or image")
        expect(json["media"] as? String == "clip.mp4", "media must be a relative filename, not a URL")
        expect(json["poster"] as? String == "poster.jpg", "poster must be the sidecar filename")

        let expectedKeys: Set<String> = [
            "version", "id", "kind", "title", "media", "poster",
            "mimeType", "width", "height", "durationSeconds", "byteSize", "createdAt",
        ]
        expect(Set(json.keys) == expectedKeys, "manifest keys drifted from the web contract: \(Set(json.keys))")
    }

    static func checkSanitizedFilename() {
        expect(ShareBundle.sanitizedFilename("My Recording (1).mp4") == "My-Recording--1-.mp4", "unexpected sanitization")
        expect(!ShareBundle.sanitizedFilename("../../etc/passwd").contains("/"), "path separators must not survive")
        expect(ShareBundle.sanitizedFilename("") == "capture", "empty names need a fallback")
    }

    static func main() throws {
        checkSlug()
        checkPageURL()
        try checkManifestEncoding()
        checkSanitizedFilename()
        print("ShareLinkCheck: all assertions passed")
    }
}
