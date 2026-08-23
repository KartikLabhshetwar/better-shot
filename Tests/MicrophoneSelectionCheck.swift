import Foundation

@main
enum MicrophoneSelectionCheck {
    static func expect(_ actual: String?, _ expected: String?, _ label: String) {
        precondition(actual == expected, "\(label): expected \(String(describing: expected)), got \(String(describing: actual))")
    }

    static func main() {
        let builtIn = "BuiltInMicrophoneDevice"
        let iphone = "B4BA9672-iPhone"
        let usb = "USB-Podmic"
        let all = [iphone, builtIn, usb]

        expect(MicrophoneCatalog.resolveID(availableIDs: all, savedID: usb, systemDefaultID: builtIn), usb,
               "an explicit saved choice wins over the system default")
        expect(MicrophoneCatalog.resolveID(availableIDs: all, savedID: nil, systemDefaultID: builtIn), builtIn,
               "system default wins over enumeration order")
        expect(MicrophoneCatalog.resolveID(availableIDs: all, savedID: "unplugged", systemDefaultID: builtIn), builtIn,
               "a stale saved device falls back to the system default")
        expect(MicrophoneCatalog.resolveID(availableIDs: all, savedID: "", systemDefaultID: builtIn), builtIn,
               "an empty saved id is treated as unset")
        expect(MicrophoneCatalog.resolveID(availableIDs: all, savedID: nil, systemDefaultID: "gone"), iphone,
               "an unavailable system default falls back to the first device")
        expect(MicrophoneCatalog.resolveID(availableIDs: all, savedID: nil, systemDefaultID: nil), iphone,
               "no default at all falls back to the first device")
        expect(MicrophoneCatalog.resolveID(availableIDs: [], savedID: usb, systemDefaultID: builtIn), nil,
               "no microphones resolves to nothing rather than a phantom id")
        expect(MicrophoneCatalog.resolveID(availableIDs: all, savedID: nil, systemDefaultID: ""), iphone,
               "an empty default id is treated as unset")

        print("MicrophoneSelectionCheck: all assertions passed")
    }
}
