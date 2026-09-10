# BetterShot onboarding

Updated September 10, 2026 for 0.5.1.

1. **Welcome:** a short introduction, Screenshots/Recordings picker, still preview,
   and optional six-second demo. No autoplay, sound, looping, or network dependency.
2. **Permissions:** all five permissions are shown in compact rows, with no
   disclosures. Screen capture is marked Required; Accessibility, Input Monitoring,
   Microphone, and Camera are Optional. Each row shows Allow, Open Settings, Allowed,
   or Restricted. Denied access and previous system requests lead to Settings;
   undecided microphone/camera requests can be retried. Errors stay beside the action.
   No permission or recording input is enabled automatically.
3. **First Capture:** find the menu-bar clover, see the current capture-bar shortcut, then
   open the shared bar or edit a separate practice image in the real editor.

Back, Skip Setup, and Continue remain in a persistent footer. The 760 × 680 window
resizes down to 520 × 560; longer content scrolls. System colors and existing chrome
support light/dark and Reduce Transparency. Demos start only after Watch Demo;
leaving the page stops them, losing app focus pauses them, and enabling Reduce
Motion returns to the still. The same explanation is available as text.

Setup is first-run-only. Before launch writes preferences, `prepareForLaunch`
records a zero seen-version for fresh profiles or marks existing BetterShot profiles
seen. A positive seen-version, including version 1, never triggers setup again.
Skip, close, and completion mark it seen. Neither the menu tray nor Settings exposes onboarding.
The window controller rejects attempts after completion. Permission requests that
may need a relaunch preserve the existing resume flag; explicit dismissal clears it.
Settings permission requests never set it. Grants always come from macOS.
The isolated test pilot disables permission actions and explains that access must
be granted in the actual BetterShot app; it cannot modify real permissions.

## Design reference

[Apple’s onboarding guidance](https://developer.apple.com/design/human-interface-guidelines/onboarding)
informs the brief, optional setup and hands-on practice. The user explicitly asked
to remove reopening controls. The compact native window retains the existing
Raycast-inspired structure without the extra shortcuts slide.

## Hyperframes demos

`docs/onboarding-media/DESIGN.md` defines the neutral visual direction. The two
`index.html` compositions illustrate annotation and video trim/zoom using the
existing coastal photo. They are illustrative examples, not recordings of app UI.
The app bundles only rendered MP4s and PNG posters in `Resources/Onboarding`.

Render with Hyperframes 0.8.33, Node 22+, FFmpeg, and its Chrome renderer. For each
of `screenshot` and `recording`, copy its index.html, DESIGN.md, and
Resources/Onboarding/coast.png into a temporary composition directory. Run:

```sh
npx --yes hyperframes@0.8.33 check /path/to/composition
npx --yes hyperframes@0.8.33 render /path/to/composition --quality high --fps 30 --output /path/to/demo.mp4
ffmpeg -ss 4.5 -i /path/to/demo.mp4 -frames:v 1 /path/to/demo.png
```

Copy the results to `Resources/Onboarding/<kind>-demo.mp4` and `<kind>-demo.png`.
The Swift app has no Hyperframes or JavaScript runtime dependency.

## Artwork

Generated using the built-in image generation tool. No generated logos or action icons.
Original PNGs are bundled in Resources/Onboarding; they are sample content, not product screenshots.

### coast.png

Use case: photorealistic-natural. Asset type: bundled sample photograph for BetterShot macOS onboarding, also used for a hands-on screenshot editing exercise. Create a beautifully composed wide landscape photograph of a quiet rocky coastline with pale blue sea, sage coastal grasses in foreground, a curving path leading toward soft distant cliffs in warm morning light. Editorial travel photography, natural realistic textures, restrained powder blue and sage palette, peaceful and inviting. Landscape 3:2 composition, clear shapes and spacious sky, high detail suitable for full-resolution image editing. No people, no text, no logos, no UI, no watermark, no decorative frame.

### desk.png

Use case: photorealistic-natural. Asset type: second bundled practice photograph in BetterShot macOS onboarding. Create a refined editorial still-life photograph, wide landscape 3:2 format: a matte cream ceramic coffee cup beside an open blank notebook, a graphite pencil and small branch of olive leaves on a warm light grey stone desk. Soft window light from the upper left, realistic paper grain and ceramic texture, gentle clear shadows, calm muted grey, cream and sage palette. Objects arranged asymmetrically with plenty of uncluttered surface. Entire notebook completely blank; no lettering, no logos, no UI, no watermark, no border. High resolution and crisp focus for a screenshot annotation exercise.

## Verification

Run `make test` using the provided BETTERSHOT_TESTING=1 runners. Standalone checks
cover onboarding state and preserved preferences. Editor integration checks
full-resolution practice copies, silent six-second playable videos, 16:9 posters,
permission status/recovery, and compact/light/dark snapshots of every step.

Offscreen snapshots do not validate native video playback, VoiceOver, live capture,
or macOS permission dialogs. Check those on a signed app before release.


September 10 permission-page verification: `make test` passed, including first-run
eligibility, existing-profile migration, permission retry routing, test isolation,
and all five visible rows in compact/light/dark snapshots. The final build and
editor/export integration rerun also passed. The refreshed native pilot shows all
five permission actions and an explicit preview-only explanation, without a
disclosure. Real permission grants and system-triggered restart still require a
signed-app manual check; the pilot never requests those permissions.
