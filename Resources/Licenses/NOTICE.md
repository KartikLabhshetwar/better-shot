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

The cancellable hover-open/close scheduling in
`Sources/Notch/NotchPresenter.swift` is adapted from TheBoredTeam and contributors’
`boringNotch/ContentView.swift` (`handleHover`), created by Harsh Vardhan Goswami
and modified by Richard Kunkli, at revision
99c26e418323d10e48886469fc9bd83900194bec:
https://github.com/TheBoredTeam/boring.notch/tree/99c26e418323d10e48886469fc9bd83900194bec

These adapted portions use GPL-3.0, reproduced in BoringNotch.txt. BetterShot keeps
its own capture/history actions and DynamicNotchKit surface; no Boring Notch
artwork, music services, or background integrations are included. The complete
application remains distributed under the combined AGPLv3 terms described above,
with corresponding source and build instructions in the BetterShot repository.
