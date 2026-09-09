# BetterShot onboarding (0.5.0, unreleased)

Updated September 10, 2026 for 0.5.0 release preparation.

1. **Welcome:** a centered clover and short introduction to screenshots and recordings. Start Setup begins; Set Up Later opens the shared bar.
2. **Permissions:** screen access is prominent. A native Optional permissions disclosure contains Accessibility, Input Monitoring, Microphone, and Camera. Existing per-feature request, denial, restriction, and restart recovery controls remain. Nothing is requested automatically; granting access never enables recording inputs or key capture.
3. **Shortcuts:** the capture-bar binding is prominent, followed by region, fullscreen, and recording-options bindings from ShortcutService. Customized bindings and disabled states are preserved. Review Access opens the optional permission controls when Accessibility is missing or shortcuts need a restart.
4. **First Capture:** the bundled menu-bar clover shows where to find BetterShot. Short instructions lead to screenshot or recording capture; two practice photos open unique full-resolution copies in the real editor without screen access. Missing screen permission offers an Enable Access route.

The resizable 760 × 680-point window uses centered content, neutral system colors,
existing frosted chrome, and a persistent footer with Back, accessible step markers,
Set Up Later, and Return to continue. At 520 × 560 points, content scrolls while the
footer stays reachable. No animation or new dependency is added.

Onboarding version 2 covers new users, existing users, and users of the previous
brief guide. Set Up Later, the close button, and completion mark it seen. Permission
requests that may require relaunch persist a resume flag; quitting then reopening
returns to Permissions, including when the guide was reopened manually. Explicit
dismissal clears the flag. Requests made from Settings do not schedule onboarding.
Status always comes from macOS: returning to the app, a two-second refresh while
Permissions/Shortcuts/First Capture is visible, and Check Again all recheck the grants.
CoreGraphics preflight APIs cannot distinguish a first request from a denial, so
those rows say Not enabled and offer a settings route. AVFoundation distinguishes
not determined, authorized, denied, and restricted. Restricted access is explained
without prompting. TipKit still teaches Arrow beside its editor control.

## Sources and decisions

- Inspected the installed Raycast macOS app using Show Onboarding: a centered welcome, focused content, and a persistent bottom progress/action strip. Adapted these patterns to BetterShot’s clover and neutral native chrome. The guide stays optional and avoids Raycast’s decorative motion and longer feature tour.

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
It renders sixteen snapshots of the four steps in light/dark at 520/760-point widths,
plus two sheets of permission recovery states. The flow adds no animations and reuses the existing chrome
that supports Reduce Transparency; OS accessibility settings need a live check.

The redesigned flow passed `make test`, including all sixteen onboarding snapshots
and the existing permission, sample-copy, editor, and export checks. Reviewed each
step in light/dark and compact/default layouts; longer compact content scrolls
while the footer stays visible. Live navigation remains unverified: automatic
approval review blocked launching the locally built isolated test host as
unrecognized software. That host uses BETTERSHOT_TESTING=1 to avoid requesting
TCC access or reading R2 credentials; launching it requires user approval.

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

