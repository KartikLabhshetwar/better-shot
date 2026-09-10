import Foundation

@main
struct OnboardingStateCheck {
    static func main() {
        let suite = "BetterShot-onboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        OnboardingState.prepareForLaunch(defaults: defaults)
        precondition(OnboardingState.shouldPresent(defaults: defaults), "Fresh installs see setup")
        defaults.set("custom shortcut", forKey: "bs_hotkey_1")
        defaults.set("existing look", forKey: "bs_defaultBeautifierConfig")
        OnboardingState.prepareForLaunch(defaults: defaults)
        precondition(OnboardingState.shouldPresent(defaults: defaults), "Launch migrations must not skip pending first-time setup")
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "bs_openEditorAfterRecording")
        OnboardingState.prepareForLaunch(defaults: defaults)
        precondition(!OnboardingState.shouldPresent(defaults: defaults), "Existing users without an onboarding marker skip setup, including stored false values")
        defaults.set("custom shortcut", forKey: "bs_hotkey_1")
        defaults.set("existing look", forKey: "bs_defaultBeautifierConfig")
        defaults.set(1, forKey: OnboardingState.seenVersionKey)
        OnboardingState.prepareForLaunch(defaults: defaults)
        precondition(!OnboardingState.shouldPresent(defaults: defaults), "Older onboarding completion must never trigger another introduction")
        OnboardingState.markSeen(defaults: defaults)
        precondition(!OnboardingState.shouldPresent(defaults: defaults), "Skip, close, and completion do not nag")
        precondition(defaults.string(forKey: "bs_hotkey_1") == "custom shortcut")
        precondition(defaults.string(forKey: "bs_defaultBeautifierConfig") == "existing look")
        OnboardingState.resumeAtPermissions(defaults: defaults)
        precondition(OnboardingState.shouldPresent(defaults: defaults))
        precondition(OnboardingState.shouldResumePermissions(defaults: defaults), "A permission restart returns to setup, even after an earlier completion")
        OnboardingState.markSeen(defaults: defaults)
        precondition(!OnboardingState.shouldResumePermissions(defaults: defaults), "Explicit dismissal clears pending setup")
        precondition(!OnboardingState.shouldPresent(defaults: defaults))
        defaults.set(OnboardingState.currentVersion + 1, forKey: OnboardingState.seenVersionKey)
        OnboardingState.markSeen(defaults: defaults)
        precondition(defaults.integer(forKey: OnboardingState.seenVersionKey) == OnboardingState.currentVersion + 1)
        precondition(!OnboardingState.shouldPresent(defaults: defaults), "Downgrades do not repeat the guide")
        print("Onboarding: first-run-only, existing-user migration, restart recovery, dismissal, preference preservation, and downgrade checks passed")
    }
}
