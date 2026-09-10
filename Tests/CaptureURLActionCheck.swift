import Foundation

@main
struct CaptureURLActionCheck {
    static func main() {
        for action in CaptureURLAction.allCases {
            assert(CaptureURLAction(url: URL(string: "bettershot://\(action.rawValue)")!) == action)
        }
        assert(CaptureURLAction(url: URL(string: "BETTERSHOT://CAPTURE/region")!) == .region)
        for value in [
            "https://capture/region", "bettershot:record", "bettershot:///record",
            "bettershot://unknown", "bettershot://capture", "bettershot://capture/region/extra",
            "bettershot://capture/region?output=/tmp/test.png", "bettershot://record#start",
            "bettershot://user@record", "bettershot://user:password@record", "bettershot://record:123",
            "bettershot://capture/../region", "bettershot://settings/anything"
        ] {
            assert(CaptureURLAction(url: URL(string: value)!) == nil, value)
        }
        print("CaptureURLActionCheck: URL routes and malformed URL rejection verified")
    }
}
