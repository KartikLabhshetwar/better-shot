import Foundation

@main
struct OnboardingStateCheck {
    static func main() {
        // A fixed suite, cleared first: a UUID name left one plist per run behind.
        let suite = "BetterShotTests-onboarding"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(OnboardingState.prepareForLaunch(defaults: defaults), "Only a fresh install initializes new defaults")
        precondition(OnboardingState.shouldPresent(defaults: defaults), "Fresh installs see setup")
        defaults.set("custom shortcut", forKey: "bs_hotkey_1")
        defaults.set("existing look", forKey: "bs_defaultBeautifierConfig")
        precondition(!OnboardingState.prepareForLaunch(defaults: defaults), "Pending setup on restart is not a new install")
        precondition(OnboardingState.shouldPresent(defaults: defaults), "Launch migrations must not skip pending first-time setup")
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "bs_openEditorAfterRecording")
        precondition(!OnboardingState.prepareForLaunch(defaults: defaults), "Legacy preferences identify an upgrade")
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
        OnboardingState.save(step: 1, defaults: defaults)
        precondition(OnboardingState.shouldPresent(defaults: defaults), "A permission restart returns to setup, even after an earlier completion")
        precondition(OnboardingState.savedStep(defaults: defaults) == 1, "Setup resumes at the step it left")
        OnboardingState.markSeen(defaults: defaults)
        precondition(defaults.object(forKey: OnboardingState.stepKey) == nil, "Explicit dismissal clears pending setup")
        precondition(!OnboardingState.shouldPresent(defaults: defaults))
        defaults.set(OnboardingState.currentVersion + 1, forKey: OnboardingState.seenVersionKey)
        OnboardingState.markSeen(defaults: defaults)
        precondition(defaults.integer(forKey: OnboardingState.seenVersionKey) == OnboardingState.currentVersion + 1)
        precondition(!OnboardingState.shouldPresent(defaults: defaults), "Downgrades do not repeat the guide")
        print("Onboarding: first-run-only, existing-user migration, step resume, dismissal, preference preservation, and downgrade checks passed")
    }
}
