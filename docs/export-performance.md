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

### Verification

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
