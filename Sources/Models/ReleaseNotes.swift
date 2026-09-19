import Foundation

/// Bundled CHANGELOG.md is the release-content source; no network request at launch.
struct ReleaseNotes: Equatable {
    let version: String
    let body: String

    static func parse(_ markdown: String) -> [Self] {
        var releases: [Self] = []
        var version: String?
        var lines: [String] = []
        func append() {
            if let version {
                releases.append(Self(version: version, body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                append()
                version = nil
                lines = []
                if line.hasPrefix("## ["), let end = line.firstIndex(of: "]") {
                    let candidate = String(line[line.index(line.startIndex, offsetBy: 4)..<end])
                    if validVersion(candidate) { version = candidate }
                }
            } else if version != nil {
                lines.append(line)
            }
        }
        append()
        return releases
    }

    static func validVersion(_ version: String) -> Bool {
        version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    }

    static func newer(_ version: String, than previous: String) -> Bool {
        validVersion(version) && validVersion(previous) && version.compare(previous, options: .numeric) == .orderedDescending
    }

    static func pending(in releases: [Self], current: String, defaults: UserDefaults = .standard) -> [Self] {
        guard releases.contains(where: { $0.version == current }) else { return [] }
        guard let previous = defaults.string(forKey: seenVersionKey), validVersion(previous) else {
            return releases.filter { $0.version == current }
        }
        guard newer(current, than: previous) else { return [] }
        return releases.filter { newer($0.version, than: previous) && !newer($0.version, than: current) }
    }

    static let seenVersionKey = "bs_releaseNotesSeenVersion"

    static func prepareForLaunch(current: String, defaults: UserDefaults = .standard) {
        // New installs see the guide, not an update announcement too. Permission
        // restart recovery is independent and never resets this release marker.
        if defaults.object(forKey: seenVersionKey) == nil,
           defaults.integer(forKey: OnboardingState.seenVersionKey) == 0 {
            markSeen(current, defaults: defaults)
        }
    }

    static func markSeen(_ current: String, defaults: UserDefaults = .standard) {
        guard validVersion(current) else { return }
        if let previous = defaults.string(forKey: seenVersionKey), newer(previous, than: current) { return }
        defaults.set(current, forKey: seenVersionKey)
    }
}
