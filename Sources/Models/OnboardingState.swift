import Foundation

/// Independent of app releases: change only when the introduction changes substantially.
enum OnboardingState {
    static let currentVersion = 2
    static let seenVersionKey = "bs_onboardingSeenVersion"
    static let resumePermissionsKey = "bs_onboardingResumePermissions"

    static func shouldPresent(defaults: UserDefaults = .standard) -> Bool {
        shouldResumePermissions(defaults: defaults) || defaults.integer(forKey: seenVersionKey) < currentVersion
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
