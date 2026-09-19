# TourKit integration

Vendored Swift package from https://github.com/rampatra/TourKit at
`4f2b109506650151d87cd5e84bb9fe2623938781` (MIT; see LICENSE).

BetterShot uses TourSlideshowView in its existing resizable onboarding window.
Local adjustments: system-aware neutral colors, native primary button, accessible
back/skip controls, hidden decorative artwork, reduced-transparency support, and
150 ms page fades disabled under Reduce Motion. The sample executable/artwork is
omitted from the package manifest; upstream library and tests are retained.

When updating, compare the source against this revision and retain these small
accessibility adjustments. Run `swift test --package-path Vendor/TourKit` and
`make test`. App compiler settings remain unchanged.
