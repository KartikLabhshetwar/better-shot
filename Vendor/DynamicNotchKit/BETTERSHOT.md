# DynamicNotchKit in BetterShot

Upstream: https://github.com/mrkai77/DynamicNotchKit
Revision: cd0b3e52d537db115ad3a9d89601f20e0bee8d27
Original package: MIT (LICENSE; also bundled in Resources/Licenses).

The local NotchShape.swift is copied from TheBoredTeam/boring.notch revision
99c26e418323d10e48886469fc9bd83900194bec, retaining its original author headers.
The interruptible presentation updates were adapted from that project's ContentView.
Those portions retain GPLv3, documented in BetterShot's
Resources/Licenses/BoringNotch.txt; the original package's MIT
notice does not replace their terms.

Local integration applies capture exclusion before showing a panel, supports
synchronous dismissal during capture/mode changes, and routes whole-surface
hover to BetterShot. Normal expansion/collapse uses a 140 ms ease-out transition,
disabled with Reduce Motion. No animated blur surfaces are used.
Expanded, compact, and floating surfaces are black with native dark controls.
Hosting disables automatic window sizing and passes clicks through transparent
margins. Screen changes preserve the chosen display; floating panels support
compact leading/trailing controls. The documentation-only plugin and media are
omitted. Capture, recording, preview actions, and media storage stay in BetterShot.
