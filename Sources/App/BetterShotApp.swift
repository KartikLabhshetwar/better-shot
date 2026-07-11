import SwiftUI

enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}

@main
struct BetterShotApp: App {
    @NSApplicationDelegateAdaptor(BetterShotDelegate.self) var delegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}
