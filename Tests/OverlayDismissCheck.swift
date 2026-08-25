import Foundation

@main
enum OverlayDismissCheck {
    static let delayKey = "bs_overlayDismissDelay"

    static func main() {
        let range = AppPreferences.overlayDismissRange
        let never = AppPreferences.overlayDismissNever

        precondition(range.upperBound == never, "the slider must reach the sentinel, or Never is unreachable")
        precondition(AppPreferences.overlayDismisses(after: range.lowerBound), "the shortest delay must still auto-hide")
        precondition(AppPreferences.overlayDismisses(after: never - 1), "one step below the top is still a timed dismiss")
        precondition(!AppPreferences.overlayDismisses(after: never), "the top of the slider means the overlay stays up")
        precondition(!AppPreferences.overlayDismisses(after: never + 5), "a stored value above the sentinel must also stay up")

        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: delayKey)
        defer {
            if let original { defaults.set(original, forKey: delayKey) } else { defaults.removeObject(forKey: delayKey) }
        }

        defaults.removeObject(forKey: delayKey)
        precondition(AppPreferences.overlayDismissDelay == 5.0, "an unset preference must fall back to 5s")
        precondition(AppPreferences.overlayDismisses(after: AppPreferences.overlayDismissDelay), "a fresh install must still auto-hide the overlay")

        defaults.set(never, forKey: delayKey)
        precondition(AppPreferences.overlayDismissDelay == never, "the sentinel must survive a round trip through UserDefaults, not fall back to 5s")
        precondition(!AppPreferences.overlayDismisses(after: AppPreferences.overlayDismissDelay), "choosing Never must actually stop the dismiss timer")

        defaults.set(2.0, forKey: delayKey)
        precondition(AppPreferences.overlayDismisses(after: AppPreferences.overlayDismissDelay), "2s is a real delay, not Never")

        print("OverlayDismissCheck: the top of the Hide it after slider pins the overlay open")
    }
}
