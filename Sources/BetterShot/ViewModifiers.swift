//
//  ViewModifiers.swift
//  BetterShot
//
//  Reusable SwiftUI view modifiers and extensions.
//

import AppKit
import SwiftUI

// MARK: - Conditional Modifier

extension View {
    /// Apply a transform only when the condition is true.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - On Click Outside

/// Fires when a mouse-down occurs outside the view's bounds within the same window.
/// The click is not consumed - the target element still receives it.
private struct OnClickOutsideModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .background(ClickOutsideDetector(enabled: enabled, action: action))
    }
}

private struct ClickOutsideDetector: NSViewRepresentable {
    let enabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ClickOutsideNSView()
        view.action = action
        view.isMonitorEnabled = enabled
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ClickOutsideNSView else { return }
        view.action = action
        view.isMonitorEnabled = enabled
    }
}

private final class ClickOutsideNSView: NSView {
    var action: (() -> Void)?
    private var monitor: Any?

    var isMonitorEnabled: Bool = false {
        didSet {
            if isMonitorEnabled {
                installMonitor()
            } else {
                removeMonitor()
            }
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window else { return event }
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            if !self.bounds.contains(locationInView) {
                self.action?()
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension View {
    /// Fires when a click lands outside this view's bounds. The click is not consumed.
    func onClickOutside(enabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(OnClickOutsideModifier(enabled: enabled, action: action))
    }
}

// MARK: - On Escape Key

private struct OnEscapeKeyModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .background(EscapeKeyDetector(action: action))
    }
}

private struct EscapeKeyDetector: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EscapeKeyNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EscapeKeyNSView)?.action = action
    }
}

private final class EscapeKeyNSView: NSView {
    var action: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitor()
        } else {
            removeMonitor()
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Escape key
                self?.action?()
                return nil
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension View {
    /// Fires when the Escape key is pressed while this view is in a window.
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        modifier(OnEscapeKeyModifier(action: action))
    }
}

// MARK: - Sheet Style

extension View {
    /// Applies a consistent frosted-glass sheet presentation style.
    func bettershotSheetStyle() -> some View {
        self
            .presentationCornerRadius(12)
            .presentationBackground(.thinMaterial)
            .presentationBackgroundInteraction(.enabled)
    }
}

// MARK: - Window Accessor

/// Fires a callback whenever the SwiftUI view's hosting NSWindow changes.
private struct WindowAccessorModifier: ViewModifier {
    let onChange: (NSWindow?) -> Void

    func body(content: Content) -> some View {
        content.background(WindowAccessorView(onChange: onChange))
    }
}

private struct WindowAccessorView: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowAccessorNSView {
        let view = WindowAccessorNSView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: WindowAccessorNSView, context: Context) {
        nsView.onChange = onChange
    }
}

private final class WindowAccessorNSView: NSView {
    var onChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onChange?(window)
    }
}

extension View {
    /// Fires when this view's hosting NSWindow changes (attached or detached).
    func onWindowChange(_ onChange: @escaping (NSWindow?) -> Void) -> some View {
        modifier(WindowAccessorModifier(onChange: onChange))
    }
}

// MARK: - macOS 26 Availability Helpers

extension View {
    @ViewBuilder
    func scrollEdgeEffectSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }

    @ViewBuilder
    func safeAreaBarIfAvailable(edge: VerticalEdge, @ViewBuilder content: () -> some View) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, content: content)
        } else {
            safeAreaInset(edge: edge, content: content)
        }
    }
}
