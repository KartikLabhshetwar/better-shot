# Export performance check — 2026-09-10

Measured on an Apple M5 with 32 GB RAM using optimized Release objects
(`SWIFT_COMPILATION_MODE=incremental` for the standalone test runner). Each
export produces a two-minute, 1920×1080, 60 fps H.264 MP4 with audio.

| Workload | Local render | Additional upload preparation |
| --- | ---: | ---: |
| Plain, Fast | 34.9 s | 0.11 s |
| Effects, Fast | 114.4 s | 0.11 s |
| Effects, Ultrafast | 106.0 s | 0.14 s |

The effect workload includes 12 zooms, camera compositing, cursor movement and
click effects, crop, gradient background, rounded corners, shadow, and four
simultaneous masks (two blur, two pixelate). The source is a synthetic 30 fps
moving block over two solid colors with a silent soundtrack. It is much more
compressible than typical camera footage. These are single-run measurements,
not universal speed guarantees.

Effects increased fresh rendering time substantially: the heavy Fast workload
took about 3.3 times the plain render. Ultrafast reduced it by about 7%, while
keeping the 60 fps output cadence. It reduces temporal blur sampling; it does
not remove masks or other effects.

Both editor export and sharing use `RecordingStudioExporter`. Unchanged saved
sessions can reuse the existing deliverable; the benchmark forces fresh renders.
The production upload-preparation helper returned the existing MP4 in all three
cases. Output sizes were approximately 1.19 MB, 17.88 MB, and 17.44 MB respectively.
No R2 credentials or actual uploads were used. Internet transfer time remains
dependent on file size, connection speed, and service conditions.

Run the optional benchmark using the commands in [CONTRIBUTING.md](../CONTRIBUTING.md).
Normal `make test` also checks fractional clip timing, recorded audio/video
composition, actual exports, cache invalidation, and cancellation.
