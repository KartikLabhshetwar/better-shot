import Foundation

/// Completion is independent of app releases; updates never repeat completed setup.
enum OnboardingState {
    static let currentVersion = 2
    static let seenVersionKey = "bs_onboardingSeenVersion"
    static let resumePermissionsKey = "bs_onboardingResumePermissions"

    /// Run before launch migrations create preferences. Returns true only for a new install,
    /// not a permission restart or an upgrade with unfinished setup.
    @discardableResult
    static func prepareForLaunch(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: seenVersionKey) == nil else { return false }
        let existingUser = defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("bs_") || $0.hasPrefix("recordingStudio.")
        }
        defaults.set(existingUser ? currentVersion : 0, forKey: seenVersionKey)
        return !existingUser
    }

    static func shouldPresent(defaults: UserDefaults = .standard) -> Bool {
        shouldResumePermissions(defaults: defaults) || defaults.integer(forKey: seenVersionKey) == 0
    }

    static func shouldResumePermissions(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: resumePermissionsKey)
    }

    static func resumeAtPermissions(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: resumePermissionsKey)
    }

    /// Closing and skipping count as seen, so an optional introduction never nags.
    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(max(currentVersion, defaults.integer(forKey: seenVersionKey)), forKey: seenVersionKey)
        defaults.removeObject(forKey: resumePermissionsKey)
    }
}
