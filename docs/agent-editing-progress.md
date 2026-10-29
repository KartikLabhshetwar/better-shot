# Multi-recording agent editing checkpoint

## Status — 2026-10-29

Steps 2 and 3 are implemented and verified locally on `agent-editing`.
The final feature package contains the native and MCP workflows described below.
No push, release publication, version bump, real R2 credentials, live preferences,
or Keychain changes were used. Preserve the untracked HANDOFF-agent-editing.md,
graphify-out/ and Sources/graphify-out/.

Reviewed local packages:
- `abb5343`: merged upstream main while preserving Step 1 Agent Access.
- `dcb6adc`: validated format-9 source catalogs, tagged clips and managed copies.
- `7c957a5`: authored crop/imported audio parity and owning audio-asset lifetime.
- `cfd2d73`: source snapshots, native preview worker, shared multi-source rendering,
  playback assets, model transactions, undo/drafts/save/reopen.
- `c110686`: bounded multi-source audio-only exports to actual timeline samples.

## Final behavior and implementation contract

- Add Recording copies an individual library recording into the project's
  sources/<UUID>.bettershotrec package. Original captures are preserved. Nested
  multi-recording projects are rejected; caller filesystem paths are not exposed
  through MCP. Legacy single-recording projects remain compatible.
- Each leaf retains screen/camera/input/capture/replacement audio and authored
  edits. Optional root sourceDocuments snapshots are authoritative; older
  catalogs fall back strictly to managed leaf edits. Corrupt documents do not
  silently become defaults. No nested catalogs or tagged leaf clips are allowed.
- Outer source-tagged ranges use the leaf's authored editor clock, after its
  cuts/speed changes. Outer speed compounds authored speed. Shared resolution
  maps outer editor time to leaf editor time to raw media time.
- The main timeline handles trim/split/delete/speed/reorder with source-aware
  thumbnails, bounds and cut previews. Move Clip Earlier/Later and Control–Option
  arrows use the exact-permutation reorder path. Separate source/outer edits
  remain separate undo actions even within one run-loop event.
- Edit Recording embeds the existing native inspector/effect lanes. Apply creates
  one root undo action affecting every referencing clip; Cancel discards private
  changes/imports. Source topology stays fixed. Embedded models never register,
  write drafts/metadata, save, export or share independently. Root effect lanes
  are hidden; composed audio export remains available from the root inspector.
- Native Add/Edit, uncommitted speed, crop/mask edits and pending audio/caption
  preparation block conflicting operations. Quit is cancelled during a native
  source transaction, directing the user to Apply/Add/Cancel before quitting.
- Shared multi-source compositor/video/audio paths preserve authored framing,
  camera, timing and effects; canvases fit without stretching. Native Metal
  preview uses a serial worker. Inactive reader/frame/compositor caches are
  evicted, and backward/repeated clips reconstruct their decoding state.
- MCP append_recording(handle, expectedRevision, projectId, requestId) and
  reorder_clips(handle, expectedRevision, clipIds) share the native model.
  Inspection adds sources and clip sourceId. Append rechecks library membership,
  editor identity, source/target revision, cancellation and access lease after
  preparation and immediately before synchronous commit. Identical retries share
  one task/result; differing arguments reject reused IDs. Failed IDs replay their
  failure, so fresh attempts need a new ID. Four preparations may remain pending;
  slots release only after cleanup. The latest 16 completed receipts are retained
  while the target editor remains open.

## Verification actually completed

All checks used BETTERSHOT_TESTING=1 through the provided runners with temporary
libraries/media/output, isolated preferences and in-memory Agent Access state.

- BETTERSHOT_CHECK_MULTI_SOURCE=1 make test: unsigned Debug build, 39 standalone
  checks and source configuration/compositor/model integration passed. Covers
  authored crop/audio/canvas settings, nested speed clocks, malformed/symlink/
  nested-source rejection, rotated media, source switches/backward seeks, camera,
  preview-worker pixel parity, encoded video parity, snapshots and source-effect
  overrides, promotion/append/reorder/undo/drafts/save/reopen, and original media.
  Log: /tmp/bettershot-pcm-core-final.log.
- Audio-only regression: the strict duration assertion passed for five M4A
  exports and WAV, including tone/silence timing. Root cause was a retimed reader
  emitting a final PCM buffer beyond its requested timeRange, not only encoder
  padding. Multi-source audio-only export now bounds the actual 48 kHz PCM
  samples before encoding; legacy reading is unchanged.
- MULTI_SOURCE_UI focused runner passed with real authored/imported audio:
  compact light/dark native controls and sheets, composed audio controls, source
  effects/undo, active speed-draft rejection, root effect-edit rejection, embedded
  effect availability, registry quit-guard transitions, corrupt fallback rejection,
  superseded imports/cleanup and retained authored audio. Final log:
  /tmp/bettershot-ui-audio-final.log. Inspector/library/sheet snapshots are under
  .build/editor-snapshots/. Parent reviewed compact light/dark inspector layouts,
  populated library and source sheet; final real-audio inspector includes Export.
- AGENT_MULTI_SOURCE passed actual SDK initialize/list/call plus append/retry/
  concurrent retry, pending cap, cancellation/lease expiry/disable cleanup, stale
  source/target revisions, reorder/trim/undo/redo, composed preview, production
  export and save/reopen.
- Existing AGENT_ACCESS, AGENT_EDITING and RECORDING_SAVE gates passed final
  objects: authentication/Host/Origin/body checks, rotation/shutdown, split/trim/
  delete/speed, revision/cache fences, export jobs and saving before close.
  These four logs plus the UI gate are /tmp/bettershot-verified-<GATE>.log.
- Final make release passed unsigned; /tmp/bettershot-multi-release-final.log.
- Independent review found and verified fixes for ignored root Zoom/3D edits,
  missing composed audio export controls and silent source-sheet loss on Quit.
  Final review and git diff --check found no remaining actionable defects.

## Deliberate limits and manual checks still outstanding

Offscreen controls and render-worker parity do not establish live MTKView/AVPlayer
playback, pointer dragging, native toolbar behavior, source-sheet parent-window
close/quit-alert interaction, external client configuration, real-library use or
macOS 14 runtime behavior. These remain manual smoke checks. Compilation targets
macOS 14; no compiler/platform settings were changed.

A pre-existing generic makeMovie AVAssetWriter fixture stall prevented claiming
an unfiltered generic suite pass; the focused production runners above passed.
Custom wallpaper references retain existing ordinary-project storage behavior.
Nested multi-recording append, arbitrary file import through MCP and new agent
style/effect tools are outside this package.

The hourly continuation automation
resume-multi-recording-agent-editing-after-usage-reset was deleted after successful
validation and the local feature commit. Both authorized features and necessary
automated checks/docs are complete. No reset credits were used; do not push these
local commits without new authorization.
