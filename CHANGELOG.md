# Changelog

All notable changes to Better Shot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2] - 2026-08-26

The image editor's broken export after a save is fixed, and three community
performance passes move the heavy image and JSON decoding that sat on the main
thread into the background, so the preview card, the Recording Studio and long
recordings all stop stuttering.

### Changed

- **The studio wallpaper decodes once, not sixty times a second**: With a custom wallpaper set, the Recording Studio preview re-read the file from disk and re-decoded it on every frame of playback and every scrub tick, on the main thread, in the same tick that had to draw the video. The wallpaper now renders through the image editor's cached preview component, so the decode happens once, off the main thread, and both editors share the cached copy ([#113](https://github.com/KartikLabhshetwar/better-shot/pull/113), thanks [@zergzorg](https://github.com/zergzorg))
- **The preview card decodes its thumbnail in the background**: The after-capture card decoded the full screenshot on the main thread, tens of megabytes for a 5K shot, just to draw a card a couple of centimeters wide, right while the capture pipeline was still writing the file. Screenshots now go through the same off-main thumbnail decoder recordings already used ([#115](https://github.com/KartikLabhshetwar/better-shot/pull/115), thanks [@zergzorg](https://github.com/zergzorg))
- **Long recordings open faster in the studio**: The pointer sidecar, sixty samples a second for the whole recording, so megabytes of JSON on a long take, was read, decoded and thinned on the main thread while the studio window sat unresponsive. All of it now runs in the background before the window fills in ([#117](https://github.com/KartikLabhshetwar/better-shot/pull/117), thanks [@zergzorg](https://github.com/zergzorg))

### Fixed

- **Export works after a save**: Saving or sharing an annotated screenshot left the editor pointing at a base image that was never written to disk, so the next Export, Copy or Save failed with "The file couldn't be opened because it isn't in the correct format", whether the edit was an annotation or a background effect. The first save now stores the untouched base and the editable document next to the History copy and repoints the editor at it, so every later export renders, and repeated saves stop stacking duplicate copies in History ([#118](https://github.com/KartikLabhshetwar/better-shot/issues/118), thanks [@erickhun](https://github.com/erickhun))
- **Copy on a recording copies the video**: The preview card's hover Copy put a still frame on the clipboard for recordings. It now copies the video file itself, so the paste lands in Finder or Slack as a movie ([#115](https://github.com/KartikLabhshetwar/better-shot/pull/115), thanks [@zergzorg](https://github.com/zergzorg))

## [0.4.1] - 2026-08-26

A quick follow to the rebuild. The Recording Studio learns to crop video the
way the image editor crops a shot, the clip timeline picks up a minimap,
split snapping and mid-drag panning, the app wears a new clover, and two
community fixes bring back Copy and the space key.

### Added

- **Crop video in the Recording Studio**: The video editor now has the same crop the image editor has. Enter crop from the toolbar, drag the box or any handle, and the recording is cropped non-destructively: the full frame stays in the project, so the crop can be adjusted or cleared later, and Cmd Z steps it back. The preview and the export run one shared geometry, auto-zoom anchors are remapped into the cropped frame so zoom and crop now compose instead of zoom overriding the crop, and export sizes round to even pixels so every encoder accepts them
- **Timeline minimap**: Once the timeline is zoomed in, a slim strip under it draws the whole recording with the visible window as a draggable chip and a tick for the playhead, so a zoomed-in timeline never loses its place. At fitted zoom it stays out of the way
- **The timeline pans itself mid-drag**: Dragging a trim handle or scrubbing past the visible edge scrolls the timeline in that direction, faster the further you overshoot, instead of pinning the drag to the edge
- **Split snapping**: The split line snaps to the playhead when the pointer comes within a few pixels of it and refuses to cut right on top of an existing clip boundary, so accidental sliver clips are gone; hold Option to cut exactly where the pointer is. `S` splits at the pointer, `C` splits at the pointer or, with nothing hovered, at the playhead, and the right-click Split item disables itself where a cut is not possible
- **The Copy button is back**: The 0.4.0 toolbar rebuild dropped Copy from the image editor, so an annotated screenshot could only leave through a save panel. It returns beside Export on its old shortcut, and the pasteboard now carries the file, the image and TIFF together, so the paste lands in a terminal as well as in Gmail ([#111](https://github.com/KartikLabhshetwar/better-shot/pull/111), thanks [@zergzorg](https://github.com/zergzorg))
- **Delete shared uploads from Settings**: The Cloud tabs in Settings grew a Delete From Cloud button that removes the uploaded copies from your R2 bucket after a confirmation, so their share links stop working while the local files stay on your Mac

### Changed

- **A clover on the icon**: The owl lasted one release. The app icon, the menu bar glyph and the website now carry a new clover logo
- **White clip selection**: The selected clip's outline in the timeline is white instead of yellow, so selection reads as chrome rather than a warning
- **One card for every transfer**: Rendering, uploading, exporting and a failure with retry all report through the same floating status card, replacing the separate share link panel, so a share and an export look and behave the same
- **The playhead pins instead of vanishing**: Scrolling a zoomed timeline away from the current frame keeps the playhead at the near edge, dimmed, so you always know which side the frame is on
- **Timeline edges read as edges**: Content scrolled out of view fades out at the sides instead of hitting a hard clip, and a clip edge under the pointer shows its trim handle before you grab it

### Fixed

- **Annotation tools stay armed**: Drawing a blur, pixelate or any other annotation no longer bounces the editor back to the select tool after one shape, so masking several spots in a row does not mean re-picking the tool each time ([#108](https://github.com/KartikLabhshetwar/better-shot/pull/108), thanks [@zergzorg](https://github.com/zergzorg))
- **Space switches region capture to window selection**: Region capture invoked the system tool in mouse-only selection mode, so the space key that flips it over to window selection did nothing. It now opens in the interactive mode that carries the space toggle, pinned to start in selection, and a space-switched shot drops the window shadow to match window capture ([#109](https://github.com/KartikLabhshetwar/better-shot/pull/109), thanks [@zergzorg](https://github.com/zergzorg))

## [0.4.0] - 2026-08-26

The rebuild release. Better Shot's capture pipeline, floating recording bar,
and both editors were rebuilt from the ground up. Recording gained
cursor-tracked auto-zoom, self-hosted share links, and a capture core that
survives a crash mid-recording. The editors gained proper tabbed inspectors,
and the parts of a screencast that used to need After Effects (speed ramps,
transitions, scene changes, a tilted 3D card, color) now live in dedicated
tabs.

### Added

- **Recording options in Settings**: Settings > Recording now holds the camera and microphone pickers, the system audio toggle, a 0/1/3/5 second start delay, and the teleprompter switch. They read and write the same preferences the recording bar uses, so a choice made in either place shows up in both
- **Cloud share compresses before it publishes**: Sharing from either editor now runs the file through a local compression pass before a single byte is uploaded. Images are downscaled to 2560 px and encoded as both PNG and JPEG with the lighter file winning, and a shot with real transparency keeps its alpha. Videos are re-encoded to 1080p MP4. Whenever the compressed file does not come out smaller, the original uploads instead. Everything publishes straight to your own R2 bucket, configured in Settings > Sharing
- **A cursor the editor draws**: The pointer is no longer burned into the capture. Its path, its clicks and every shape it wore (arrow, beam, hand, resize) are saved beside the recording, so the editor draws it back and you restyle it after the fact. A spring chases the recorded path, so a shaky hand glides, the pointer never trails behind the motion, and a click lands exactly on the spot instead of arriving late. A Cursor tab holds the type (the pointer you had, or a soft touch ring), size, how far it leans into a fast sweep, whether it fades out once you stop moving, and the motion feel: Relaxed, Smooth, Natural or Snappy. The preview and the exported file draw the same cursor, scaled by the zoom like the rest of the picture
- **Mute the mic mid-recording**: The recording bar grew a microphone button with its own level under the glyph, so a mic that has gone quiet shows up while you record rather than in the finished file. Muting drops the audio instead of writing silence, so a muted stretch leaves nothing in the recording at all
- **Keyboard overlay**: Turn on “The keys I type” in Settings, Recording and BetterShot records your keystrokes beside the recording, then draws them under the video in the editor. Typing collapses into words instead of stuttering key by key, backspace takes the character back, and a shortcut like ⌘S gets its own moment. Every line stays editable or droppable in the Overlay tab, with position, size, weight, color, a backdrop plate and uppercase. Capture is off until you turn it on, asks for Input Monitoring, and never leaves your Mac
- **Captions**: The Overlay tab can transcribe the recording's own audio into timed caption lines, on device where your Mac supports it, so nothing is uploaded. Speech is grouped into readable lines that break on a pause, on a full stop, or when a line gets too long, and every line stays editable in the sidebar. Position, size, weight, color, width, a backdrop plate and uppercase, drawn on the canvas so captions stay readable while the recording zooms
- **Text segments**: Drop a line of text on the canvas for a stretch of the recording. It sits on the background rather than inside the video, so it holds still while the recording zooms under it. Size, weight, alignment, color, width and shadow, plus an entrance and an exit picked from fade, slide, pop or a typewriter reveal. Drag it where you want it on the preview, and one resolve drives both what you see and what the exporter draws
- **Masks**: An Overlay tab holds boxes that either hide part of the frame or spotlight it. Hide blurs or pixelates what is inside the box, and it is destroyed in the export rather than covered, so a password on screen never ships. Spotlight dims everything outside the box and fades in and out so it does not blink. Drag the box on the video, set its start and end from the playhead, and the same math paints the live preview and the exported file
- **Text, blur and caption lanes**: Text overlays, masks and caption lines now sit on the timeline under the zoom lane, one lane per kind, exactly like zoom cues. Drag a segment to move it, drag either edge to retime it, click it to select it in the sidebar. A lane only appears once it has something in it, so a plain recording still gets a plain timeline
- **Color in the image editor**: The screenshot editor gained the same Color section the recorder has, with the nine presets, an intensity slider and the full manual set (exposure, contrast, saturation, warmth, tint, fade, split tone, vignette, grain), so a set of screenshots and a clip can be graded to match
- **Tabbed inspectors**: The video sidebar is six tabs instead of one long scroll: Clip (scissors), Motion (zoom), Cursor (pointer), Camera (person), Overlay (masks) and Style (paintbrush). The screenshot sidebar got the same treatment with three: Annotate, Adjust and Style. Each tab holds only the controls that act on what you selected, so neither sidebar is a wall of disclosure triangles any more
- **Per-clip audio mode**: Speeding a clip up no longer forces one behavior on its audio. Each clip picks Mute, Keep Pitch, or Match Speed, so a 4x skim can stay silent while a 0.5x hold keeps a natural voice
- **Transitions**: Adjacent clips can cross into each other with Crossfade or Fade Through Black, with an adjustable length. The transition is baked into the export rather than faked in the preview
- **Scene modes and split screen**: Every clip carries its own scene: Both (screen with the floating face cam), Screen only, Camera only, or Split, which drops the bubble and gives the screen and the camera a pane each. Change scenes mid-recording and the export cuts between them
- **3D camera**: A Perspective section in the Style tab tips the whole card in space. Drag the tilt pad for pitch and yaw, add Roll, and pull Depth for how hard the lens sells it. One pinhole projection drives both the live preview and the export, so combined tilts stay square and the drop shadow follows the pose
- **Color correction**: Exposure, contrast, saturation, temperature, tint, highlights, shadows, and vignette, with separate grades for the screen and the face cam
- **Click highlights**: Clicks recorded in the pointer sidecar now render as expanding rings in the export, derived from the same capture that drives auto-zoom
- **Export progress**: Exporting shows a live progress overlay instead of a frozen window, with the spring timing and reduced-motion fallback the rest of the app uses
- **Countdown overlay**: The start delay now draws a full-screen countdown so you know exactly when capture begins
- **Escape closes editors**: Escape dismisses the image and video editors, and an unsaved editor asks before it closes rather than discarding your work
- **Split anywhere**: One Split button, on click or with `S`. Turn it on and click a clip where you want the cut; it turns itself off once the cut lands, so you never get stuck in a cutting mode. `Delete` removes the selected clip
- **Inspector tab shortcuts**: Command 1 through Command 6 jump between the video tabs, and Command 1 through Command 3 between the screenshot tabs
- **Annotation keys are visible**: The image editor's tools always had single-key shortcuts, but nothing said so. Each tool now carries its key in the corner of its button and in its tooltip, read from the same table the keyboard uses, so the two cannot drift apart
- **Auto-zoom (virtual camera)**: Recordings now track your cursor and zoom in around it, the way a screencast editor would. Pointer position is sampled at 30 Hz during capture and written to a `.pointer.json` sidecar next to the video; the editor turns clicks into zoom cues, smooths them through a spring-damped viewport timeline, and bakes the motion into the export as per-frame transform ramps. Toggle it in the video editor's Zoom inspector, where each cue can be retimed, rescaled, or deleted, and preview it live before exporting
- **Zoom cue lane**: A second timeline lane under the trim strip shows every zoom cue in place, so you can see where the camera moves relative to the footage
- **Face cam**: A circular camera bubble you can turn on from the recording bar and drag anywhere on screen. It is captured as part of the recording rather than composited afterwards, so what you position is exactly what lands in the video. Right-click the bubble's toolbar button for Small, Medium, and Large. Works with any connected camera, including Continuity Camera with your iPhone
- **Clip timeline**: The trim strip is now a multi-clip editor. Split at the playhead, drag either edge of a clip to trim it, click a clip to select and scrub it, and delete the parts you do not want. The player, zoom preview, and export all follow the edited timeline, so what you scrub is what you get
- **Per-clip speed**: Each clip carries its own speed between 0.25x and 4x, applied to video and audio together, so you can hold on a slow section and skim past a long one in the same recording
- **Undo and redo in the video editor**: `Cmd Z` and `Cmd Shift Z` step through clip edits
- **Share links via Cloudflare R2**: A Share button next to Export uploads the recording to your own R2 bucket and copies the public link to your clipboard. Configure it in Settings > Sharing with your account ID, bucket, public base URL, and an R2 API token scoped to Object Read & Write. Uploads go straight from the app to R2 over a hand-signed AWS SigV4 request (CryptoKit only, no SDK and no proxy worker), so nothing routes through a third-party service
- **Keychain-backed credentials**: The R2 access key ID and secret access key are stored in the macOS Keychain. Only non-secret config (account ID, bucket, public base URL, enable flag) lives in UserDefaults
- **Test Connection button**: Verifies R2 credentials before you rely on them, using an object-scoped probe so an Object Read & Write token passes without needing bucket list permission
- **Source picker bar**: Record no longer starts capturing the instant you click it. It opens a floating bar that lists every connected display and every open window alongside area selection, with microphone and system audio toggles and a 0/1/3/5 second start delay. Choosing a source morphs the same bar in place into the recording controls, so the bar you set up in is the bar you stop in
- **Record a single window**: Window capture uses a window-scoped content filter, so the recording follows that window and excludes whatever is stacked on top of it
- **Recording area highlight**: When recording a region, the area outside it dims and the edge gets a pulsing accent border, so you always know what is in frame. The overlay is click-through and excluded from the capture itself
- **Redesigned recording bar**: The floating bar now uses an `NSVisualEffectView` HUD material with refined corner radius and shadow, an AppKit-tracked hover puck that keeps responding while Better Shot is in the background, spring-based show and hide animations, and drag position that persists between recordings
- **Multi-display capture**: Recording now targets the display under your pointer (or the frontmost window) instead of always grabbing the main display. Region capture carries its own `CGDirectDisplayID`, so selections on secondary and negative-origin displays land in the right place
- **Crash-resilient recording**: Video is written as fragmented MP4 with a 2-second fragment interval, so a crash or force quit mid-recording leaves a playable file instead of a corrupt one
- **Microphone recording**: Turning on the mic in the recording bar records your narration into the video as its own audio track, kept separate from system audio rather than mixed at capture time. Requires macOS 15, which is where ScreenCaptureKit added microphone capture, so the control is hidden on macOS 14
- **Open editor after screenshot**: New setting to jump straight into the editor after taking a screenshot ([#72](https://github.com/KartikLabhshetwar/better-shot/pull/72), thanks [@y-u-s-u-f](https://github.com/y-u-s-u-f))
- **New owl mascot**: New app icon and logo across the app and website

### Changed

- **One toolbar, three buttons**: Both editors now end in the same three actions. Save (Cmd+S) keeps your edits inside BetterShot and flashes a green Saved confirmation, Share uploads and copies a link, and Export, the highlighted button, writes the finished image or video to your Mac. The image editor's confusing extra buttons ("Save As" and the checkmark) are gone
- **Local and Cloud tabs**: The Screenshots and Recordings pages in Settings are now split into a Local tab for files on disk and a Cloud tab listing everything you have shared, with a thumbnail, a copy-link button, and a shortcut to the share page. The old dead Shared Links section is gone
- **Same wallpapers everywhere**: The image editor and the Recording Studio now share one wallpaper library with the same Recent and macOS tabs, so a screenshot and a clip can sit on the same background
- **Share UI polish**: The image editor's share button shows live progress with a cancel, the upload options popover was redesigned, and the share link panel now brings the app forward properly and steps back when closed
- **Everything saves as BetterShot**: Exported screenshots and recordings are named `BetterShot_` plus the timestamp, recording projects use the `.bettershotrec` extension, and the support folders, sidecar files, and alerts all carry the BetterShot name
- **One save folder for everything**: Screenshots and exported recordings land in the same place, your Desktop by default, chosen once under Settings > General > Save to. The format and quality pickers there govern editor exports too, so nothing quietly disappears into a Pictures subfolder any more
- **MP4 is the default everywhere**: Exports, quick saves, and suggested file names all produce MP4, and the cloud copy of a share is always an MP4 even when compression cannot shrink the file, so a shared link plays in any browser, on Windows, and in Slack. A QuickTime master is rewrapped without re-encoding on the way out, and MOV stays one tap away in Export Options
- **Undo and Redo are buttons again**: Both editors carry Undo and Redo in the toolbar, stepping through the same history as ⌘Z and ⇧⌘Z and dimming when there is nothing left to step through
- **The canvas sits on a plain background**: The dotted workspace pattern behind the editors is gone; both now rest on the native window background
- **The upload popover asks one thing**: a title. The comments-and-likes toggle went away with the worker service behind it; share pages are static files served from your own bucket
- **Clip controls moved to the transport bar**: Split, Delete and the clip count sit beside the timecode under the player instead of in a strip above the timeline, which gives the timeline back a row
- **Crop is a mode, not a permanent panel**: Entering crop shows the crop box, and leaving it puts the box away in both the image and the video editor. Crop handles stay flat while cropping even when a 3D pose is applied, so they remain grabbable
- **The face cam bubble is draggable in the editor**: Position it in the preview and the export follows, instead of being locked to where capture left it
- **Rebuilt clip timeline**: Cuts occupy real space on the timeline, delete works on the selected clip, and the drag math for trimming and scrubbing was rewritten so handles track the pointer 1:1
- **Export and Cloud Share sit side by side**: The editor toolbar has two buttons. Export renders and saves locally; Cloud Share uploads and copies a link. With a bucket connected, Cloud Share is a split button whose menu re-copies the last link, opens it, or hands it to Mail, Messages or Slack through the system share sheet. Without one, it opens the cloud settings instead of hiding
- **A share shows you the link**: Finishing an upload used to flash a "Link Copied" toast for two and a half seconds and take the link away with it. It now opens a card that stays: the URL sits in a selectable field with Copy Link, Open and a dismiss, the link is still on the clipboard the moment the card appears, and the card materializes on one critically damped spring, scale, blur and position together, rather than sliding ten pixels on a timed fade
- **The recording bar remembers only positions you chose**: Dragging the bar saves where you put it, but programmatic repositioning no longer counts as a drag, so an automatic placement can no longer be saved and then restored forever. A saved position is also only reused when it fits entirely on a screen
- **Roomier recording bar**: Taller controls, wider spacing between them, more generous padding around the edges, and a softer corner radius. The bar now sits centered above the bottom of the screen with clearance instead of hugging the bottom edge
- **Reduce Motion is respected**: The recording bar's show and hide animations fall back to an instant transition when `accessibilityDisplayShouldReduceMotion` is set
- **Pause and resume rebuilt**: Pausing now compacts presentation timestamps properly instead of leaving a gap, so paused time no longer stretches the exported timeline
- **Restart keeps your source**: Restarting a recording replays whatever you were capturing, including the region you selected, instead of always restarting full screen
- **Capture callbacks off the main actor**: The `SCStream` wrapper is `NSLock`-guarded so ScreenCaptureKit callbacks stay off the main actor under Swift 6 strict concurrency
- **New inspector sliders in both editors**: Padding, Corner Radius, Shadow, Redaction Density, and Zoom Amount are now label-in-track scrubbers instead of stock macOS sliders. The whole row is draggable, so there is no thumb to chase; hovering reveals calibrated tick marks and the current position; and the value beside it is an editable field, so you can type an exact number, or nudge with the arrow keys. Shared by the image editor and the video editor so both read as one control system

### Fixed

- **Image share upload**: Sharing a screenshot that had no annotations silently did nothing, because the editor only uploaded after a successful re-render of edits. An untouched screenshot now uploads the original file, so every image gets compressed, published to your R2 bucket, and hands you a link, exactly like video sharing
- **Default Look actually applies**: The background, padding, and corner radius chosen in Settings > Default Look now seed both the image editor and the Recording Studio. A saved editor document or an explicit style preset still wins, and an untouched Default Look leaves the editors on their own defaults
- **Recordings missing from Settings**: The two history stores were writing incompatible data to the same `history.json`, so each save wiped the other's records. The editor history moved to its own `editorHistory.json` with a one-time migration, and Settings > Recordings now reads the recording packages on disk directly, so every recording, including ones made before this release, shows up in the list
- **Delete stays in sync**: Deleting a recording from Settings removes the whole recording package and its editor project, and deleting from the editor history clears the matching Settings entry, in both directions without leftovers
- **Version shown in the app matches the release**: The build was stamping a version hardcoded in the project file instead of the one in `version.json`, so the menu bar kept saying the wrong number. Every build now syncs its version and build number from `version.json`, and `make run` restarts the app instead of foregrounding the stale copy
- **Dragging the preview hands over the real file**: Dragging a capture out of the floating preview used to give receivers a temporary copy under `~/Library/Caches`, so drops referenced a cache file that could vanish. The drag now delivers the original file itself
- **Export can no longer fire on a failed load**: If the editor opens on a file that has gone missing, Export and Share now disable instead of running and failing with a confusing error
- **Annotations have a visible Delete button**: The image editor toolbar gained a Delete button that removes the selected annotation, enabled only when something is selected. The Delete key still works as before
- **Recording no longer crashes the moment it starts**: With the face cam on, the very first camera frame killed the app. The sidecar writer opened its file before attaching the video input, and `AVAssetWriter` throws an uncaught exception for any input added after `startWriting`, so recording died on frame one with an abort rather than an error. The input is attached first and the file opened second, and appending a frame now happens under the same lock that retires the writer, so stopping a recording can no longer land a frame on an input that has already been finished
- **The face cam mouth matches the microphone**: The cam file was written by one object and timed by another. `AVCaptureMovieFileOutput` decided the sidecar's own zero from the first frame it managed to write, while a second video output reported the first frame it saw, which arrives several frames earlier while the movie writer is still starting up. The editor lined the cam up against that earlier instant, so the face ran ahead of the voice by a variable tenth to a third of a second. The cam is now written by an asset writer fed from the same video output that reports the clock, so the frame that starts the file is the frame the offset is measured from, and the editor's preview resyncs at 80 ms of drift instead of 150 ms
- **The pointer size slider does something**: The drawn cursor was rendered at about three quarters the size of a real macOS pointer and the slider stopped at 2x, so moving it looked like nothing happened. The pointer now starts life-size and the slider runs to 3x
- **Click highlights are visible**: The ring was drawn in plain white for 0.42s, which is invisible on a light window. It now carries a dark halo under the white stroke and lingers 0.55s, in the preview and the export alike
- **Color presets apply while paused**: Picking a grade with the player stopped repainted nothing, because the preview kept the first filter chain it built and the follow-up seek landed on the frame it was already showing. A paused player now gets a fresh chain per change, so every preset shows on the canvas rather than only in its swatch
- **Zoom no longer needs a switch**: The zoom inspector acts on cues directly rather than gating them behind a toggle
- **Exports stop failing silently**: The frame pump treated a reader that gave up mid-render exactly like a reader that finished, so a failed read marked the inputs done and the writer closed a truncated or empty file. It now surfaces the reader's own error, and an export that produced no frames fails instead of writing a stub
- **Export failures say what went wrong**: “The operation could not be completed” is AVFoundation's placeholder, not a diagnosis. The toast now carries the failure reason, the underlying error, and the domain and code behind it
- **Saving to a protected folder reports itself**: The render lands in the temporary directory and only the finished file moves to your save folder, so a Desktop or Documents permission block reads as “could not be saved to /Users/you/Desktop” instead of an opaque AVFoundation code
- **Every recording crashed the instant it started**: A closure written inside a `@MainActor` function inherits main-actor isolation unless its parameter type is `@Sendable`. The pointer sampler's timer handler, the three ScreenCaptureKit sample callbacks, and the updater's download delegate were all assigned that way and then invoked on background queues, so Swift 6's isolation check raised `EXC_BREAKPOINT` on the first pointer sample of every recording, in every mode. All of them are now explicitly `@Sendable`, and the capture callbacks moved behind the stream's existing lock, which also removes an unsynchronized read and write of those properties
- **Every capture was stored up to three times**: A screenshot kept its original in Application Support, its beautified export in the save folder, and a byte-identical second copy of the original under `BetterShot/bases/`. The editor now maps an export back to the original through history instead of that duplicate, recordings are referenced where they are written rather than copied into Application Support (which cost a full second copy of every video), and re-exporting from either editor updates the existing history entry instead of importing another copy ([#99](https://github.com/KartikLabhshetwar/better-shot/issues/99))
- **History grew without limit**: History now keeps the 100 most recent captures by default, configurable in Settings > General > History (50 to 500, or unlimited). Trimming removes only the originals BetterShot keeps in Application Support, never files in your save folder. Leftover copies in `BetterShot/bases/` from earlier versions are pruned at launch ([#99](https://github.com/KartikLabhshetwar/better-shot/issues/99))
- **Share uploaded the raw recording**: The Share button uploaded the original capture, so trim, crop, zoom, and background effects were silently dropped from every shared link. It now renders your edits into a temporary file, uploads that, and cleans up afterwards. Unedited recordings still upload the original file with no re-encode
- **Recording bar sat in the bottom-left corner**: The bar measured itself by casting its content view to `NSHostingView<RecordingBarRootView>`, but the view is built with an `.environment` modifier applied, so the real type is `NSHostingView<ModifiedContent<...>>` and the cast always failed. The measurement guard returned early and the bar's frame was never set at all, leaving it at its construction origin in the bottom-left corner. It now measures through `NSView.fittingSize`, which needs no cast, and centers above the bottom edge
- **Microphone and camera entitlements were wiped on every project regeneration**: `project.yml` owns `BetterShot.entitlements`, so XcodeGen rewrote the hand-added microphone entitlement back to an empty dictionary each time the project was regenerated. Both device entitlements are now declared in `project.yml` and survive regeneration
- **Valid R2 credentials reported as invalid**: Test Connection signed a request against the bucket root, which needs list permission that an Object Read & Write token does not have. It now probes an object key inside the bucket instead
- **Zoom followed the cursor to the wrong place on region recordings**: Pointer samples are captured in Quartz global coordinates, but the region rect was being converted to AppKit coordinates before being handed to the sampler, so zoom tracked an inverted Y position on any area recording
- **History and Videos tabs stuttered while scrolling**: `HistoryStore` is `@MainActor`, so thumbnail decoding hopped back onto the main actor and ran `CGImageSource` and `AVAssetImageGenerator` work there. Decoding is now genuinely off the main actor
- **Full-size decode after every screenshot**: The floating preview card decoded the entire screenshot on the main actor for a 130x98 point card, roughly 60 MB per shot on a 5K display. It now decodes a 260 px thumbnail off the main actor
- **Updater leaked a URLSession**: A delegate-based `URLSession` was never invalidated, so it and its delegate outlived every update download ([#90](https://github.com/KartikLabhshetwar/better-shot/pull/90), thanks [@zergzorg](https://github.com/zergzorg))
- **Video editor leaked AVPlayer time observers**: The previous observer was not released when loading a new video ([#91](https://github.com/KartikLabhshetwar/better-shot/pull/91), thanks [@zergzorg](https://github.com/zergzorg))

### Known limitations

- Auto-zoom overrides manual crop at export: when zoom is enabled, the crop rectangle is ignored
- The face cam bubble is captured from the screen, so it appears in full screen and area recordings but not in single-window recordings, which capture only that window's own content
- Zoom cues are derived from clicks, so a recording with no clicks produces no cues

## [0.3.7] - 2026-06-07

### Added

- **Screen recording**: Record your screen as MP4 video with ScreenCaptureKit. Includes a floating status bar with timer, pause/resume, stop, and discard controls. Access via the new "Record" button in the menu bar or `⌘⇧2`
- **Restart recording**: New restart button in the recording status bar, cancels the current recording and immediately starts a new one
- **Recording pill redesign**: Minimal icon-only controls (pause, stop, restart, discard) with solid dark background, proper SwiftUI observation for live timer updates, and auto-sized panel
- **Video editor with effects**: Full video editor with padding, corner radius, shadow, and background picker (solid colors, gradients, macOS wallpapers, custom images), matching the image editor's inspector sidebar. Trim timeline with thumbnail strip, transport controls, and export with effects baked in
- **Recording settings tab**: Dedicated settings panel for recording preferences: FPS (24/30/60), show cursor, capture audio, and open editor after recording toggles
- **Record Screen keyboard shortcut** (`⌘⇧2`): Configurable global hotkey for screen recording, shown in Capture settings alongside screenshot shortcuts
- **Separate History and Videos tabs**: Screenshots and recordings are now in separate tabs in Settings. History shows only screenshots, Videos shows only recordings, each with their own clear button and appropriate actions (preview for screenshots, open in editor for recordings)
- **Preview panel for recordings**: After stopping a recording, the floating preview overlay appears (same as screenshots). Click it to open the video editor
- **Drag-to-app from preview**: Dragging from the floating preview card now provides the actual file URL, enabling drop into apps like Figma, Slack, and Finder
- **App appearance setting**: Choose between System, Light, and Dark mode in Settings > General > Appearance. The app no longer forces light mode and respects your macOS setting by default
- **Recent menu with sub-menus**: Single "Recent" button in the menu bar with nested "Screenshots" and "Recordings" sub-menus, each with their own clear option
- **Image crop**: Crop screenshots in the editor with draggable corner and edge handles, dark mask overlay, and rule-of-thirds grid. Crop is applied on export; annotations remain editable on the full image
- **Video crop**: Crop recordings in the video editor with the same overlay UX. Crop is baked into the exported MP4 via AVMutableVideoComposition transform
- **MP4 recording and export**: Screen recording now records directly as MP4 instead of MOV. Video editor also exports as MP4
- **Changelog page**: Dedicated `/changelog` page on the landing site, auto-generated from CHANGELOG.md (single source of truth)

### Fixed

- **Race condition: `BundledBackgrounds.ImageCache`**: Added `NSLock` to the `@unchecked Sendable` image cache dictionary: concurrent access from multiple threads could crash
- **Race condition: `ShortcutService.cachedShortcuts`**: Protected the static shortcut cache with `NSLock`: the CGEvent tap callback reads it from an arbitrary thread while the main actor writes it
- **Race condition: `RecordingSession.appendVideoSample`**: Moved `writer.startSession(atSourceTime:)` outside the lock to avoid calling AVAssetWriter while holding the lock
- **Race condition: `ScreenRecordingManager` stop/cancel**: Added `.stopping` state guard so concurrent stop calls (e.g. user taps stop while stream error fires) can't both proceed
- **Memory leak: `RecordingStatusBarController`**: Panel was never set to `nil` on dismiss, leaking the NSPanel and its SwiftUI view hierarchy
- **Memory leak: `PreviewOverlay`**: Panel was never released on dismiss, accumulating stale panels
- **Memory leak: `VideoEditorModel.generateThumbnails`**: Changed `Task.detached` to use `[weak self]` to prevent retaining the model after window close
- **Recording timer stuck at 00:00**: `ScreenRecordingManager.shared` was stored as `let` (plain constant): SwiftUI's `@Observable` tracking requires `@State` to trigger re-renders
- **Recording pill invisible/clipped**: Panel used a hardcoded `contentRect` that didn't match SwiftUI content size. Now uses `hostingView.fittingSize` for exact sizing
- **Recording saved to wrong location**: Raw video now stays in the user's save directory after stopping: `importCapture` uses `deleteSource: false` so the file isn't moved away
- **Filename collision on rapid capture**: `HistoryStore.importCapture` now appends a UUID suffix when a file with the same millisecond timestamp already exists
- **Orphaned files on delete**: `deleteRecord` and `deleteAllRecords` now clean up beautified files and base images, not just the raw capture
- **Crash on headless display**: `CountdownOverlay` accessed `NSScreen.screens[0]` without bounds checking, changed to safe `.first` with guard
- **Zero-duration thumbnail generation**: `VideoEditorModel.generateThumbnails` now guards against `duration == 0` to prevent generating 20 useless thumbnails at time zero
- **Windows open on wrong screen**: Editor, video editor, settings, preview overlay, recording status bar, toast, and pinned screenshots now open on the same screen where the menu bar icon was clicked. Previously, all windows sampled `NSEvent.mouseLocation` after the popover dismissed (too late) or hardcoded `NSScreen.main`, causing them to appear on the primary display instead of the active one. The originating screen is now captured from the status bar button before dismissal and threaded through to all window controllers
- **Recording pill visible in recordings**: The floating recording status bar (timer, pause, stop, discard) was being captured in screen recordings. Fixed by setting `sharingType = .none` on the panel so ScreenCaptureKit excludes it from capture
- **Export deletes files from save directory**: Exporting from the screenshot or video editor was deleting the exported file from the save directory via `importCapture(deleteSource: true)` and a redundant `removeItem` call. Now only the old history store record is cleaned up; the exported file stays in the save directory
- **Recent recordings open editor directly**: Clicking a recording in the Recent menu now shows the floating preview overlay (with edit, pin, copy, dismiss actions) instead of jumping straight into the video editor, matching how recent screenshots behave
- **Annotation export positioning**: Annotations (arrows, rectangles, text, all tools) now render at the correct position in the exported image, matching the canvas preview. The export renderer previously used independent Y-axis math from the SwiftUI canvas. Fixed by flipping the CG context to Y-down for annotation rendering, using the same coordinate formulas as the canvas preview
- **Annotations mispositioned with crop**: When crop was active, annotations were rendered using coordinates normalized to the original image size, but the renderer was given the cropped image. Annotations are now remapped from original-image to cropped-image coordinate space before export
- **Duplicate file on Desktop**: Screenshots no longer create a visible `.base` companion file on the Desktop. The raw source image used for re-editing is now stored internally in Application Support, so only the beautified screenshot appears in the save directory
- **Video export missing background**: Background was invisible in exported videos because `AVMutableVideoCompositionInstruction.backgroundColor` defaulted to opaque black, covering the background layer. Fixed by setting it to clear and applying corner radius via `CAShapeLayer` mask on the video layer
- **Video editor not loading default effects**: Video editor now loads user-configured defaults from `AppPreferences.defaultBeautifierConfig` on open, matching the image editor behavior
- **Preview pin button position**: Moved the pin button from bottom-left (next to pencil) to bottom-right corner of the preview overlay
- **Video trim handles**: Fixed coordinate space bug where trim handle drag gestures used the handle's local 8px frame instead of the timeline's coordinate space, making handles unresponsive or inaccurate
- **Recording dimensions in history**: Videos tab now shows correct pixel dimensions instead of "0 x 0": video track dimensions are read via AVFoundation on import

### Removed

- **Auto-export with effects on recording stop**: Removed `VideoEditorModel.autoExportWithDefaults`: recordings are now saved as raw video immediately. Effects (background, padding, corner radius, shadow) are only applied when the user explicitly exports from the video editor. This eliminates the long delay between stopping a recording and seeing the preview
- **Dead code cleanup**: Removed `CountdownOverlay.activeCountdownTask` (was assigned then immediately awaited, served no purpose)

### Changed

- **Recording pill UI**: Icon-only buttons (no text labels), solid `Color(white: 0.1)` background instead of `.ultraThinMaterial`, forced dark color scheme, hover-only button highlights
- Version bumped to 0.3.7 (build 10)

## [0.3.6] - 2026-06-06

### Added

- **Reset to Defaults in Settings**: Added reset buttons throughout settings: "Reset Effects to Defaults" in Default Background section, "Reset All General Settings to Defaults" at the bottom of General tab, "Reset Shortcuts to Defaults" in Keyboard Shortcuts section, and "Reset All Capture Settings to Defaults" at the bottom of Capture tab
- **Preview overlay settings restored**: Position (bottom-right/bottom-left) and auto-dismiss delay (2–15s) are back in Capture settings
- **Shortcut recorder fix**: Recorder now temporarily disables the CGEvent tap so system shortcuts like ⌘⇧4 can be captured without triggering the native macOS screenshot. Uses a local event monitor instead of `keyDown`

### Improved

- **Tab state preserved in settings**: Settings tabs now use ZStack with opacity toggling instead of Group/switch, preserving state when switching between tabs
- **Async history thumbnails**: History tab loads thumbnails asynchronously to avoid blocking the UI on large capture histories

### Fixed

- **Scrollbar hidden in settings**: Removed visible scrollbar from the settings content area
- **Editor & Settings Space switching**: `orderFrontRegardless` before the activation policy change prevents macOS from switching to Desktop

### Changed

- Version bumped to 0.3.6 (build 9)

## [0.3.5] - 2026-06-06

### Changed

- **Inspector panel moved to the left**: The editor inspector (tools, style, effects, background) is now on the left side of the editor window, canvas on the right
- **Recent captures open preview instead of editor**: Clicking a recent capture in the menu bar now shows the floating preview panel instead of opening the editor directly, matching the normal capture flow
- **README updated**: Removed hardcoded version numbers, added Homebrew install instructions, updated feature descriptions to reflect all current capabilities
- **Landing page updated**: Added color picker, self-timer, QR/barcode scanning, spotlight, customizable shortcuts, workflow extras section, and Homebrew install to the landing page. Removed version number from hero badge
- **CONTRIBUTING.md updated**: Editor flow diagram and key files table updated to reflect left-side inspector panel
- **llms.txt rewritten**: Replaced incorrect tech stack (React/Tauri/TypeScript) with accurate Swift 6/SwiftUI architecture and complete feature listing
- Version bumped to 0.3.5 (build 8)

## [0.3.4] - 2026-06-06

### Added

- **Automatic update check on launch**: App checks GitHub releases on startup and shows a toast notification when a new version is available. A blue dot badge appears next to the version label in the menu bar
- **Smart toast after capture**: Toast now shows "Screenshot saved & copied!" when clipboard copy is enabled, or "Screenshot saved!" otherwise

### Changed

- **Simplified capture flow**: Screenshots now always apply default settings (background, padding, corner radius, shadow) and save directly to the gallery. No more editor-first or preview-first workflow, just capture, auto-beautify, and save
- **Removed screenshot mode picker**: The Editor/Gallery segmented control is removed from the menu bar. Default effects configured in Settings are always applied automatically
- **Preview panel restored**: Both a toast notification and the floating preview panel now appear after taking a screenshot
- **Removed overlay settings**: Overlay position and dismiss delay settings removed from Capture settings since the floating preview is no longer shown after capture
- **Recent captures open in editor**: Clicking a recent capture in the menu bar now opens it in the editor instead of showing a floating preview
- Version bumped to 0.3.4 (build 7)

### Fixed

- **Crash on window close**: Fixed `EXC_BREAKPOINT` crash in `_postWindowNeedsUpdateConstraints` caused by `setActivationPolicy(.accessory)` triggering layout updates on a window mid-teardown. Deferred activation policy change to the next run loop iteration for editor, settings, and toast windows
- **Double background on editor open**: A `.base.png` copy of the raw capture is saved alongside every beautified output. The editor now resolves to the base image before loading, making it architecturally impossible to apply background/padding/shadow twice, regardless of which URL is passed to the editor
- **Race condition fixes across the codebase**: Fixed multiple race conditions that could cause crashes:
  - Menu bar popover: eliminated Task wrapper in close animation, captured panel reference before nil'ing to prevent use-after-free
  - Editor window delegate: replaced `Task { @MainActor }` with `DispatchQueue.main.async` for deterministic ordering during window teardown
  - Shortcut service: cached shortcuts on main thread to prevent `@MainActor`-isolated property access from CGEvent tap callback thread
  - Toast window: added generation counter to prevent stale animated-dismiss completion handlers from nil'ing a newly created panel
  - Countdown overlay: added cancellation guard against concurrent `showCountdown` calls that could stack overlapping countdowns
  - Preview overlay: cancel pending dismiss task at the start of `show()` to prevent a stale dismiss from hiding a freshly shown preview
  - Menu bar event monitor: replaced `Task { @MainActor }` with `DispatchQueue.main.async` for consistent dispatch ordering

### Removed

- **Screenshot mode preference** (`ScreenshotMode` enum): No longer needed since capture always uses gallery mode with auto-applied defaults
- **"Show floating preview after capture" toggle**: Removed from General settings

## [0.3.3] - 2026-06-06

### Added

- **Settings sidebar navigation**: Redesigned preferences from top tabs to a left sidebar with right content panel
- **Keyboard shortcut recorder**: Click any shortcut badge to record a new key combination (press Escape to cancel)
- **Default effects configuration**: Padding, corner radius, shadow, and background are now configurable directly in Settings and persist across sessions
- **Live settings preview**: Default Effects section shows a real-time mini preview of how screenshots will look with current padding, corner radius, shadow, and background
- **macOS wallpapers in settings**: Default Background picker now includes bundled macOS wallpaper thumbnails alongside solid colors and gradients
- **Custom image backgrounds in settings**: "Custom Image..." button in Default Background picker lets you choose any image file as your default background
- **Click preview to open editor**: Clicking the floating preview overlay opens the editor
- **Window capture**: Click-to-select window capture available from the menu bar
- **OCR toast notification**: After OCR copies text to clipboard, a toast confirms "Text copied to clipboard"
- **Color picker toast notification**: After color picker copies hex to clipboard, a toast confirms "#HEXCODE copied to clipboard"
- **Custom menu bar popover**: Replaced SwiftUI `MenuBarExtra` with a custom `NSPanel`-based popover with arrow, smooth spring animation, and click-outside-to-dismiss

### Fixed

- **Blur/pixelation invisible in editor**: Fixed `viewScale ≈ 0.16` being multiplied into blur radius and pixel block size, making effects sub-pixel in the canvas preview. Blur radius no longer scales; pixelation computes blocks from view dimensions
- **Spotlight annotation drift**: Canvas preview used `imageFrame` for overlay extent but export used `fullCanvasRect`. Fixed by passing `canvasFrame` through to SpotlightPreview
- **Laggy editor sliders**: Replaced CGContext-based preview render loop with SwiftUI-native layers (CanvasBackgroundView, CanvasScreenshotView), eliminating re-render on every slider change
- **OCR not firing from menu bar**: `dismiss()` was cancelling the async capture task. Fixed by using `Task.detached` so capture survives popover teardown
- **Settings not opening from menu bar**: `@Environment(\.openSettings)` doesn't work from a custom `NSPanel` outside SwiftUI's scene system. Created `SettingsWindowController` that directly manages an `NSWindow` with `PreferencesView`, matching the `EditorWindowController` pattern
- **Editor opens on wrong screen/Space**: `NSApp.activate(ignoringOtherApps:)` would switch macOS Spaces to where the app was last active (typically Desktop). Added `.moveToActiveSpace` collection behavior to editor and settings windows so they appear on the user's current Space
- **Settings sidebar toggle on wrong side**: Sidebar toggle button appeared on the right side of the title bar when hosted in `NSHostingView`. Fixed by adding an `NSToolbar` with `.toggleSidebar` item to the settings window
- **History icon disappearing**: Menu bar "Recent Captures" and dividers no longer vanish when capture history is empty
- **Background picker in settings**: Cleaner grid layout with proper "None" swatch (strikethrough icon)
- **Preview click-to-edit**: Clicking anywhere on the floating preview (including the hover overlay) now opens the editor
- **Custom background image**: Fixed file picker for custom wallpaper backgrounds in editor
- **GitHub link in About tab**: Corrected URL to `KartikLabhshetwar/better-shot`

### Changed

- **Menu bar icon redesigned**: Converted to a proper template image (black on transparent) that automatically renders white in dark mode and black in light mode, matching native macOS menu bar icon behavior. Icon now fills the full menu bar height instead of being undersized
- **Menu bar redesigned**: Custom `NSPanel` popover with arrow, 2-column grid buttons (Region, Screen, Window, Pick Color), screenshot mode toggle (Editor/Gallery), utility grid (OCR, Recent Captures), and footer grid (Settings, Quit). Shortcut badges on each button
- **About page redesigned**: Left-aligned sectioned layout (Updates, Project, Credits) with horizontal icon+title header. Includes GitHub and X links
- **Settings window enlarged**: 680×560 (was 620×440) so Default Effects preview and sliders are visible without scrolling
- **Settings window title**: Shortened to "Settings" (was "BetterShot Settings") to prevent title bar truncation
- **Toast notifications generalized**: `ToastWindow` now accepts a custom title (was hardcoded "Saved") and supports SF Symbol icons alongside app icons
- **Color picker feedback**: Replaced the cursor-anchored dark HUD panel with a standard toast notification matching the app's toast style
- **Editor canvas rewritten**: SwiftUI-native rendering with `CanvasBackgroundView` and `CanvasScreenshotView` instead of CGContext re-renders. `UnevenRoundedRectangle` for per-corner radius clipping
- **Capture engine rewritten**: Region, fullscreen, and window capture now use the native macOS `screencapture` CLI for maximum reliability across all displays and configurations
- **Layout section improved**: Single "Ratio" row with dropdown, larger alignment grid with 28pt cells and hover highlights
- Default beautifier config now uses a centralized `AppPreferences.defaultBeautifierConfig` accessor across editor, settings, and auto-apply

### Removed

- **Pixelate annotation tool**: Removed from the toolbar (blur tool remains). Keyboard shortcut `P` removed
- **"Save as Default" button**: Removed from editor Effects section; defaults are now managed in Settings
- **Bundled background images**: Removed Wallpapers and Gradients image assets from the editor. Only solid colors, code-generated gradients, macOS assets, and custom images remain
- **Repeat Region shortcut from settings**: Removed from the Keyboard Shortcuts section in Capture settings

## [0.3.2] - 2026-06-03

### Added

- **In-app auto-update**: Updates now download the DMG in-app with a progress bar, mount it, replace the running app, and relaunch. No more opening Chrome to download manually. New states: downloading (with cancel), ready to install, installing.
- **Makefile**: `make build`, `make run`, `make dmg`, `make release`, `make clean`, `make lint`, `make test-build`, `make version` for local development and testing without opening Xcode.

### Fixed

- **History tab empty state not centered**: `ContentUnavailableView` was inside a `List`, constraining it to a row. Moved it outside the `List` with `frame(maxWidth: .infinity, maxHeight: .infinity)` so it centers properly in the tab.

## [0.3.1] - 2026-06-03

### Fixed

- **Window capture not working**: The window picker used a plain `NSWindow` with borderless style, which can't become key; mouse and keyboard events were unreliable. Replaced with a custom `PickerWindow` subclass that overrides `canBecomeKey`/`canBecomeMain`, matching how the region selection overlay works.
- **Window picker hit-test**: Replaced NSScreen-based coordinate conversion with `CGEvent.location` for reliable cursor-to-window matching across all monitors.
- **Window capture stale reference**: After the picker closes, the app now re-fetches `SCShareableContent` and looks up the selected window by ID to get a fresh `SCWindow` reference before capturing.

## [0.3.0] - 2026-06-03

### Added

- **In-app update checker**: Check for Updates button in Preferences > About that queries GitHub releases API and links to the latest download
- **Version tracking**: `version.json` file at project root for release management
- **Professional annotation system**: Complete rewrite of annotation tools
  - **Interactive canvas**: Annotations render as live SwiftUI views: click to select, drag to move, handles to resize
  - **Selection system**: Single select, multi-select (Shift/Cmd+click), marquee drag selection, select all (Cmd+A)
  - **Curved arrows**: Quadratic Bézier arrows with draggable curve control handle and snap-to-straight
  - **Live text editing**: Text annotations use inline NSTextView with full font family, size, bold/italic/underline, and alignment controls
  - **Numbered circles**: Auto-incrementing numbered badges with proper outline and contrast text
  - **Redaction tools**: Pixelate and blur with adjustable density slider and cached preview generation
  - **Resize handles**: Corner handles for shapes, endpoint handles for lines/arrows, curve handle for arrows
  - **Color picker**: 10 named color presets with popover selector + custom ColorPicker
  - **Stroke width picker**: Visual popover with 5 presets (2/4/6/8/12px)
- **Aspect-ratio locking**: Hold Shift while drawing rectangles/ellipses to constrain to square/circle
- **Arrow snap-to-straight**: Arrow curves snap to a straight line when dragged near the start-end axis
- **Color Picker** (Cmd+Shift+C): Uses macOS native `NSColorSampler` for pixel-perfect color picking on any monitor. After picking, a floating HUD shows the color swatch and hex code (#RRGGBB) near the cursor. Hex is copied to clipboard.
- **OCR with QR/Barcode detection**: The OCR capture action now runs both `VNRecognizeTextRequest` and `VNDetectBarcodesRequest` together. Detects QR codes, barcodes, and text in a single pass. QR/barcode payloads appear first in the copied result.
- **Delayed Screenshot countdown overlay**: When the self-timer is set, a fullscreen translucent overlay shows large countdown numbers (3, 2, 1) with scale-down and fade animation. The overlay dismisses before the screenshot fires so it never appears in the capture.
- **Spotlight annotation tool** (G): Darkens everything outside a selected rectangular region to draw focus. Adjustable opacity via the density slider. Uses even-odd fill for both SwiftUI preview and CGContext export rendering.
- **Pinned Floating Screenshots**: Pin any capture as a borderless, always-on-top floating window. Drag to move anywhere, scroll wheel to resize (0.25x–4.0x), hover to reveal close button. Pin from the floating preview card or from the editor. "Unpin All" appears in the menu bar when pins exist.
- **Layout controls**: New LAYOUT section in the editor inspector with aspect ratio dropdown (Auto, 1:1, 4:3, 3:2, 16:9, 9:16) and a visual 3x3 alignment grid picker. Canvas expands to fit the selected ratio without cropping the image.
- **Canvas Expansion**: Annotations can now be drawn into the padding area beyond the screenshot boundaries, enabling margin annotations and callouts outside the image.
- **Repeat Area Capture** (Ctrl+Cmd+Shift+4): Re-captures the exact same screen region as your last region capture without reselecting. Falls back to normal region selection if no previous region exists.
- **Image Overlay** (Cmd+Shift+V): Paste any image from clipboard onto the current screenshot. The pasted image is composited at center, scaled to fit within 80% of the canvas.
- **Option+Drag to Duplicate**: Hold Option and drag any annotation to create a copy. The original stays in place while the duplicate moves with the cursor.
- **Persistent Tool Selection**: The text tool now stays armed after committing a text annotation, so you can immediately click to place another text box without reselecting the tool.
- **Expanded keyboard shortcuts**: V (select), R (rectangle), F (filled rectangle), O (ellipse), L (line), A (arrow), D (freehand), N (numbered circle), P (pixelate), B (blur), G (spotlight), T (text)
- **Toast notifications**: Editor shows a brief HUD when exporting ("Exported"), copying ("Copied to clipboard"), or saving defaults ("Saved as default"). Auto-dismisses after 1.5 seconds.
- **Save as Default**: Button in the Effects section saves current padding, corner radius, shadow, background, alignment, and aspect ratio as the default for all new captures.
- **Export preserves in history**: Exported images (with annotations baked in) are added to Recent Captures so reopening shows the final result, not the raw capture.
- **Save directory picker**: Replaced the raw text field with a native macOS folder picker (`NSOpenPanel`) in Preferences.

### Fixed

- **Menu bar icon template rendering**: Changed `template-rendering-intent` from `"original"` to `"template"` so the icon adapts to light mode, dark mode, and high-contrast accessibility settings, matching how native macOS system utilities render menu bar icons
- **Keyboard shortcut override**: Fixed the accessibility permission flow: the CGEvent tap now only registers after accessibility permission is confirmed, with polling to detect when the user grants permission
- **Annotation coordinate system**: Gesture tracking now normalizes against the actual image display rect (accounting for aspect-fit letterboxing), not the full view bounds
- **Blur edge darkening**: Export-time Gaussian blur now pads the crop rect by `ceil(radius * 2)` on all sides before applying the filter, eliminating fringe artifacts at region boundaries
- **Export redaction performance**: Replaced per-item `ctx.makeImage()` (full canvas snapshot for each blur/pixelate region) with a single shared canvas snapshot, reducing export time proportionally to the number of redaction annotations
- **Spotlight export positioning**: Rewrote `AnnotationDrawing` to use explicit `imageRect`/`fullCanvasRect` parameters instead of context translation. Spotlight overlay now correctly covers the full canvas while the cutout aligns with the image position.
- **Annotation export positioning**: All annotations now render at the correct position within the canvas padding area, not offset by the image origin.
- **Multi-monitor capture**: Fullscreen and region capture now correctly identify the display under the cursor using `CGEvent.location` and `CGDisplayBounds` instead of NSScreen coordinate conversion.
- **Settings reactivity**: Capture settings (self timer, overlay position, dismiss delay, export format/quality) now use `@AppStorage` so changes reflect immediately in the UI.
- **Alignment Y-axis**: Fixed inverted Y-axis in the export renderer: clicking "bottom" in the alignment grid now correctly places the image at the bottom of the canvas.

### Changed

- **Menu bar UI redesigned**: Grouped by intent: "Open Last Capture" quick access at top, capture modes (Region, Full Screen, Window), utilities (OCR, Color Picker), contextual actions (Unpin All when pins exist), Recent Captures submenu (up to 8 items). Removed "Check for Updates" from menu (lives in Preferences > About). Shortened labels.
- **Inspector panel redesigned**: Sidebar with sections for Tools, Style, Text, Effects, Layout, and Background, each with proper spacing, section headers, and dividers
- **Canvas rendering**: Annotations now render directly as SwiftUI views on the canvas (not baked into a preview image), enabling real-time interaction without re-render delays
- **Live beautifier preview**: Canvas shows the full rendered preview (background, padding, shadow, corner radius) with a 30ms debounced render pipeline. Redundant re-renders are skipped when config hasn't changed.
- **Performance optimizations**: Cached font family list (static lazy), TransparencyGrid rasterized via `.drawingGroup()`, arrow hit-test sampling halved (32→16 points), text style dirty-check guards redundant `setAttributes` calls, GPU memory cleanup after blur export
- Version bumped to 0.3.0
- Deployment target remains macOS 14.0
- Simplified BetterShotDelegate, removed all video recording callback and frame extraction code

### Removed

- **Screen recording**: Removed ScreenRecorder, VideoProcessor, RecordingControlPanel, and the bundled videokit binary. Video features will return in a future release
- **Old annotation system**: Replaced `ColorSwatch`, `StrokeWidth` enum, `AnnotationGestureView`, and basic `AnnotationItem` with the full interactive model

## [0.2.0] - 2026-06-02

### Added

- **Native Swift/SwiftUI rewrite**: Complete rewrite from Electron/Rust to pure Swift/SwiftUI + Go for video processing
- **Screen recording**: Full screen and window recording via ScreenCaptureKit
  - Floating control pill with pause/resume, stop, and discard controls
  - Pulsing red dot indicator with MM:SS timer
  - HEVC encoding at 60fps Retina resolution
  - Post-recording compression via videokit (FFmpeg)
  - Recordings saved to user's configured save directory
- **Preview overlay with editor access**: Floating preview card appears after capture
  - Hover to reveal actions: edit (pencil), delete, dismiss
  - Copy and Save pill buttons
  - Draggable thumbnail
  - Clicking pencil icon opens the annotation editor
- **Annotation editor window**: Opens from preview overlay with full beautifier controls
  - Switches app to regular activation policy (visible in Dock/Cmd-Tab) while editing
- **Override macOS screenshot shortcuts**:
  - Cmd+Shift+3 = Capture Screen
  - Cmd+Shift+4 = Capture Region
  - Cmd+Shift+5 = Capture Window
  - Cmd+Shift+6 = Toggle Screen Recording
  - Cmd+Shift+O = OCR Region
- **Bundled background images**: Wallpapers, mesh gradients, and macOS assets now ship inside the app bundle
- **videokit bundled**: Go-based FFmpeg wrapper included in the app for video compression

### Fixed

- **Background images not loading in editor**: Resources weren't being copied into the app bundle; fixed project config and file lookup to use direct path construction
- **Screenshot sound**: Now plays the actual macOS screenshot sound (`Screen Capture.aif`) instead of the generic "Blow" sound
- **Editor image caching**: Added `.onChange(of: imageURL)` and `.id()` to prevent stale images when editor window is reused

### Changed

- App target deployment raised to macOS 14.0
- Swift 6 strict concurrency throughout

## [0.1.0] - Previous

### Added

- **Background Border slider**: Adjustable padding around screenshots (0–200px)
- **Frontend test framework**: Vitest with React Testing Library (19 tests)
- **Rust unit tests**: CropRegion bounds, filename generation (13 tests)

### Fixed

- Background visible at 0px border setting

### Changed

- Padding now stored in EditorSettings (previously hardcoded to 100px)
