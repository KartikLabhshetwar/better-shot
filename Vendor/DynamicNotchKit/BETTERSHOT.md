# DynamicNotchKit in BetterShot

Upstream: https://github.com/mrkai77/DynamicNotchKit
Revision: cd0b3e52d537db115ad3a9d89601f20e0bee8d27
License: MIT (LICENSE; also bundled in Resources/Licenses).

Local integration patches provide synchronous presentation/dismissal and a window
configuration hook so capture exclusion is applied before showing the panel.
Screen changes preserve the chosen display. Hosting disables automatic window
sizing and passes clicks through transparent margins. Presentation is immediate;
no new motion or blur transitions are used. Floating surfaces respect Reduce
Transparency. The documentation-only plugin and media are omitted.
