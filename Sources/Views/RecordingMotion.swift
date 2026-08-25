import AppKit
import SwiftUI

/// Reduced-motion aware animation curves, checked live rather than cached.
@MainActor
enum RecordingMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var showHideSpring: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82)
    }

    static var pressRelease: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.28, dampingFraction: 1)
    }
}
