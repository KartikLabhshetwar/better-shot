import AppKit

enum LaunchContext {
    /// Read the launch event before deferring presentation to the next run-loop turn.
    static func isLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
