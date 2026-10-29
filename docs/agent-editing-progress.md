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

## First package implemented and verified (`dcb6adc`)

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

1. Authored crop/replacement-audio parity is implemented and verified (`7c957a5`). The native
   parity test exposed an existing audio lifetime bug: `AVAssetTrack` retained
   no owning asset, so later composition failed with AVFoundation -11800 and
   OSStatus -12780. `RecordingReplacementAudio` now retains its `AVURLAsset`.
   The full focused `make test` gate passes with trimmed/retimed source clips,
   original/square-fill/square-fit canvas, and unsafe/missing soundtrack checks.
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

## Active implementation after the first allowance reset

The multi-source rendering agent owns exporter/source resolver/composition helper
and a new compositor integration test. Its proposed frame renderer uses serial,
resettable native readers and the existing compositor; authored source canvases
fit into the common output canvas without stretching.

The Studio agent owns document snapshots and root model transactions. Chosen UX:
an explicit transactional **Edit Recording** mode reuses the source inspector;
Apply creates one root undo step, Cancel discards local changes, and changes
affect all outer clips referencing that source. Source clip topology/duration
stays fixed; trim/speed/cuts/reorder live on the outer timeline. Embedded child
models must suppress registry, metadata, draft/save/export/share side effects.
Root `sourceDocuments` snapshots are authoritative and reject nested catalogs,
nested snapshots and tagged leaf clips. The resolver prefers them over the
immutable source package's initial edit document.

## Engine/model/preview package verified

Implemented and verified: shared multi-source still/video/audio
rendering, resettable per-source GPU frame feeds, Metal native preview worker,
root snapshot/promotion/append/reorder/source-effect transactions, embedded child
model side-effect isolation, and production integration tests. Parent wired
`BETTERSHOT_CHECK_MULTI_SOURCE` for configuration + compositor + model checks and
`BETTERSHOT_CHECK_MULTI_SOURCE_MODEL` for independent transaction checks.

The combined app build and 38 standalone checks pass. The model-only integration
passed promotion timing/identity, stale cleanup, undo/redo, save/reopen, reorder,
discard, source effect snapshots, and unchanged originals. Strict incoming saved
edit/priority-draft corruption checks also pass; malformed documents never fall
back to defaults during append.

Final compositor checks pass: exact preview-worker pixel parity across source
switches/backward seeks, independently oriented rotated-media reference, encoded
pixel parity, per-source framing, source snapshot overrides, and video/audio-only
soundtrack timing. Audio probes now use individual sample timing rather than a
whole buffer's starting timestamp. Multi-source writers end at the exact outer
duration to prevent trailing sample/AAC padding from extending the result. All
assertions removed temporarily during diagnostics were restored for the final
successful `BETTERSHOT_TESTING=1 BETTERSHOT_CHECK_MULTI_SOURCE=1 make test` run.

Do not edit a test file while another runner is compiling the shared test list.
Existing Agent Access/Editing checks also passed against the final built objects.
Native append/source editing UI, source-aware filmstrip/trim interactions, and MCP
append/reorder operations remain later packages; do not report them implemented.

Next: build the native library-based Add Recording flow, an explicit transactional
Edit Recording sheet, source-aware thumbnail/time/trim/cut-badge interactions, and
then the typed MCP append/reorder workflow. Keep root controls from silently
editing properties ignored by per-source rendering. Consider evicting inactive
decoder/frame caches for large source catalogs before exposing the workflow.
Live MTKView/AVPlayer interaction and macOS 14 runtime still need manual checks;
the current preview test exercises the actual actor render worker, not a displayed
window. No release or push is authorized.

## Native UI and MCP package under final validation (2026-10-29)

HEAD remains `cfd2d73`; the following package is uncommitted. Earlier "later
packages" notes above describe the previous committed checkpoint, not the current
working tree. All subagents have frozen their edits; no active edits remain.

Implemented in the working tree:
- Add Recording library sheet, transactional Edit Recording embedded Studio,
  source-aware thumbnails/trim bounds/cut badges, move-earlier/later context
  actions and Control–Option arrows. Original individual recordings are copied;
  nested multi-recording append is deliberately rejected.
- MCP append/reorder schemas and inspection source IDs; revision/library/editor
  checks before and after preparation, shared retry tasks, 16 completed receipts,
  and a global four-pending-preparation cap that releases slots after cleanup.
- Source/audio/transcription busy guards, strict corrupt fallback rejection,
  independent outer undo transactions, and inactive renderer cache eviction.
- README, CONTRIBUTING and Unreleased changelog describe the actual workflow.

Validation already passed against this package before the last two small fixes:
`BETTERSHOT_CHECK_MULTI_SOURCE_UI=1 make test` (app + 39 standalone + offscreen
light/dark controls/source effects/audio cleanup); then
`BETTERSHOT_CHECK_AGENT_MULTI_SOURCE=1 make test` (same build/standalone checks,
real SDK initialize/list/call, append/retry/concurrent retry, bounded pending
preparations, cancellation/lease expiry/disable cleanup, stale target/source
revisions, reorder/trim/undo/redo/composed preview/export/save/reopen).
Existing AGENT_ACCESS, AGENT_EDITING and RECORDING_SAVE focused runners passed.
Unsigned `make release` passed. Tests ran with BETTERSHOT_TESTING=1 and isolated
library/preferences/token state, not real credentials.

Final MULTI_SOURCE rerun found intermittent audio-only output padding:
3.3246875s instead of 3.25s. Existing assertion remains unchanged. Minimal fix
moves multi-source writer.endSession before input.markAsFinished in
RecordingAudioExport.swift, since encoder finalization could race the endpoint.
The prior passing MP4 sibling had exact audio/video duration. Also added native
and shared append guards for uncommitted clip-speed drafts (documents/revisions
omit draft values until committed), with production-model UI regression checks.

Final verification currently running in exec session 74583, sequentially:
1. MULTI_SOURCE make test -> /tmp/bettershot-audio-endpoint-final.log
2. MULTI_SOURCE_UI runner -> /tmp/bettershot-speed-ui-final.log
3. repeated MULTI_SOURCE runner -> /tmp/bettershot-audio-endpoint-repeat.log
Inspect results, never assume an unfinished runner passed. Rebuild Release after
these last changes if practical. If core duration still fails, diagnose the
production audio writer rather than loosening duration tolerance. No commit until
satisfactory final validation/review. Stage explicit intended files only, including
new Sources/BetterShot/RecordingStudioSources.swift and the three new test programs
plus RecordingSourceTimelineInteractionCheck.sources; preserve handoff/Graphify.

Offscreen snapshots reviewed: compact recording inspector light/dark, populated
Add Recording library light, and source editing sheet dark. They show layout and
controls; black offscreen video does not establish live playback. Manual live
MTKView/AVPlayer, parent-window sheet close handling, external client setup and
macOS 14 runtime remain unverified. Generic suite's pre-existing makeMovie stall
remains a limitation; focused runners were used. No push/release/version change.

Final runner outcome: session 74583 stopped with exit2 on the first gate.
Audio-only duration STILL fails after reordering finalization:
3.3253541666666666s vs3.25s at compositor test169. UI speed-draft and repeated
core runners did not run due to && short-circuit. The endSession ordering is
therefore an unproven change, not a verified fix. Next reset must investigate
sample timing/encoder padding or exact writer range handling, preserve strict
assertions, then rerun core/UI/MCP as appropriate. Do not commit this WIP package.

## Audio endpoint correction verified after reset

Root cause: AVAssetReader's retimed mix can emit a final PCM buffer beyond its
requested timeRange (3969 samples at3.2426667s, ending3.3253542s for a3.25s cut).
The encoder endpoint alone does not reliably remove the extra decoded samples.
Multi-source audio-only export now requests interleaved48kHz stereo PCM and trims
the actual last sample buffer to the remaining sample clock before encoding.
Legacy audio reading stays unchanged; the strict duration assertion is unchanged.
The full `BETTERSHOT_TESTING=1 BETTERSHOT_CHECK_MULTI_SOURCE=1 make test` passed
against final production sources: app build,39 standalone checks, authored source
configuration, preview/video parity including rotated/backward/camera footage,
five M4A exports plus WAV with timing/tone/silence checks, and model transactions.
Log: /tmp/bettershot-pcm-core-final.log.

Independent read-only review also found and verified fixes for ignored root
Zoom/3D edits (controls now belong only in leaf editors), missing native composed
Export Audio access (restored), and Quit silently discarding embedded source
edits (registry transaction guard now blocks quit until Apply/Cancel).
Final UI/MCP/access/edit/save runner sequence is active in session59240, with logs
/tmp/bettershot-verified-<GATE>.log; final unsigned Release build session68428.
These later results are pending, not established by this core pass. No live
macOS14, native quit-alert or displayed video claim follows from these tests.
