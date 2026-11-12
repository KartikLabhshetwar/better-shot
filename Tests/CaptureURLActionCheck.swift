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
        for path in ["/tmp/a.png", "/tmp/a.jpg", "/tmp/a.jpeg", "/tmp/A.PNG", "/tmp/a.heic"] {
            assert(OpenedImageFile.isEditable(URL(fileURLWithPath: path)), path)
            assert(CaptureURLAction(url: URL(fileURLWithPath: path)) == nil, path)
        }
        // Open With > Other… can pass any file.
        for path in ["/tmp/a.mov", "/tmp/a.txt", "/tmp/a.pdf", "/tmp/a"] {
            assert(!OpenedImageFile.isEditable(URL(fileURLWithPath: path)), path)
        }
        for value in ["https://example.com/a.png", "bettershot://capture/region"] {
            assert(!OpenedImageFile.isEditable(URL(string: value)!), value)
        }
        print("CaptureURLActionCheck: URL routes, opened image files, and malformed URL rejection verified")
    }
}
