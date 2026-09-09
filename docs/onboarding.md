# BetterShot onboarding (0.5.0, unreleased)

Updated September 10, 2026 for 0.5.0 release preparation.

1. **Screenshots:** native region/window/display capture, OCR, color sampling, annotations, Blur/Pixelate, backgrounds, Save versus Export, and Copy.
2. **Video:** display/window/area recording, optional audio/camera and teleprompter, Stop/Pause/Restart/Discard, timeline editing, inspector tabs, cursor effects, local MOV/MP4 export, and optional R2 sharing.
3. **Permissions:** request Screen & System Audio Recording (needed for capture), Accessibility (global shortcuts), Input Monitoring (precise pointer motion and optional special-key overlays), Microphone, and Camera. Each row explains the feature and offers its own native request and System Settings link. Nothing is requested automatically on entry. Camera/microphone setup reuses RecordingInputAuthorization. Grants never enable recording inputs or key capture in preferences.
4. **Ready:** report whether screen access is available, return to Permissions if needed, open the capture bar or Recording options, or edit one of the two practice images. Sample editing happens after the walkthrough and creates a durable, unique, full-resolution working copy.

Onboarding version 2 covers new users, existing users, and users of the previous
brief guide. Set Up Later, the close button, and completion mark it seen. Permission
requests that may require relaunch persist a resume flag; quitting then reopening
returns to Permissions, including when the guide was reopened manually. Explicit
dismissal clears the flag. Requests made from Settings do not schedule onboarding.
Status always comes from macOS: returning to the app, a two-second refresh while
Permissions/Ready is visible, and Check Permissions Again all recheck the grants.
CoreGraphics preflight APIs cannot distinguish a first request from a denial, so
those rows say Not enabled and offer a settings route. AVFoundation distinguishes
not determined, authorized, denied, and restricted. Restricted access is explained
without prompting. TipKit still teaches Arrow beside its editor control.

## Sources and decisions

- [Apple HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding): brief, optional, interactive learning after launch; easy reopening.
- [Apple HIG: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy): explicit feature-driven permission requests. No launch-time Accessibility prompt; status comes from macOS.
- [Apple: Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos): a normal resizable window, native buttons, keyboard behavior, and the existing menu-bar identity.
- [Apple HIG: Launching](https://developer.apple.com/design/human-interface-guidelines/launching): the introduction is presented after launch setup.
- [Apple TipKit](https://developer.apple.com/documentation/tipkit): one contextual tip, anchored to the control it teaches.
- Reviewed [SwiftUI-Onboarding](https://github.com/Sedlacek-Solutions/SwiftUI-Onboarding), [TourKit](https://github.com/rampatra/TourKit), [PermissionPilot](https://github.com/arpitagarwal1301/PermissionPilot), and [WelcomeWindow](https://github.com/CodeEditApp/WelcomeWindow). No package added: this four-step flow uses existing SwiftUI/AppKit presentation and permission services. Extract a shared package only when another real app needs it.

## Artwork

Generated using the built-in image generation tool. No generated logos or action icons.
Original PNGs are bundled in Resources/Onboarding; they are sample content, not product screenshots.

### coast.png

Use case: photorealistic-natural. Asset type: bundled sample photograph for BetterShot macOS onboarding, also used for a hands-on screenshot editing exercise. Create a beautifully composed wide landscape photograph of a quiet rocky coastline with pale blue sea, sage coastal grasses in foreground, a curving path leading toward soft distant cliffs in warm morning light. Editorial travel photography, natural realistic textures, restrained powder blue and sage palette, peaceful and inviting. Landscape 3:2 composition, clear shapes and spacious sky, high detail suitable for full-resolution image editing. No people, no text, no logos, no UI, no watermark, no decorative frame.

### desk.png

Use case: photorealistic-natural. Asset type: second bundled practice photograph in BetterShot macOS onboarding. Create a refined editorial still-life photograph, wide landscape 3:2 format: a matte cream ceramic coffee cup beside an open blank notebook, a graphite pencil and small branch of olive leaves on a warm light grey stone desk. Soft window light from the upper left, realistic paper grain and ceramic texture, gentle clear shadows, calm muted grey, cream and sage palette. Objects arranged asymmetrically with plenty of uncluttered surface. Entire notebook completely blank; no lettering, no logos, no UI, no watermark, no border. High resolution and crisp focus for a screenshot annotation exercise.

## Verification

Run `make test` with the provided runners (`BETTERSHOT_TESTING=1`).
OnboardingStateCheck verifies first presentation, existing-user presentation, dismissal,
preserved preferences, the version-1 upgrade, permission-restart recovery, and downgrade behavior. EditorUIIntegration checks original-byte
copies, unique working files, write failure, AV permission status mapping, and testing guards.
It renders sixteen snapshots of the four steps in light/dark at 520/680-point widths,
plus two sheets of permission recovery states. The flow adds no animations and reuses the existing chrome
that supports Reduce Transparency; OS accessibility settings need a live check.

Live navigation was checked in an isolated app hosting the production onboarding
with BETTERSHOT_TESTING=1: Screenshots → Video → Permissions → Ready, Return to
advance, scrolling to Camera/Microphone/retry controls, and Review Permissions
returning to the top of setup. The test host cannot request TCC access or read R2
credentials. Closing the window dismissed the guide.

Still required before release: signed-app first launch, Escape/Tab/VoiceOver,
actual permission grant/denial/revocation and system-triggered relaunch, switching
to the real sample editor, and capturing after setup. The automated checks do not
prove these OS interactions.

The website removes launch.mp4 and feature-1.mp4 through feature-4.mp4. It keeps
the shared-recording player, adds first-capture guidance, and labels the new introduction
as coming in 0.5.0. `pnpm build` passes; desktop and 390-point mobile feature layouts were reviewed
in Chrome. `pnpm exec tsc --noEmit` finds four pre-existing nullable `parsed`
errors in components/count-up.tsx (lines 46 and 48); the Next.js configuration skips
type validation during builds. `pnpm lint` cannot run because ESLint is absent
from the project's dependencies. These unrelated issues were left unchanged.

