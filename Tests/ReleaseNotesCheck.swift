import Foundation

@main struct ReleaseNotesCheck {
    static func main() throws {
        let suite = "BetterShot-release-notes-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = """
        # Changelog
        ## [Unreleased]
        Ignore this
        ## [0.5.10] - 2026-10-01
        ### Added

        - Newest feature
        ## [0.5.4] - 2026-09-19
        ### Added

        - **3D** shots
        ## [0.5.3] - 2026-09-11
        - Older change
        """
        let notes = ReleaseNotes.parse(source)
        precondition(notes.map(\.version) == ["0.5.10", "0.5.4", "0.5.3"])
        precondition(notes[1].body == "### Added\n\n- **3D** shots")
        precondition(ReleaseNotes.parse("invalid").isEmpty)
        OnboardingState.prepareForLaunch(defaults: defaults)
        ReleaseNotes.prepareForLaunch(current: "0.5.4", defaults: defaults)
        precondition(ReleaseNotes.pending(in: notes, current: "0.5.4", defaults: defaults).isEmpty, "Fresh installs see only onboarding")
        defaults.removePersistentDomain(forName: suite)
        defaults.set(1, forKey: OnboardingState.seenVersionKey)
        ReleaseNotes.prepareForLaunch(current: "0.5.4", defaults: defaults)
        precondition(ReleaseNotes.pending(in: notes, current: "0.5.4", defaults: defaults) == [notes[1]], "Existing users without a release marker see the current update once")
        ReleaseNotes.markSeen("0.5.3", defaults: defaults)
        precondition(ReleaseNotes.pending(in: notes, current: "0.5.10", defaults: defaults) == Array(notes.prefix(2)), "Skipped releases remain visible; numeric version ordering handles .10")
        precondition(ReleaseNotes.pending(in: notes, current: "0.6.0", defaults: defaults).isEmpty, "Do not show old notes under a missing current release")
        ReleaseNotes.markSeen("0.5.10", defaults: defaults)
        precondition(ReleaseNotes.pending(in: notes, current: "0.5.10", defaults: defaults).isEmpty, "Dismissed updates do not repeat")
        ReleaseNotes.markSeen("0.5.4", defaults: defaults)
        precondition(defaults.string(forKey: ReleaseNotes.seenVersionKey) == "0.5.10", "Downgrades do not reset the marker")
        OnboardingState.resumeAtPermissions(defaults: defaults)
        precondition(OnboardingState.shouldPresent(defaults: defaults))
        ReleaseNotes.prepareForLaunch(current: "0.5.10", defaults: defaults)
        precondition(defaults.string(forKey: ReleaseNotes.seenVersionKey) == "0.5.10")
        let bundled = ReleaseNotes.parse(try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8))
        precondition(Set(bundled.map(\.version)).count == bundled.count)
        let versionInfo = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "version.json"))) as! [String: Any]
        precondition(bundled.contains { $0.version == versionInfo["version"] as? String }, "The app version must have release notes")
        print("PASS changelog parsing, fresh install, existing-user migration, skipped releases, dismissal, downgrade, and permission restart independence")
    }
}
