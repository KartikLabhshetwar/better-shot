# Cap 3D rendering attribution

The 3D camera and focus rendering portions identified below are adapted from
Cap Software, Inc., Cap commit c2ee42bda0159e51e031356689e00d7ac4d66d11:
https://github.com/CapSoftware/Cap/tree/c2ee42bda0159e51e031356689e00d7ac4d66d11

Copyright (c) 2023-present Cap Software, Inc.
Adaptation to Swift/Core Image/Metal: Copyright (c) 2026 Kartik Labhshetwar.

Upstream files: crates/rendering/src/camera3d.rs,
crates/rendering/src/shaders/camera3d.wgsl, and
crates/rendering/src/shaders/camera3d-blur.wgsl.
Adapted files: Sources/BetterShot/Recording3DShot.swift and
Sources/BetterShot/Recording3DBlurRenderer.swift. The rendering composition and
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
