import Foundation

// Mirror of the capture destination rules (Sources/Models/AppPreferences.swift).

enum CaptureDestination: String, CaseIterable {
    case saveAndCopy
    case saveOnly
    case copyOnly

    var savesFile: Bool { self != .copyOnly }
    var copiesToClipboard: Bool { self != .saveOnly }
}

let destinationKey = "bs_captureDestination"
let copyAfterSaveKey = "bs_copyAfterSave"

func captureDestination(in defaults: UserDefaults) -> CaptureDestination {
    if let raw = defaults.string(forKey: destinationKey),
       let destination = CaptureDestination(rawValue: raw) {
        return destination
    }
    let copiedAfterSave = defaults.object(forKey: copyAfterSaveKey) as? Bool ?? true
    return copiedAfterSave ? .saveAndCopy : .saveOnly
}

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

check(CaptureDestination.saveAndCopy.savesFile, "Save & Copy must write a file")
check(CaptureDestination.saveAndCopy.copiesToClipboard, "Save & Copy must reach the clipboard")
check(CaptureDestination.saveOnly.savesFile, "Save Only must write a file")
check(!CaptureDestination.saveOnly.copiesToClipboard, "Save Only must leave the clipboard alone")
check(!CaptureDestination.copyOnly.savesFile, "Copy Only must not write a file")
check(CaptureDestination.copyOnly.copiesToClipboard, "Copy Only must reach the clipboard")

check(
    CaptureDestination.allCases.contains { !$0.savesFile },
    "at least one destination must skip the save, otherwise Copy Only does nothing"
)

let suiteName = "CaptureDestinationCheck-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }

check(captureDestination(in: defaults) == .saveAndCopy, "a fresh install must save and copy")

defaults.set(false, forKey: copyAfterSaveKey)
check(
    captureDestination(in: defaults) == .saveOnly,
    "an install that had copy-after-save off must carry over as Save Only"
)

defaults.set(true, forKey: copyAfterSaveKey)
check(
    captureDestination(in: defaults) == .saveAndCopy,
    "an install that had copy-after-save on must carry over as Save & Copy"
)

defaults.set(CaptureDestination.copyOnly.rawValue, forKey: destinationKey)
check(
    captureDestination(in: defaults) == .copyOnly,
    "an explicit choice must win over the toggle it replaced"
)

defaults.set("nonsense", forKey: destinationKey)
check(
    captureDestination(in: defaults) == .saveAndCopy,
    "an unreadable stored value must fall back rather than lose the capture"
)

if failures.isEmpty {
    print("CaptureDestinationCheck: all assertions passed")
} else {
    failures.forEach { FileHandle.standardError.write(Data("FAIL: \($0)\n".utf8)) }
    exit(1)
}
