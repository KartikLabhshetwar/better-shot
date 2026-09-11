import AppKit
import SwiftUI
@testable import BetterShot

// Uses the production views and models. Run through capture-editors.sh after make test.
@main
struct CaptureEditors: App {
    private let video = ProcessInfo.processInfo.environment["BETTERSHOT_MEDIA_KIND"] == "video"
    private let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BETTERSHOT_MEDIA_SOURCE"]!)

    var body: some Scene {
        WindowGroup(video ? "BetterShot Recording Editor" : "BetterShot Screenshot Editor") {
            Group {
                if video {
                    RecordingStudioWindow(url: .constant(source))
                } else {
                    AnnotationEditorWindow(url: .constant(source))
                }
            }
            .preferredColorScheme(.light)
        }
        .defaultSize(width: 1360, height: 860)
    }
}
