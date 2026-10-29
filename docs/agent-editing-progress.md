# Agent editing implementation checkpoint

## Current status

The agreed Steps1–3, nested combined-project imports and typed MCP visual-effect
editing are implemented and validated locally on agent-editing. The user will do
combined manual verification later. No push, publication, version bump, real R2
credentials, live preferences, Keychain or permission changes were made. Preserve
HANDOFF-agent-editing.md, graphify-out/ and Sources/graphify-out/ (user untracked).

Reviewed local history:
- abb5343: merged upstream main while preserving Step1 Agent Access.
- dcb6adc: validated format9 source catalogs, tagged clips and managed copies.
- 7c957a5: authored crop/audio parity and owning audio-asset lifetime.
- cfd2d73: source snapshots, shared rendering/preview and model transactions.
- c110686: bounded multi-source audio-only output to actual timeline samples.
- 5efc254: native Add/Edit Recording, source timeline and MCP append/reorder.
- 37afbd4: embedded dirty tracking and native Cancel discard protection.
- 56538a2: combined-project imports normalized to editable leaf sources.
- The final effects package adds the tools and checks described below.

## Native and nested-project contract

Add Recording copies library recordings or combined projects into managed
sources/<UUID>.bettershotrec packages; original captures remain untouched.
Combined imports copy each referenced validated leaf once with a fresh source
UUID, remap imported clip IDs, and preserve ordered source ranges/speeds and
authoritative authored snapshots. Catalogs/leaf snapshots stay flat: no recursive
filesystem references or rendered-movie replacement. Repeated clips share their
new managed source. Optional presentationAspectRatios records inner-to-outer
canvas ancestry (at most16 positive finite ratios); rendering fits these from
outside in before drawing the leaf, preserving centered black letterboxing.
Destination root encoding settings remain authoritative; imported root encoder
mute/format/quality/frame rate are not projected onto copied leaf documents.

Outer tagged ranges use leaf authored editor time. Source resolution maps that
clock through leaf cuts/speed to raw media; outer speed compounds authored speed.
Root sourceDocuments override immutable leaf edits; older missing snapshots fall
back strictly, never converting corrupt data into defaults. Flat leaf validation,
symlink/unsafe audio-reference rejection and cancellation/stale cleanup remain.

The main timeline handles source-aware trim/split/delete/speed/reorder,
thumbnails/cut previews, Move Earlier/Later and Control–Option arrows. Edit
Recording embeds the native source inspector/effect lanes: Apply is one root undo
action for every referencing clip, Cancel protects dirty changes, and discarded
private imports are removed. Embedded models have a normalized clean in-memory
baseline and dirty tracking, but never register, write drafts/metadata, save,
export or share independently. Root effects are not silently edited; use a leaf.
Composed Export Audio remains available in the root inspector. Native Add/Edit,
crop/mask/speed editing and audio/caption preparation block conflicting agent
operations. Quit is cancelled during a native source transaction until resolved.

Shared native compositor/video/audio paths preserve source framing, camera,
cursor and effect timing. Metal preview uses a serial worker with bounded frames;
inactive readers/frame/compositor caches are evicted. Backward/repeated playback
rebuilds decoder state. Pending frame comparisons tolerate1ns of clock rounding:
equivalent nested times straddled recorded PTS0.7 by about2e-15 seconds and
otherwise selected adjacent frames. Audio-only export clamps actual48kHz PCM
samples because retimed readers can emit a buffer past the requested timeRange.

## MCP surface

Existing authenticated loopback Agent Access, library allowlisting, revisions,
composed previews, edits/undo/redo/save and retained export jobs remain. No raw
filesystem/script/capture/cloud-upload tools were added.

append_recording(handle,expectedRevision,projectId,requestId) accepts individual
or combined library projects. Identical retries share a task/result; differing
arguments reject reused IDs. Failed IDs replay failure, so fresh preparations
need a new ID. Four preparations may remain pending; slots release after cleanup.
The last16 completed receipts are retained while the target remains open.
reorder_clips requires every current clip ID exactly once. Async append rechecks
library membership, unique editor identity, source/target revision, lease,
cancellation and native busy state before synchronous commit.

inspect_effects(handle,sourceId?,offset?,limit?) returns handle/root revision,
selected leaf ID, capabilities, path-free settings/catalogs and separate paginated
zoomCues/masks/shots3D collections. Default page32, maximum64; pages include total
counts. Omit sourceId for legacy recordings; combined roots require an existing
leaf ID from inspect_timeline. Embedded children supply capabilities only; raw
authored document fields are preserved rather than replaced by normalized input.

set_effects(handle,expectedRevision,sourceId?,patch) supports:
- None/approved gradients/RGBA backgrounds; padding/corners/shadow/aspect/Fit/Fill.
- Supported cursor visibility/appearance/scale/motion/press/ripple/idle behavior.
- Available camera visibility/layout/placement/size/roundness/independent aspect.
- Zoom cues/enabled state, crop/reset, scoped Blur/Pixelate masks and preset3D.
- Existing click/keystroke/subtitle visibility, placement and subtitle style.

Zoom times use raw source time; mask/3D times use the leaf authored editor clock.
Supplied arrays replace the entire collection (maximum64); omitted settings stay
unchanged. Unknown keys/types, nonfinite or out-of-range values, duplicate IDs,
invalid timing/rectangles and unsupported capabilities fail before mutation.
Schema/runtime mask scope/timing alternatives match. Existing custom wallpapers,
gradients and 3D poses remain intact when omitted and are inspected without paths
or arbitrary matrices. Transcription, audio import, arbitrary document payloads,
wallpaper paths and custom keyframe/matrix authoring are outside this typed API.

The shared throwing model transaction supports legacy and leaf documents, keeps
clip/trim/source topology fixed and legacy audio identity unchanged, prepares
native configuration/playback assets, then checks task cancellation, the Ops
lease/unique-handle/native-busy/revision callback and own loaded/revision state
immediately before synchronous commit. Changes create one undo step/revision;
no-ops validate without bumping either. Native source-audio edits remain supported
through the existing wrapper. Callback errors retain their typed MCP outcomes.

## Final automated evidence

All tests used BETTERSHOT_TESTING=1 through provided runners with temporary media,
libraries/output, isolated process preferences and in-memory Agent Access tokens.
No installed app, real captures or credentials were used.

- AGENT_EFFECTS make test passed unsigned Debug app build,39 standalone checks,
  strict parser/schema/inspection tests and complete effects integration:
  every section/limits/unknown keys/capability/time validation, pagination/path
  redaction, legacy and source atomic edits, exact one-step undo/revision/no-op,
  composed preview/export/save/reopen, unchanged originals, stale/busy/duplicate/
  cancelled/revoked requests, final model callback rejection, actual SDK list/
  inspect/set envelopes and disabling access mid-request.
  Log: /tmp/bettershot-agent-effects-final.log.
- Final NESTED_IMPORT passed C→B→A independent canvas reference, fresh/shared IDs,
  clocks/speeds/camera/audio, destination mute policy, encoded parity, source
  effects/undo/save/reopen, rejected-stage cleanup and original byte preservation.
  Log: /tmp/bettershot-extensions-final-NESTED_IMPORT.log.
- Final MULTI_SOURCE, MULTI_SOURCE_UI, AGENT_MULTI_SOURCE, AGENT_ACCESS,
  AGENT_EDITING and RECORDING_SAVE gates passed current final objects. Coverage
  includes crop/audio/rotated source configuration, backward/switching preview,
  encoded output,5M4A+WAV timing/tone/silence, source model/dirty-state/import
  cleanup, authenticated SDK append/retry/lease/reorder, auth/rotation/shutdown,
  edit/cache/revision fences, export retention and saving before close.
  Logs: /tmp/bettershot-extensions-verified-<GATE>.log.
- Final unsigned make release passed: /tmp/bettershot-extensions-release.log.
- Independent source/trust-boundary review and git diff --check passed. README,
  CONTRIBUTING and Unreleased changelog describe actual behavior and JSON usage.

One formerly intermittent worker/shared pixel assertion was diagnosed precisely:
only one blue component at one rotated pixel differed (183 vs182) between
independent NV12→BGRA CoreImage contexts. Worker parity now permits at most ONE
8bit level per component AND normalized mean error<1e-5, with diagnostic images
for larger differences. Geometry, raw/editor clock and replay assertions remain
strict. The independent nested reference separately allows differences only on
its proven fractional viewport-edge columns and total error<.0005; all other
nested pixels and geometry/clocks stay exact. No broad tolerance hides timing or
layout errors. Tests were not disabled to pass.

## Manual verification and deliberate limits

The user deferred combined manual verification. Prior isolated displayed checks
passed AVPlayer readiness, source-boundary playback, backwards seeks and new
Metal frames in both appearances on macOS27.0.1. Native UI tools verified source
Apply/reopen, Keep Editing/Discard confirmation, Add Recording and Undo/Redo.
No further live UI checks were run for the two extensions in this final package.

Still manual: macOS14 runtime, timeline pointer dragging, actual parent-window
close/production Quit interactions, real-library use and preferred external MCP
client configuration. The fixture lacked existing Screen Recording permission,
so no live window PNGs were captured and no permission was requested. The app
continues to target macOS14 without compiler/platform setting changes.

A pre-existing generic makeMovie AVAssetWriter fixture stall prevents claiming an
unfiltered generic suite pass. The focused production gates above all passed.
Existing custom wallpaper references keep ordinary-project storage behavior.

The continuation automation continue-nested-imports-and-agent-visual-effects
was deleted successfully after the reviewed local effects commit. Both requested
extensions and their automated checks/docs are complete. No reset credits were
used. Do not push these local commits without new authorization.
