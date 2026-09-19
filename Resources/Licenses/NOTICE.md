# Cap 3D rendering attribution

The 3D camera and focus rendering portions identified below are adapted from
Cap Software, Inc., Cap commit c2ee42bda0159e51e031356689e00d7ac4d66d11:
https://github.com/CapSoftware/Cap/tree/c2ee42bda0159e51e031356689e00d7ac4d66d11

Copyright (c) 2023-present Cap Software, Inc.
Adaptation to Swift/Core Image/Metal: Copyright (c) 2026 Kartik Labhshetwar.

Upstream files: crates/rendering/src/camera3d.rs,
crates/rendering/src/shaders/camera3d.wgsl, and
crates/rendering/src/shaders/camera3d-blur.wgsl, and
apps/desktop/src/routes/editor/three-d.ts.
Adapted files: Sources/BetterShot/Recording3DShot.swift and
Sources/BetterShot/Recording3DBlurRenderer.swift. Scene selection/timing and the
native vector thumbnails in Sources/BetterShot/Recording3DInspector.swift also
adapt the editor's scene and preview geometry. The rendering composition and
zoom integration in RecordingStudioExporter.swift and RecordingStudioStyle.swift
also follow these upstream algorithms.

These adaptations are licensed under GNU Affero General Public License version 3
(AGPL-3.0-only). The complete upstream notice and license are in Cap.txt in this
folder. The application incorporating these portions must be conveyed under the
AGPLv3 terms, including corresponding source; the BSD license continues to apply
to the original BetterShot portions. This notice and license are bundled with the
application. No Cap trademarks or artwork are included.

Corresponding source and build instructions:
https://github.com/KartikLabhshetwar/better-shot
See CONTRIBUTING.md, project.yml, Makefile, and version.json in that repository.

## TourKit

The bundled TourKit Swift package is Copyright (c) 2026 Ram Patra, used under the
MIT license in TourKit.txt. Source: https://github.com/rampatra/TourKit at
4f2b109506650151d87cd5e84bb9fe2623938781. BetterShot's local appearance and
accessibility adjustments are documented in Vendor/TourKit/BETTERSHOT.md.


## Boring Notch

Notch UI and interaction code is copied/adapted from TheBoredTeam/boring.notch,
revision 99c26e418323d10e48886469fc9bd83900194bec:
https://github.com/TheBoredTeam/boring.notch/tree/99c26e418323d10e48886469fc9bd83900194bec

Credit: TheBoredTeam and Boring Notch contributors. The upstream shape credits
Kai Azim (original DynamicNotchKit) and Alexander (modifications); HoverButton
credits Kraigo. Original source headers are retained. Used under GPL version 3;
the complete upstream license is bundled in BoringNotch.txt.

- `boringNotch/components/Notch/NotchShape.swift` is copied into
  `Vendor/DynamicNotchKit/Sources/DynamicNotchKit/Views/NotchShape.swift`.
- `boringNotch/components/HoverButton.swift` is adapted in
  `Sources/Notch/BoringNotchHoverButton.swift` with accessible labels and shorter,
  reduced-motion-aware hover feedback.
- `boringNotch/ContentView.swift` supplies the cancellable hover-leave flow in
  `Sources/Notch/NotchPresenter.swift` and the interruptible spring in the vendored
  `DynamicNotch.swift`. BetterShot preserves capture exclusion, keyboard focus,
  native menu/sheet protection, and Reduce Motion; its own capture/editor/media
  actions replace the upstream music, calendar, and shelf integrations.

BetterShot modifications: Copyright (c) 2026 Kartik Labhshetwar. These copied and
adapted portions retain GPLv3 terms, not the original-code BSD license. Retain this
notice, the license, and corresponding source when distributing. The combined
application also incorporates the AGPLv3 Cap portions described above.
Corresponding source and build instructions are in the BetterShot repository
linked above (`CONTRIBUTING.md`, `project.yml`, `Makefile`, and `version.json`).
