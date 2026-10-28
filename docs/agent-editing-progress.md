# Multi-recording agent editing checkpoint

## Scope and working rules

The user authorized Steps 2 and 3 on 2026-10-29: editable multi-recording
projects, then MCP operations to append and arrange those recordings. Use
subagents, Ponytail full, reviewed local commits on `agent-editing`, and no push
or release. Preserve the untracked handoff and both Graphify directories.

Continue across five-hour allowance resets until completion or weekly allowance
exhaustion. Check usage before pausing, preserve this checkpoint, and never spend
reset credits. The hourly continuation automation is
`resume-multi-recording-agent-editing-after-usage-reset`; delete it when done or
when the weekly allowance is exhausted.

## Baseline

`abb5343` merged upstream main and preserved Step 1. Build, standalone checks,
focused MCP/editing checks, and saved-video replacement/close checks passed.
Real-library opening and external client setup remained unverified.

## Agreed implementation contract

- A project owns managed copies at `sources/<UUID>.bettershotrec`; originals
  remain untouched. Persist identities, names, and durations, never caller paths.
- Each leaf retains its raw screen/camera movies, input/capture sidecars,
  replacement audio, and authored native edit document.
- Optional document `sources` and clip `sourceID` preserve legacy decoding.
  Tagged outer clip ranges use the leaf's authored editor time; outer speed
  compounds its authored speed. Keep outer editor time, leaf editor time, and
  raw source time distinct.
- Strict multi-source validation preserves explicit array order and rejects
  invalid identities/ranges. Legacy single-source normalization stays unchanged.
- Share source resolution and the production compositor across preview/export.
  Reordering must not reuse a forward-only camera decoder at a stale timestamp.
- MCP adds library-ID-based append and exact-permutation clip reorder, with
  current revision checks. Async append rechecks its request lease and revision
  before committing and deduplicates concurrent retry IDs.

## First package implemented and verified

- Format-9 optional source catalog and optional clip source IDs; strict ordered
  validation, source-aware splitting, exact-permutation reorder, legacy decoding.
- Explicit managed leaf-media staging, safe local replacement-audio references,
  symlink/nested-source rejection, atomic installation, and failed-stage cleanup.
- Shared native render-configuration builder and authored-source timing resolver.
- The editor and session renderer fail closed on multi-source documents and on
  tagged clips missing their catalog. No new UI/tools expose incomplete rendering.
- Agent tests now use a per-process temporary recording library and exercise SDK
  discovery/open with library-issued IDs and unknown-ID rejection.

Validation: `BETTERSHOT_TESTING=1 BETTERSHOT_CHECK_MULTI_SOURCE=1 make test`
passed (app build, 38 standalone checks, source configuration integration).
Focused Agent Access and Agent Editing runners also passed. The first build's
source guards were edited while it ran; its stale-object integration failure was
resolved by rebuilding the final sources, not by weakening the assertion.

## Next packages

1. Preserve authored crop and replacement audio in the extracted native config
   builder. Compare it against `RecordingStudioModel.makeExportConfiguration()`
   in production-path tests. These fields were omitted by the pre-existing
   session renderer; extraction intentionally kept that behavior initially.
2. Integrate multi-source preview/export/playback using the shared compositor and
   source resolver. Handle mixed dimensions, missing camera/audio, speed and
   repeated/backward clips without stale decoder frames. Never render to a movie
   and adopt that flattened movie as an editable source.
3. Integrate root promotion, append/reorder, source selection/inspector semantics,
   undo/redo, and atomic save/reopen in Studio. Inspector semantics need a concrete
   decision: avoid silently ignoring authored effects or implicit global overrides.
4. Add `append_recording(handle, expectedRevision, projectId, requestId)` and
   `reorder_clips(handle, expectedRevision, clipIds[])`; extend inspection with
   sources and clip source IDs. Deduplicate pending append requests before await;
   recheck cancellation, lease and target revision synchronously before commit.
   Multi-source trim bounds use the clip's source duration, not other clips.
5. Complete composed preview/export and MCP end-to-end regression coverage,
   native compact/light/dark checks, and user documentation.

Do not report Steps 2/3 complete until the integration packages are verified.
