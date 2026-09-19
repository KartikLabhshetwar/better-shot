import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct TourPage: Identifiable, Hashable, @unchecked Sendable {
    public let id: UUID
    public let imageName: String
    public let imageBundle: Bundle?
    public let title: LocalizedStringKey
    public let description: LocalizedStringKey
    /// Optional `.strings` / `.xcstrings` table name used to look up `title` and
    /// `description`. When `nil`, the default `Localizable` table is used.
    public let tableName: String?
    /// Bundle used to look up localized strings for `title` and `description`.
    /// When `nil`, falls back to `imageBundle`, which is typically the caller's
    /// module bundle (e.g. `.module`).
    public let stringsBundle: Bundle?

    public init(
        id: UUID = UUID(),
        imageName: String,
        imageBundle: Bundle? = nil,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        tableName: String? = nil,
        stringsBundle: Bundle? = nil
    ) {
        self.id = id
        self.imageName = imageName
        self.imageBundle = imageBundle
        self.title = title
        self.description = description
        self.tableName = tableName
        self.stringsBundle = stringsBundle
    }

    /// Bundle used for localized string lookup. Prefers `stringsBundle`, then
    /// `imageBundle`, else `nil` (SwiftUI default).
    var resolvedStringsBundle: Bundle? {
        stringsBundle ?? imageBundle
    }

    public static func == (lhs: TourPage, rhs: TourPage) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct TourSlideshowView: View {
    let pages: [TourPage]
    /// Fixed content width of the slideshow card. The image region's height
    /// is `width / imageAspectRatio` and is locked once at init time, so
    /// every slide renders its artwork at exactly the same absolute size.
    let width: CGFloat
    let continueButtonTitle: LocalizedStringKey
    let finishButtonTitle: LocalizedStringKey
    let buttonTableName: String?
    let buttonBundle: Bundle?
    let onFinish: (() -> Void)?
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var cardBackground: Color { Color(white: colorScheme == .dark ? 0.10 : 0.96) }
    @State var currentIndex: Int

    public init(
        pages: [TourPage],
        width: CGFloat = 660,
        initialPageIndex: Int = 0,
        continueButtonTitle: LocalizedStringKey = "Continue",
        finishButtonTitle: LocalizedStringKey = "Done",
        buttonTableName: String? = nil,
        buttonBundle: Bundle? = nil,
        onFinish: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.pages = pages
        self.width = width
        self.continueButtonTitle = continueButtonTitle
        self.finishButtonTitle = finishButtonTitle
        self.buttonTableName = buttonTableName
        self.buttonBundle = buttonBundle
        self.onFinish = onFinish
        self.onClose = onClose
        _currentIndex = State(initialValue: Self.clamped(initialPageIndex, pageCount: pages.count))
    }

    /// Absolute pixel height of the image region, rounded to whole points
    /// so the artwork's edges never anti-alias against the card background.
    var imageHeight: CGFloat {
        (width / Self.imageAspectRatio).rounded()
    }

    public var body: some View {
        Group {
            if pages.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    imageSection
                    bottomPanel
                }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }
        }
        .frame(width: width)
        // Purely visual animation: drives the slide cross-fade and the
        // page-indicator's active-dot slide. Layout size never changes
        // because the hosting window is locked to the tallest slide.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: currentIndex)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No tour pages")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - Image section (top ~55%)

    /// Recommended tour artwork aspect ratio (width : height).
    ///
    /// `imageHeight = width / imageAspectRatio` is locked at init time so
    /// the image is rendered at a stable absolute size on every slide.
    static let imageAspectRatio: CGFloat = 16.0 / 10.0

    private var imageSection: some View {
        // Only the artwork participates in the cross-fade. The gradient
        // and page indicator are siblings of the transitioning image in
        // this ZStack so they stay at full opacity across slide changes;
        // if they were `.overlay`s on the image they'd be part of its
        // `.id + .transition(.opacity)` subtree and visibly fade out and
        // back in at the transition's midpoint.
        ZStack(alignment: .top) {
            image(for: pages[currentIndex])
                .resizable()
                .scaledToFit()
                .frame(width: width, height: imageHeight)
                .id(currentIndex)
                .transition(.opacity)
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: cardBackground.opacity(0.15), location: 0.25),
                    .init(color: cardBackground.opacity(0.45), location: 0.50),
                    .init(color: cardBackground.opacity(0.80), location: 0.75),
                    .init(color: cardBackground, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            PageIndicator(totalPages: pages.count, currentIndex: currentIndex)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            topControls
        }
        .frame(width: width, height: imageHeight)
    }

    // MARK: - Bottom panel (dark area with text + button)

    private var bottomPanel: some View {
        let currentPage = pages[currentIndex]

        return VStack(spacing: 0) {
            Text(currentPage.title, tableName: currentPage.tableName, bundle: currentPage.resolvedStringsBundle)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(currentPage.description, tableName: currentPage.tableName, bundle: currentPage.resolvedStringsBundle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Spacer(minLength: 24)

            primaryActionButton
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Per-slide identity so title, description, and button cross-fade
        // as one unit alongside the image above.
        .id(currentIndex)
        .transition(.opacity)
    }

    // MARK: - Top controls (back / close overlaying the image)

    private var topControls: some View {
        HStack {
            iconButton(systemName: "chevron.left") {
                goBack()
            }
            .opacity(currentIndex > 0 ? 1 : 0)
            .disabled(currentIndex == 0)
            .accessibilityHidden(currentIndex == 0)
            .accessibilityLabel("Previous page")

            Spacer()

            iconButton(systemName: "xmark") {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            }
            .accessibilityLabel("Skip tour")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    // MARK: - Primary CTA

    private var primaryActionButton: some View {
        Button(action: advance) {
            Text(
                isLastPage ? finishButtonTitle : continueButtonTitle,
                tableName: buttonTableName,
                bundle: buttonBundle
            )
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 180)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Icon button (glass circle)

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background {
                    if reduceTransparency {
                        Circle().fill(cardBackground)
                    } else if #available(macOS 26.0, iOS 26.0, *) {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                            }
                    } else {
                        Circle().fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    var isLastPage: Bool {
        currentIndex == pages.count - 1
    }

    static func clamped(_ index: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return max(0, min(index, pageCount - 1))
    }

    func advance() {
        if isLastPage {
            if let onFinish {
                onFinish()
            } else if let onClose {
                onClose()
            } else {
                dismiss()
            }
        } else {
            currentIndex += 1
        }
    }

    func goBack() {
        let newIndex = max(0, currentIndex - 1)
        guard newIndex != currentIndex else { return }
        currentIndex = newIndex
    }

    private func image(for page: TourPage) -> Image {
        if let bundle = page.imageBundle,
           let image = platformImage(named: page.imageName, in: bundle) {
            #if canImport(AppKit)
            return Image(nsImage: image)
            #elseif canImport(UIKit)
            return Image(uiImage: image)
            #else
            return Image(page.imageName, bundle: page.imageBundle)
            #endif
        }

        return Image(page.imageName, bundle: page.imageBundle)
    }

    #if canImport(AppKit)
    private func platformImage(named name: String, in bundle: Bundle) -> NSImage? {
        if let direct = bundle.image(forResource: name) {
            return direct
        }

        let nsName = NSImage.Name((name as NSString).deletingPathExtension)
        if let catalogImage = bundle.image(forResource: nsName) {
            return catalogImage
        }

        return loadImageFromResourceFile(named: name, in: bundle)
    }
    #elseif canImport(UIKit)
    private func platformImage(named name: String, in bundle: Bundle) -> UIImage? {
        if let direct = UIImage(named: name, in: bundle, compatibleWith: nil) {
            return direct
        }

        return loadImageFromResourceFile(named: name, in: bundle)
    }
    #endif

    #if canImport(AppKit)
    private func loadImageFromResourceFile(named name: String, in bundle: Bundle) -> NSImage? {
        if let resourceURL = resourceURL(named: name, in: bundle) {
            return NSImage(contentsOf: resourceURL)
        }
        return nil
    }
    #elseif canImport(UIKit)
    private func loadImageFromResourceFile(named name: String, in bundle: Bundle) -> UIImage? {
        guard let resourceURL = resourceURL(named: name, in: bundle),
              let data = try? Data(contentsOf: resourceURL) else {
            return nil
        }
        return UIImage(data: data)
    }
    #endif

    private func resourceURL(named name: String, in bundle: Bundle) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, let url = bundle.url(forResource: base, withExtension: ext) {
            return url
        }

        for candidateExt in ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"] {
            if let url = bundle.url(forResource: name, withExtension: candidateExt) {
                return url
            }
        }

        return nil
    }
}

#if canImport(AppKit)

/// Presents a `TourSlideshowView` inside a transparent, card-sized, draggable macOS window.
///
/// The window has no title bar, no visible chrome, a transparent background, and is sized
/// to match the tour card. It can be dragged around by its background and participates in
/// Mission Control / App Exposé like a normal window.
@MainActor
public final class TourKitWindowController {
    private final class HostWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private var window: NSWindow?
    private var windowDelegate: WindowDelegate?

    public init() {}

    /// Presents the tour window. If a window is already visible, it is brought to the front.
    ///
    /// The window automatically closes when the user taps the checkmark or finishes the tour.
    /// `onClose` and `onFinish` are invoked *before* the window is dismissed.
    @discardableResult
    public func present(
        pages: [TourPage],
        width: CGFloat = 660,
        continueButtonTitle: LocalizedStringKey = "Continue",
        finishButtonTitle: LocalizedStringKey = "Done",
        buttonTableName: String? = nil,
        buttonBundle: Bundle? = nil,
        onFinish: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) -> NSWindow {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return existing
        }

        let dismiss: () -> Void = { [weak self] in
            self?.close()
        }

        // Lock the window to the tallest slide's natural content height so
        // every slide renders in the same card size: the absolute image
        // region up top, and a bottom panel whose title, description, and
        // button pin to the top, centre, and bottom of the remaining space
        // respectively. Shorter slides simply get more breathing room.
        let imageHeight = width / TourSlideshowView.imageAspectRatio
        let maxPanelHeight = Self.maxBottomPanelHeight(
            pages: pages,
            width: width,
            continueButtonTitle: continueButtonTitle,
            finishButtonTitle: finishButtonTitle,
            buttonTableName: buttonTableName,
            buttonBundle: buttonBundle
        )
        let totalHeight = max(imageHeight + maxPanelHeight, 1)

        let rootView = TourSlideshowView(
            pages: pages,
            width: width,
            continueButtonTitle: continueButtonTitle,
            finishButtonTitle: finishButtonTitle,
            buttonTableName: buttonTableName,
            buttonBundle: buttonBundle,
            onFinish: {
                if let onFinish {
                    onFinish()
                } else {
                    onClose?()
                }
                dismiss()
            },
            onClose: {
                onClose?()
                dismiss()
            }
        )

        let contentSize = CGSize(width: width, height: totalHeight)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: contentSize)

        let window = HostWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.contentView = hosting
        window.center()

        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        window.delegate = delegate
        self.windowDelegate = delegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        return window
    }

    /// Returns the tallest bottom-panel natural height across all pages.
    ///
    /// The slideshow window is locked to `imageHeight + maxPanelHeight` so
    /// every slide renders inside the same card footprint: shorter slides
    /// simply get more vertical breathing room between their title,
    /// description, and button (which pin to top, centre, and bottom of the
    /// panel respectively).
    private static func maxBottomPanelHeight(
        pages: [TourPage],
        width: CGFloat,
        continueButtonTitle: LocalizedStringKey,
        finishButtonTitle: LocalizedStringKey,
        buttonTableName: String?,
        buttonBundle: Bundle?
    ) -> CGFloat {
        guard !pages.isEmpty else { return 0 }

        return pages.enumerated().map { index, page in
            let isLast = (index == pages.count - 1)
            let sizingView = TourBottomPanelSizingView(
                page: page,
                buttonTitle: isLast ? finishButtonTitle : continueButtonTitle,
                buttonTableName: buttonTableName,
                buttonBundle: buttonBundle
            )
            .frame(width: width)

            let hosting = NSHostingView(rootView: sizingView)
            hosting.layoutSubtreeIfNeeded()
            return hosting.fittingSize.height
        }.max() ?? 0
    }

    /// Closes the tour window if it is currently presented.
    public func close() {
        window?.close()
        window = nil
        windowDelegate = nil
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

/// A layout-equivalent stand-in for `TourSlideshowView`'s bottom panel used
/// purely to pre-measure its intrinsic height. Mirrors the real panel's
/// modifier chain so `NSHostingView.fittingSize` matches what the actual
/// slideshow will render at runtime.
private struct TourBottomPanelSizingView: View {
    let page: TourPage
    let buttonTitle: LocalizedStringKey
    let buttonTableName: String?
    let buttonBundle: Bundle?

    var body: some View {
        VStack(spacing: 6) {
            Text(page.title, tableName: page.tableName, bundle: page.resolvedStringsBundle)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.description, tableName: page.tableName, bundle: page.resolvedStringsBundle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(buttonTitle, tableName: buttonTableName, bundle: buttonBundle)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 220, height: 42)
                .padding(.top, 18)
        }
        .padding(.horizontal, 32)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }
}

#endif

public struct PageIndicator: View {
    let totalPages: Int
    let currentIndex: Int

    public init(totalPages: Int, currentIndex: Int) {
        self.totalPages = totalPages
        self.currentIndex = currentIndex
    }

    public var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? Color.accentColor : Color.primary.opacity(0.22))
                    .frame(width: index == currentIndex ? 24 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentIndex + 1) of \(max(totalPages, 1))")
    }
}
