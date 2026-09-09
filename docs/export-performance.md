# Export performance check — 2026-09-10

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
