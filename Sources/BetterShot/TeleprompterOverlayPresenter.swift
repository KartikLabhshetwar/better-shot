//
//  TeleprompterOverlayPresenter.swift
//  BetterShot
//
//  The teleprompter overlay. On a notched display it renders a Dynamic
//  Island-style extension that grows out of the hardware notch; elsewhere
//  it is a pill with the same spring motion. Both anchor flush to the
//  physical top of the screen, so a recording looks the same whether it
//  was made on a notched laptop or an external display.
//
//  Show/hide choreography: the collapsed state is geometrically identical
//  to the hardware notch (same width, height, and corner radii), so hiding
//  is a single spring back to that rect - once it lands, the window is
//  removed via the animation's completion callback. No timer chains, so
//  the window can never be yanked mid-flight, and every visible pixel of
//  the collapse is hidden behind the physical notch. Text lives inside the
//  same animatable clip shape, so it is swallowed by the collapse instead
//  of overhanging it.
//
//  Like every BetterShot overlay, the panel is excluded from captures
//  unless the "include app windows in captures" preference is on.
//

import AppKit
import CoreGraphics
import Observation
import SwiftUI

// MARK: - Geometry

/// Dynamic Island silhouette: concave "ear" curves at the top that blend
/// into the hardware notch cutout, convex rounded corners at the bottom.
struct TeleprompterNotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topCornerRadius, rect.width / 4, rect.height / 2)
        let bottom = min(bottomCornerRadius, rect.width / 4, rect.height - top)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Model

@Observable
final class TeleprompterOverlayModel {
    enum Mode {
        /// Extends the hardware notch; the collapsed state hides behind it.
        case notch(width: CGFloat, height: CGFloat)
        /// Hangs from the top edge on displays without a notch.
        case pill
    }

    var mode: Mode = .pill
    var isExpanded = false
    var layout: TeleprompterScriptLayout = .empty
    /// Display words spoken so far; the word at `count - 1` is live.
    var spokenWordCount = 0
    var visibleLineCount = 3
    var expandedWidth: CGFloat = 520

    static let lineHeight: CGFloat = 20
    static let textHorizontalPadding: CGFloat = 24
    static let font = Font.system(size: 13, weight: .medium)
    static let measuringFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    var textWidth: CGFloat {
        expandedWidth - Self.textHorizontalPadding * 2
    }

    var textAreaHeight: CGFloat {
        CGFloat(visibleLineCount) * Self.lineHeight
    }

    var expandedHeight: CGFloat {
        switch mode {
        case .notch(_, let notchHeight):
            notchHeight + 6 + textAreaHeight + 24
        case .pill:
            16 + textAreaHeight + 16
        }
    }

    var collapsedSize: CGSize {
        switch mode {
        case .notch(let width, let height):
            CGSize(width: width, height: height)
        case .pill:
            CGSize(width: 140, height: 12)
        }
    }
}

// MARK: - Presenter

@MainActor
final class TeleprompterOverlayPresenter {
    static let shared = TeleprompterOverlayPresenter()

    /// One spring for every phase - the "magnetic" feel comes from the
    /// expand, collapse, and scroll all settling with the same physics.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let scrollSpring = Animation.spring(response: 0.5, dampingFraction: 0.86)

    private let model = TeleprompterOverlayModel()
    private var panel: NSPanel?
    /// Invalidates a pending hide completion when a new show starts, so the
    /// old collapse can't orderOut the freshly shown overlay.
    private var hideGeneration = 0

    private init() {}

    func show(script: String, displayID: CGDirectDisplayID?) {
        guard let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main else { return }

        hideGeneration += 1
        model.mode = Self.notchMode(for: screen) ?? .pill
        model.visibleLineCount = BetterShotPreferences.recordingTeleprompterLineCount
        model.expandedWidth = 320
        model.layout = TeleprompterScriptLayout(
            script: script,
            maximumLineWidth: model.textWidth,
            font: TeleprompterOverlayModel.measuringFont
        )
        model.spokenWordCount = 0
        model.isExpanded = false
        guard !model.layout.isEmpty else { return }

        let panel = panel ?? makePanel()
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        position(panel, on: screen)
        panel.orderFrontRegardless()

        // The collapsed shape is already on screen (invisibly, behind the
        // notch); expanding on the next runloop tick lets SwiftUI animate
        // from that mounted state instead of popping in fully grown.
        DispatchQueue.main.async { [model] in
            withAnimation(Self.spring) {
                model.isExpanded = true
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        guard model.isExpanded else {
            panel.orderOut(nil)
            return
        }

        hideGeneration += 1
        let generation = hideGeneration
        withAnimation(Self.spring, completionCriteria: .logicallyComplete) {
            model.isExpanded = false
        } completion: { [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// Monotonic: live recognition can revise its guess downward, but the
    /// prompter never scrolls back at the reader.
    func updateProgress(spokenWordCount: Int) {
        model.spokenWordCount = max(model.spokenWordCount, spokenWordCount)
    }

    private static func notchMode(for screen: NSScreen) -> TeleprompterOverlayModel.Mode? {
        let notchHeight = screen.safeAreaInsets.top
        guard notchHeight > 0 else { return nil }

        var notchWidth: CGFloat = 200
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        }
        return .notch(width: notchWidth, height: notchHeight)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let hostingView = TeleprompterOverlayHostingView(
            rootView: TeleprompterOverlayView(model: model)
        )
        // The content springs its own width/height every frame (expand
        // collapse, line-scroll). Left at its default, NSHostingView fights
        // that by continuously re-deriving window min/max size constraints
        // from the mid-animation ideal size, which never settles - AppKit's
        // constraint-update watchdog eventually kills the app. The window
        // is sized explicitly via `position(_:on:)` instead, so bridging is
        // switched off and the hosting view just fills whatever frame the
        // window gives it.
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        // Sized for the fully expanded island plus shadow slack; the content
        // is top-center aligned so the shape grows in place.
        let width = model.expandedWidth + 80
        let height = model.expandedHeight + 40

        // Above the menu bar, flush with the physical top of the screen, in
        // both modes. Anchoring the pill to `visibleFrame` instead dropped it
        // by the menu bar's height, so the same recording sat flush on a
        // notched Mac and floated ~36pt lower on an external display. The
        // island is far narrower than the screen, so it covers only the
        // normally empty middle of the menu bar.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.setFrame(
            CGRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            ),
            display: false
        )
    }
}

private final class TeleprompterOverlayHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }
}

// MARK: - View

private struct TeleprompterOverlayView: View {
    let model: TeleprompterOverlayModel

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let expanded = model.isExpanded
        let size = expanded
            ? CGSize(width: model.expandedWidth, height: model.expandedHeight)
            : model.collapsedSize
        let shape = islandShape(expanded: expanded)

        return textArea
            .opacity(expanded ? 1 : 0)
            .frame(width: size.width, height: size.height, alignment: textAlignment)
            .background(shape.fill(Color.black))
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 18, y: 8)
    }

    /// In notch mode the text hangs below the hardware notch; the pill
    /// centers it vertically.
    private var textAlignment: Alignment {
        if case .notch = model.mode {
            return .bottom
        }
        return .center
    }

    private func islandShape(expanded: Bool) -> TeleprompterNotchShape {
        switch model.mode {
        case .notch:
            // Collapsed radii match the hardware cutout, so the resting
            // shape is invisible against it.
            TeleprompterNotchShape(
                topCornerRadius: expanded ? 12 : 2,
                bottomCornerRadius: expanded ? 14 : 9
            )
        case .pill:
            TeleprompterNotchShape(
                topCornerRadius: 0,
                bottomCornerRadius: expanded ? 16 : 6
            )
        }
    }

    // MARK: Text

    private var topLineIndex: Int {
        guard model.spokenWordCount > 0 else { return 0 }
        let activeWord = model.spokenWordCount - 1
        var activeLine = model.layout.lineIndex(forWord: activeWord)
        // Prompter rules: never spend a slot on text already read - the
        // line being spoken pins to the top and every slot below is
        // upcoming script. And since recognition trails the voice, reaching
        // a line's last word already scrolls the next line up, so the
        // reader is never stranded waiting for the recognizer.
        if model.layout.isLastWord(inLine: activeWord) {
            activeLine += 1
        }
        let maximumTop = max(0, model.layout.lines.count - model.visibleLineCount)
        return min(max(activeLine, 0), maximumTop)
    }

    private var textArea: some View {
        let lineHeight = TeleprompterOverlayModel.lineHeight
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.layout.lines.enumerated()), id: \.offset) { entry in
                lineText(entry.element)
                    .font(TeleprompterOverlayModel.font)
                    .lineLimit(1)
                    .frame(height: lineHeight, alignment: .leading)
            }
        }
        .frame(width: model.textWidth, alignment: .topLeading)
        .offset(y: -CGFloat(topLineIndex) * lineHeight)
        .animation(TeleprompterOverlayPresenter.scrollSpring, value: topLineIndex)
        .frame(width: model.textWidth, height: model.textAreaHeight, alignment: .top)
        .clipped()
        .mask(verticalFade)
        .padding(.bottom, textAlignment == .bottom ? 16 : 0)
    }

    private var verticalFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black, location: 0.1),
                .init(color: .black, location: 0.92),
                .init(color: .black.opacity(0.25), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func lineText(_ line: [TeleprompterScriptLayout.Word]) -> Text {
        var text = Text(verbatim: "")
        for (position, word) in line.enumerated() {
            let wordText = Text(verbatim: word.text)
                .foregroundStyle(color(forWord: word.index))
            text = position == 0 ? wordText : Text("\(text) \(wordText)")
        }
        return text
    }

    /// Reading palette: what's already been said falls away, the live word
    /// carries the karaoke accent, and everything ahead stays bright - the
    /// reader's eyes live in the upcoming text.
    private func color(forWord index: Int) -> Color {
        let spoken = model.spokenWordCount
        if index == spoken - 1 {
            return Color(cgColor: SubtitleBarMetrics.karaokeAccent)
        }
        if index < spoken {
            return .white.opacity(0.35)
        }
        return .white.opacity(0.95)
    }
}
