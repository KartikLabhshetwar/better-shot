# Export performance

## Cap comparison — 2026-09-11

Inspected the local Cap checkout at `e23d4c619`, particularly
`crates/export/src/mp4.rs`, `apps/desktop/src/routes/editor/ExportPage.tsx`,
and its screenshot export paths. Cap's MP4 pipeline uses NV12 GPU frames,
IOSurface input to VideoToolbox, and bounded queues between rendering and
encoding. Its checked-in export UI defaults to **720p, 30 fps**; BetterShot's
existing default is original resolution at 60 fps. Default-setting comparisons
therefore mix rendering speed with very different workloads. Cap itself was
not benchmarked in this comparison.

BetterShot now applies that architecture through native Core Image and
AVFoundation, with no additional dependencies:

- Screen, camera, scaling, temporal blur, and redaction stay on the GPU through
  an IOSurface-backed NV12 encoder buffer.
- Cursor/text overlays use pooled shared buffers. A sampled intermediate
  implementation spent most of its active compositor CPU time uploading and
  compressing full-canvas CGImage textures; shared overlays remove that copy.
- Three frames can be in flight, overlapping decoding, GPU work, and encoding.
  Input images remain retained until their GPU task completes, including on
  cancellation. Static decoration and source-dependent mask work are cached.
- Export and share keep using the same compositor and saved-render cache.
  Native Export Options and Recording settings expose 30/60 fps; missing
  fields in older projects still mean 60 fps. The frame clock and shutter use
  the same setting.
- Rendered buffers and encoded movies explicitly agree on sRGB transfer and
  Rec. 709 primaries/matrix. Export tests compare decoded colors with the
  source after color conversion, allowing for lossy encoding.

The native render destination and pixel-buffer APIs are documented by
[Apple's Core Image reference](https://developer.apple.com/documentation/coreimage/cicontext).

### Two-minute benchmark

Apple M5, 32 GB RAM; optimized Release objects, H.264 MP4, 1920×1080 output,
with audio. Before/after use the existing synthetic 30 fps moving-block source.
The heavy workload includes 12 zooms, camera, cursor/click effects, crop,
gradient, rounded corners, shadows, and four masks (two blur, two pixelate).

| Workload | Before | After | Speedup | Upload preparation after |
| --- | ---: | ---: | ---: | ---: |
| Plain, Fast, 60 fps | 28.4 s | 26.7 s | 1.07× | 0.09 s |
| Effects, Fast, 60 fps | 101.2 s | 32.6 s | 3.10× | 0.10 s |
| Effects, Ultrafast, 60 fps | 124.8 s | 29.7 s | 4.20× | 0.11 s |
| Effects, Fast, 30 fps (new option) | — | 16.1 s | — | 0.07 s |

The 30 fps result exports half as many frames; it is a separate quality/cadence
choice, not the basis of the 60 fps speedup. Plain video improved only slightly.
These are single runs, with other work active in the workspace and variable
system load; the unusually slow Ultrafast baseline illustrates that variability.
The source is highly compressible and does not represent every real recording.
No build was deliberately run alongside the final benchmark. All four outputs
were checked for the expected duration. Final sizes were 1.47, 15.89, 15.67,
and 9.08 MB, respectively. Upload preparation reused each MP4; no credentials,
R2 requests, or network transfers were used.

### Why more GPU kernels do not explain the remaining plain-export time

A follow-up run measured plain/Fast/60 fps at 27.0 s, effects/Fast/60 fps at
37.2 s, effects/Ultrafast/60 fps at 37.0 s, and effects/Fast/30 fps at 21.6 s.
All four exports completed and passed the duration checks. These repeat results
reinforce the system-load variability noted above. During the plain-export
pass, a three-second process sample showed the VideoToolbox compression thread
inside `VTCompressionSessionEncodeFrame` in 2,033 of its 2,062 samples; 2,020
were waiting for a synchronous reply from the system encoding service. The
trace also contains Core Image's Metal rendering and completion queues.
The local trace is retained at `.build/export-profiles/plain-1080p60.txt`.

This points to the encoding/service path as the next place to investigate for
plain exports. It is not a measurement of GPU utilization or proof of the
hardware encoder's maximum throughput. Increasing shader parallelism alone
would not remove those service waits. The existing three-frame queue already
overlaps decode, GPU rendering, and encoding; deeper queues or multiple
compression sessions would need a measured benefit before adoption.

Apple silicon's [unified memory](https://developer.apple.com/videos/play/tech-talks/10580/)
lets the CPU and GPU share memory. The exporter already uses shared IOSurface
buffers and pools to avoid video/overlay copies. More available RAM does not
remove the work of decoding and encoding the 7,200 output frames in this case.

### Verification

`make test` passed on the final implementation, as did the focused export checks
against the optimized Release build.

The focused production checks cover source colors/orientation, timed masks,
all six camera ratios, fresh versus cached GPU frames (one 8-bit rounding level
allowed), encoded colors, 30/60 fps frame counts, audio, fractional clip timing,
legacy settings, render-cache invalidation, and cancellation before export and
with GPU frames in flight. Export options were inspected in light/dark snapshots
at compact width. Snapshots do not verify native popover placement or live
AVPlayer rendering.

Commands for full checks, focused video checks, and the benchmark are in
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Previous measurement — 2026-09-10

Measured on an Apple M5 with 32 GB RAM using optimized Release objects
(`SWIFT_COMPILATION_MODE=incremental` for the standalone test runner). Each
export produces a two-minute, 1920×1080, 60 fps H.264 MP4 with audio.

| Workload | Previously documented | Baseline rerun | Optimized render | Upload preparation after optimization |
| --- | ---: | ---: | ---: | ---: |
| Plain, Fast | 34.9 s | 40.2 s | 26.3 s | 0.09 s |
| Effects, Fast | 114.4 s | 120.4 s | 87.0 s | 0.12 s |
| Effects, Ultrafast | 106.0 s | 109.4 s | 88.5 s | 0.12 s |

The effect workload includes 12 zooms, camera compositing, cursor movement and
click effects, crop, gradient background, rounded corners, shadow, and four
simultaneous masks (two blur, two pixelate). The source is a synthetic 30 fps
moving block over two solid colors with a silent soundtrack. It is much more
compressible than typical camera footage. These are single-run measurements,
not universal speed guarantees. The baseline rerun overlapped some build activity;
the optimized timing run was kept separate from the full test build. Compared
with the previously documented results, render time fell about 17–25%.

The compositor now reuses the scaled screen image when the decoded buffer and
all shutter-sample transforms match. Blur/pixelate rasters are reused for the
same source buffer (up to 32 MiB), while mask activation and positioning are
still evaluated at every output tick. Camera shadows are rendered once per
export. Pointer, camera footage, captions, and subtitles still update at 60 fps.

Heavy effects still take substantially longer than a plain render. Ultrafast
was not faster than Fast in the optimized single run; it reduces temporal blur
sampling but does not remove masks or other effects. Source frame rate, zoom
movement, and effect coverage affect how much work can be reused.

Both editor export and sharing use `RecordingStudioExporter`. Unchanged saved
sessions can reuse the existing deliverable; the benchmark forces fresh renders.
The production upload-preparation helper returned the existing MP4 in all three
cases. Optimized output sizes were approximately 1.19 MB, 17.92 MB, and 17.47 MB respectively.
No R2 credentials or actual uploads were used. Internet transfer time remains
dependent on file size, connection speed, and service conditions.

Run the optional benchmark using the commands in [CONTRIBUTING.md](../CONTRIBUTING.md).
Normal `make test` also checks fractional clip timing, recorded audio/video
composition, actual exports, cache invalidation, and cancellation.

Image checks use a 1920×1080 two-color PNG with progressive blur, at full source
resolution. Before caching, the fresh export took 82 ms and two repeated exports
took 41–43 ms. With caching, the fresh export took 84 ms and repeated exports took
0.6–2.0 ms. These small synthetic images do not represent every screenshot.
The PNG remained byte-identical across repeats. The first render still performs
all effects and lossless encoding; this optimization accelerates repeated
Copy/Save/Export actions.

The image renderer retains at most one encoded PNG, up to 32 MiB, and may evict
it under memory pressure. Its key includes source contents, edits, and custom
wallpaper contents; a missing dependency bypasses reuse. Larger PNGs and JPEG
exports render normally. Unedited PNGs retain their existing direct-copy path.
Replacing a wallpaper also refreshes the shared preview/export file signature.


## 3D shot rendering — 2026-09-19

Reviewed Cap's repository structure and traced its 3D editor/rendering flow at
[`c2ee42bda`](https://github.com/CapSoftware/Cap/tree/c2ee42bda0159e51e031356689e00d7ac4d66d11):
`apps/desktop/src/routes/editor/three-d.ts`, `three-d-panel.tsx`,
`Timeline/ThreeDTrack.tsx`, `context.ts`, and the Rust `camera3d` modules and WGSL
shader in `crates/rendering`. This was a feature-focused review, not an audit of
every file in Cap's web/backend/media monorepo.

BetterShot uses Swift quaternion/pinhole projection and an inverse Core Image/Metal
warp adapted from the upstream renderer. The eight moves and five angles follow
Cap’s camera parameters,
endpoint motion, linear timing, and zero boundary transition. Camera orbit and
content fold are independent; distance and vertical field of view determine
apparent size. Named scenes retain their weighted timing, and Auto Scene uses the
same shot ordering. Legacy saved plane poses keep their previous geometry.

Camera and blur properties support individual keyframes with editable cubic Bézier
curves. Keys use relative shot positions so resizing keeps animation proportional.
Tracks normalize once when edited, then use binary search and bounded curve
sampling during rendering. Independent entry/exit curves interpolate camera
parameters from the exact flat-fill distance at the authored field of view.
Undo, reverse, flips, persistence, and legacy decoding
share the production model.

Radial, directional, and tilt-shift focus modes include strength, falloff, focus
position/size, angle, and bokeh controls. The Metal implementation now uses Cap's
Gaussian weights/radius limits and three rings of 5/10/15 bokeh samples, including
its luminance weights and highlight gain. Adjacent Gaussian taps are paired using
linear filtering to reduce reads without changing their normalized weights.
Kernels compile once, and inactive blur bypasses the filters. The adapted code's
AGPLv3 attribution and complete license are bundled in `Resources/Licenses/`.
No Rust runtime or web UI dependency is required by BetterShot.

Preview and export share the same GPU compositor. The content plane includes the
screen, masks, cursor, and camera. Flat shadows fade away with shot activity.
Background stays in canvas
space, depth blur applies to the composed scene, and subtitles/keyboard captions
remain sharp. Zoom magnifies the entire card about its projected target, with
recentering; it no longer crops the source inside fixed card bounds. Steep poses
retain their authored camera distance and clip rays behind the camera. Transparent
canvas padding and analytic pixel coverage keep the plane's edges clean.
The Metal preview takes decoded frames from the existing AVPlayers, keeps at most
two GPU frames in flight, and retains backgrounds/overlays while camera or blur
keyframes change. It performs no CPU bitmap readback. Crop and mask editing keep
the existing native editing surface.

On this Apple M5 / 32 GB Mac, optimized Release objects measured:

| GPU composition workload | 1920×1080 | 3840×2160 |
| --- | ---: | ---: |
| Flat | 1.48 ms/frame | 5.11 ms/frame |
| Moving 3D shot | 2.19 ms/frame | 8.32 ms/frame |
| Moving 3D + Gaussian strength 60 | 2.89 ms/frame | 14.05 ms/frame |
| Moving 3D + bokeh strength 19 | 3.09 ms/frame | 13.46 ms/frame |

These are medians of three warm 120-frame runs after one warmup, with synchronous
GPU completion, a reused synthetic source buffer, and no concurrent build. They
measure GPU composition, not decoding, encoding, display frame rate, cold shader
compilation, or every recording workload. Reproduce with the command in
CONTRIBUTING.md.

Validation compares all 13 upstream presets and 248 geometry/zoom/transition
cases generated from the actual Cap Rust renderer (under 0.03 output-pixel error
at 360 pixels high). It also checks extreme-angle/edge-on safety, resolution
independence, focus-region pixel checks, bokeh output, masks/crop/cursor/camera
alignment, random seeks over a reused source, encoded 30/60 fps output,
persistence/undo/discard, and render-cache invalidation. Displayed production
AVPlayer/Metal fixture windows were captured in both appearances. The live check
requires completed GPU frames and verifies that a paused camera edit redraws
without rebuilding the compositor. Compact blur and curve controls have light/dark
offscreen snapshots.

The timeline removes the empty cut-marker gutter from both layout and height
calculations and adds a native **+ Add** menu for Zoom and 3D Shot. Existing cut
badges remain visible when there are cuts. Physical mouse gestures and menu
selection were not automated by these checks.

The orbit pad reuses the same pose updates and GPU compositor as numeric camera edits.
