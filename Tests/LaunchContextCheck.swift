import AppKit

@main
struct LaunchContextCheck {
    static func main() {
        func event(_ id: AEEventID, launchReason: OSType? = nil) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: id,
                                              targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                              transactionID: AETransactionID(kAnyTransactionID))
            if let launchReason {
                event.setParam(NSAppleEventDescriptor(enumCode: launchReason), forKeyword: keyAEPropData)
            }
            return event
        }

        precondition(LaunchContext.isLoginItem(event(kAEOpenApplication, launchReason: keyAELaunchedAsLogInItem)),
                     "Login-item launches must suppress the automatic capture bar")
        precondition(!LaunchContext.isLoginItem(event(kAEOpenApplication)), "Manual launches keep their startup behavior")
        precondition(!LaunchContext.isLoginItem(nil), "A missing launch event keeps existing behavior")
        precondition(!LaunchContext.isLoginItem(event(kAEReopenApplication)), "Later reopening stays available")
        precondition(!LaunchContext.isLoginItem(event(kAEOpenApplication, launchReason: keyAELaunchedAsServiceItem)),
                     "Other launch reasons must not be mistaken for login")
        precondition(!LaunchContext.isLoginItem(event(kAEReopenApplication, launchReason: keyAELaunchedAsLogInItem)),
                     "The login marker only applies to the initial open event")
        print("Launch context: login, manual launch, missing event, reopen, and service checks passed")
    }
}
