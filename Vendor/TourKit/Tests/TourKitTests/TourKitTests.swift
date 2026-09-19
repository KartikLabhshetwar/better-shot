import Foundation
import SwiftUI
import Testing
@testable import TourKit

/// Helper used purely to obtain a distinct `Bundle` reference from `Bundle.main`
/// via `Bundle(for:)` for testing bundle-resolution logic.
private final class BundleToken {}

// MARK: - TourPage

@Suite("TourPage")
struct TourPageTests {
    @Test func initializationStoresAllValues() async throws {
        let bundle = Bundle(for: BundleToken.self)
        let id = UUID()
        let page = TourPage(
            id: id,
            imageName: "feature-search",
            imageBundle: bundle,
            title: "All New Spotlight Search",
            description: "Find what you need instantly.",
            tableName: "Onboarding",
            stringsBundle: bundle
        )

        #expect(page.id == id)
        #expect(page.imageName == "feature-search")
        #expect(page.imageBundle === bundle)
        #expect(page.title == LocalizedStringKey("All New Spotlight Search"))
        #expect(page.description == LocalizedStringKey("Find what you need instantly."))
        #expect(page.tableName == "Onboarding")
        #expect(page.stringsBundle === bundle)
    }

    @Test func defaultsAreNilForLocalizationHooks() async throws {
        let page = TourPage(
            imageName: "one",
            title: "Hi",
            description: "Hello"
        )

        #expect(page.imageBundle == nil)
        #expect(page.tableName == nil)
        #expect(page.stringsBundle == nil)
        #expect(page.resolvedStringsBundle == nil)
    }

    @Test func equalityAndHashingUseIdentity() async throws {
        let sharedId = UUID()
        let a = TourPage(id: sharedId, imageName: "one", title: "A", description: "Adesc")
        let b = TourPage(id: sharedId, imageName: "two", title: "B", description: "Bdesc")
        let c = TourPage(imageName: "one", title: "A", description: "Adesc")

        #expect(a == b, "Same id should be equal regardless of other fields")
        #expect(a != c, "Different ids should not be equal even with matching content")
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - Localization / Bundle resolution

@Suite("Localization")
struct LocalizationTests {
    @Test func resolvedStringsBundlePrefersStringsBundleOverImageBundle() async throws {
        let imageBundle = Bundle.main
        let stringsBundle = Bundle(for: BundleToken.self)

        #expect(imageBundle !== stringsBundle, "Test precondition: bundles must differ")

        let page = TourPage(
            imageName: "icon",
            imageBundle: imageBundle,
            title: "t",
            description: "d",
            stringsBundle: stringsBundle
        )

        #expect(page.resolvedStringsBundle === stringsBundle)
    }

    @Test func resolvedStringsBundleFallsBackToImageBundle() async throws {
        let imageBundle = Bundle(for: BundleToken.self)
        let page = TourPage(
            imageName: "icon",
            imageBundle: imageBundle,
            title: "t",
            description: "d"
        )

        #expect(page.resolvedStringsBundle === imageBundle)
    }

    @Test func resolvedStringsBundleIsNilWhenNothingProvided() async throws {
        let page = TourPage(imageName: "icon", title: "t", description: "d")
        #expect(page.resolvedStringsBundle == nil)
    }

    @Test func tableNameIsPreservedForLocalizedLookup() async throws {
        let page = TourPage(
            imageName: "icon",
            title: "hello_key",
            description: "bye_key",
            tableName: "TourStrings"
        )

        #expect(page.tableName == "TourStrings")
    }

    @Test @MainActor
    func slideshowCarriesLocalizationConfigIntoButtons() async throws {
        let bundle = Bundle(for: BundleToken.self)
        let view = TourSlideshowView(
            pages: [TourPage(imageName: "one", title: "T", description: "D")],
            continueButtonTitle: "onboarding.continue",
            finishButtonTitle: "onboarding.done",
            buttonTableName: "Onboarding",
            buttonBundle: bundle
        )

        #expect(view.continueButtonTitle == LocalizedStringKey("onboarding.continue"))
        #expect(view.finishButtonTitle == LocalizedStringKey("onboarding.done"))
        #expect(view.buttonTableName == "Onboarding")
        #expect(view.buttonBundle === bundle)
    }
}

// MARK: - PageIndicator (the slider dots)

@Suite("PageIndicator")
@MainActor
struct PageIndicatorTests {
    @Test func storesTotalPagesAndCurrentIndex() async throws {
        let indicator = PageIndicator(totalPages: 5, currentIndex: 2)
        #expect(indicator.totalPages == 5)
        #expect(indicator.currentIndex == 2)
    }

    @Test func rendersBodyForVariousPageCounts() async throws {
        for total in [1, 2, 3, 5, 10] {
            for current in 0..<total {
                let indicator = PageIndicator(totalPages: total, currentIndex: current)
                _ = indicator.body
            }
        }
    }

    @Test func rendersBodyWithZeroPagesWithoutCrashing() async throws {
        let indicator = PageIndicator(totalPages: 0, currentIndex: 0)
        _ = indicator.body
    }
}

// MARK: - TourSlideshowView: buttons, navigation, callbacks

@Suite("TourSlideshowView")
@MainActor
struct TourSlideshowViewTests {
    private func makePages(_ count: Int) -> [TourPage] {
        (0..<count).map {
            TourPage(imageName: "img\($0)", title: "Title \($0)", description: "Desc \($0)")
        }
    }

    // MARK: Button titles

    @Test func defaultButtonTitlesAreContinueAndDone() async throws {
        let view = TourSlideshowView(pages: makePages(3))
        #expect(view.continueButtonTitle == LocalizedStringKey("Continue"))
        #expect(view.finishButtonTitle == LocalizedStringKey("Done"))
    }

    @Test func customContinueAndGetStartedButtonTitles() async throws {
        let view = TourSlideshowView(
            pages: makePages(3),
            continueButtonTitle: "Next",
            finishButtonTitle: "Get Started"
        )
        #expect(view.continueButtonTitle == LocalizedStringKey("Next"))
        #expect(view.finishButtonTitle == LocalizedStringKey("Get Started"))
    }

    // MARK: isLastPage / initial state

    @Test func isLastPageForFirstIndexIsFalseWhenMultiplePages() async throws {
        let view = TourSlideshowView(pages: makePages(3))
        #expect(view.currentIndex == 0)
        #expect(view.isLastPage == false)
    }

    @Test func isLastPageForFinalInitialIndexIsTrue() async throws {
        let view = TourSlideshowView(pages: makePages(3), initialPageIndex: 2)
        #expect(view.isLastPage == true)
    }

    @Test func isLastPageForSinglePageTourIsTrue() async throws {
        let view = TourSlideshowView(pages: makePages(1))
        #expect(view.isLastPage == true)
    }

    // MARK: initialPageIndex clamping

    @Test func initialPageIndexIsClampedToValidRange() async throws {
        let pages = makePages(3)

        let negative = TourSlideshowView(pages: pages, initialPageIndex: -5)
        #expect(negative.currentIndex == 0)

        let inRange = TourSlideshowView(pages: pages, initialPageIndex: 1)
        #expect(inRange.currentIndex == 1)

        let overflow = TourSlideshowView(pages: pages, initialPageIndex: 99)
        #expect(overflow.currentIndex == 2)

        let empty = TourSlideshowView(pages: [])
        #expect(empty.currentIndex == 0)
    }

    @Test func clampedStaticHandlesEdgeCases() async throws {
        #expect(TourSlideshowView.clamped(0, pageCount: 0) == 0)
        #expect(TourSlideshowView.clamped(5, pageCount: 0) == 0)
        #expect(TourSlideshowView.clamped(-3, pageCount: 4) == 0)
        #expect(TourSlideshowView.clamped(2, pageCount: 4) == 2)
        #expect(TourSlideshowView.clamped(10, pageCount: 4) == 3)
    }

    // MARK: Continue / Get Started tap callbacks

    @Test func continueOnNonLastPageDoesNotInvokeFinishOrClose() async throws {
        final class Counter { var finish = 0; var close = 0 }
        let counter = Counter()
        let view = TourSlideshowView(
            pages: makePages(3),
            onFinish: { counter.finish += 1 },
            onClose: { counter.close += 1 }
        )

        view.advance()

        #expect(counter.finish == 0)
        #expect(counter.close == 0)
    }

    @Test func getStartedOnLastPageInvokesOnFinish() async throws {
        final class Counter { var finish = 0; var close = 0 }
        let counter = Counter()
        let view = TourSlideshowView(
            pages: makePages(3),
            initialPageIndex: 2,
            continueButtonTitle: "Next",
            finishButtonTitle: "Get Started",
            onFinish: { counter.finish += 1 },
            onClose: { counter.close += 1 }
        )

        view.advance()

        #expect(counter.finish == 1)
        #expect(counter.close == 0)
    }

    @Test func finishFallsBackToOnCloseWhenOnFinishIsNil() async throws {
        final class Counter { var close = 0 }
        let counter = Counter()
        let view = TourSlideshowView(
            pages: makePages(2),
            initialPageIndex: 1,
            finishButtonTitle: "Get Started",
            onClose: { counter.close += 1 }
        )

        view.advance()

        #expect(counter.close == 1)
    }

    // MARK: Rendering doesn't crash

    @Test func bodyRendersForPopulatedAndEmptyStates() async throws {
        _ = TourSlideshowView(pages: makePages(2)).body
        _ = TourSlideshowView(pages: []).body
    }
}
