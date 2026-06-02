# Visual slop patterns (V1–V9)

The surface layer. These are the signals every designer on X now lists — easiest to detect, easiest to swap, and therefore the *shortest-lived* as anti-slop criteria. The next training cycle will shift them. Use them for same-day detection, but never stop the audit here: a design that fixes V1–V9 and still exhibits S or C patterns is still slop.

Entries use five fields: **Signal** (what you actually see on screen), **Why it reads as slop** (the root cause), **Remediation** (the direction when avoiding the pattern), **When it's not slop** (the conditions under which this pattern is *not* slop — check this gate *before* flagging in audit mode), and **How to keep it tasteful** (positive direction for the tasteful variant, used in generation mode).

**All entries in this file are tagged `execution-sensitive`:** each V-pattern has a tasteful variant. The "How to keep it tasteful" line makes this catalog a generation handbook as well as a slop-detection list. Counterpart files: `structural.md` (also `execution-sensitive`), `conceptual.md` (tagged `always-slop` — those patterns have no tasteful variant).

---

## V1 — Purple / indigo gradient

Signal: hero background, CTA button, or large accent area uses a linear-gradient from roughly `#8B5CF6` to `#3B82F6` (or the shadcn `primary` default).

Why it reads as slop: Tailwind's `bg-indigo-500` default and shadcn's `primary` color compounded through tutorials into "modern = indigo." Models trained on that output reproduce it by default.

Remediation: do not just swap the hue (that produces green slop). Ask whether color here carries meaning. If yes, define a semantic palette (success / warning / brand / surface). If no, remove the gradient entirely — most of these pages are better with a flat surface.

When it's not slop: when the brand genuinely *is* purple/indigo (Figma, Linear, Stripe have used purple meaningfully) or when the gradient encodes a specific product state — the slop is purple-as-default, not purple as a real choice.

How to keep it tasteful: anchor the gradient in two specific hues that *mean* something (a state transition, a brand moment), use it in ONE load-bearing location (the primary CTA, not the whole hero), and surround it with neutral so the gradient reads as deliberate rather than as decoration.

---

## V2 — Single-weight geometric sans with no typographic hierarchy

Signal: body and display both use the same font at the same weight, with no size contrast, no tracking variation, no pairing — one face doing everything from H1 to caption.

Why it reads as slop: the absence of a typographic decision is what registers as generic, not any specific font. When everything is one weight and one size relationship, the page has no typographic tension.

Remediation: pick the hierarchy first — decide what the H1 is doing that the subhead is not — and let that drive the weight/size/tracking choices. A display serif for headlines, or a strong weight contrast between heading and body, is usually enough to read as intentional.

When it's not slop: a system sans is fine when paired with strong scale/weight contrast and a deliberate hierarchy decision — the slop is the absence of typographic tension, not Inter or Geist as faces.

How to keep it tasteful: pair strong scale and weight contrast (Black 48px H1 over Regular 16px body), vary tracking by role (-2% on display, +2% on small caps), and let one type moment break the system — a serif callout, a mono caption — so the page has tension instead of uniformity.

---

## V3 — Thick sans headline with gradient fill

Signal: the H1 is a heavy sans (Inter Black, Space Grotesk Bold) with a linear gradient as its text fill, usually purple-to-pink or cyan-to-purple, often paired with a soft light-leak background.

Why it reads as slop: this single combination appears in roughly every v0/Lovable hero generation in 2025–2026. It is a visual handshake that says "AI-generated SaaS."

Remediation: a hero headline earns emphasis through the *claim* it makes, not through gradient text. Set the headline in a flat color with strong hierarchy. If a type treatment is needed, try size/weight contrast, a real display face, or selective italic — anything other than gradient fill.

When it's not slop: a single moment of gradient text — a brand mark, a one-word emphasis inside an otherwise flat headline — is fine; the slop is gradient as the entire H1 treatment.

How to keep it tasteful: limit the gradient to one word or one phrase inside an otherwise flat H1, use two brand-meaningful colors (not the default violet-to-pink), and tie the treatment to a specific concept — the gradient should be *about* something (a product state, a brand verb), not just decorative emphasis.

---

## V4 — Uniform `rounded-2xl` / 16px radius on every surface

Signal: every card, button, image, input, modal, and container uses the same border-radius — often `rounded-2xl` (16px) or `rounded-3xl` (24px). Malewicz's phrase is "rounded corners around more rounded corners, boxes inside boxes."

Why it reads as slop: Tailwind and shadcn both nudge toward `rounded-xl`/`rounded-2xl` defaults; the model then applies them uniformly because there is no reason in the prompt to differentiate.

Remediation: use radius as a signal, not as a default. Buttons and inputs can be more rounded; large content containers can be less so (or square). Some of the most distinctive designs pair a single sharp corner system with one exception, not a uniform radius token applied 40 times.

When it's not slop: a deliberately uniform radius system (iOS-style, or a brand decision to be soft everywhere) is fine when the choice is intentional and held across the whole product — the slop is `rounded-2xl` as the unconsidered default.

How to keep it tasteful: commit to a deliberate radius *system* — e.g., 16px for interactive elements, 4px for content containers, square for editorial moments — and apply it consistently across every product surface so the choice reads as a system rather than as a Tailwind default; one exception that breaks the pattern intentionally is the most distinctive move.

---

## V5 — Unrestyled Lucide / Hero Icons

Signal: every icon on the page is a one-weight outlined stroke icon from Lucide or Heroicons, usually sized 20–24px, all identical treatment, often placed in 48×48 rounded squares.

Why it reads as slop: Lucide ships with shadcn; shadcn ships with most templates; models default to them. The *visual uniformity of stroke weight and style* is the tell, not Lucide itself.

Remediation: decide whether icons are decorative or functional. If decorative, consider a custom pictogram set, duotone, or removing them entirely. If functional, keep them but vary size/weight by role — hero-level icons can be larger and filled, inline icons small and outlined — so they stop reading as a grid of identical stamps.

When it's not slop: distinguish (a) decorative-icon-soup — Lucide-everywhere stamping out three-box grids, 48×48 rounded squares, identical stroke weight — which *is* slop; from (b) functional/semantic icons — status indicators, integration marks, navigation chrome, inline icons in copy, or a custom-drawn in-house family — which are fine and often necessary. Do not globally negate icons; negate the *soup*.

How to keep it tasteful: either commission an in-house icon family with a distinctive stroke or duotone treatment, or reserve stock icons for functional roles (status, integration marks, nav chrome) and never as decoration in feature grids; size and weight should vary by role — hero-level filled, inline outlined small — not be uniform 24px stamps.

---

## V6 — Ubiquitous `shadow-sm` / 0.1 opacity drop shadow

Signal: every card has the same light drop shadow, often `shadow-sm` or `shadow-md`, applied uniformly regardless of whether the surface is floating, pinned, or stacked.

Why it reads as slop: "technically clean, emotionally invisible" (prg.sh). Shadows that don't mean anything become visual padding. They register as neutral, which is the core slop texture.

Remediation: tie shadows to elevation meaning. Floating elements (modals, popovers) get real shadows; in-flow cards may need none. Or replace shadows with border-only surfaces for a flatter language. Uniform light shadows are almost always the wrong call.

When it's not slop: shadows that genuinely encode an elevation hierarchy (modal > popover > floating card > flat surface) are fine; the slop is `shadow-sm` applied uniformly as visual padding.

How to keep it tasteful: define a clear elevation ladder (1 = card on surface, 2 = popover, 3 = modal, 4 = drag-state) and use it consistently, replace `shadow-sm` on in-flow content with thin borders, and reserve actual shadow for elements that genuinely float over other content; the same `shadow-md` on every card means nothing — it's just visual noise with a Tailwind class.

---

## V7 — Random gradient blobs and radial glows

Signal: blurred circular gradient shapes floating in the hero background, sometimes three or four stacked, with no relation to content or hierarchy. Also: radial gradients behind H1s with no compositional reason.

Why it reads as slop: these exist to fill space. They are the "I need something here" move the model makes when the prompt didn't specify what the background is doing.

Remediation: subtract them. If the hero feels empty without them, the real problem is that the hero has nothing to say — go fix the headline (C1) or bring in the actual product (C4). A decorative blob is rarely the right answer.

When it's not slop: an abstract shape is fine when it visualizes the product itself (a network mesh for a graph database, a waveform for an audio tool, a particle field for a physics sim); the slop is decoration with no referent.

How to keep it tasteful: tie the shape to product semantics — the abstract form should reference what the product actually does (mesh for graph, waveform for audio, field for physics) — and animate it to encode real state (loading, processing, ambient activity); if the shape would still make sense as the product's app icon, it's earning its space.

---

## V8 — Glassmorphic cards on a purple backdrop

Signal: cards with `backdrop-blur` + semi-transparent white background + thin border, stacked over a purple/indigo gradient. Especially common on AI-generated dashboards.

Why it reads as slop: glass + purple is the dashboard template of the current moment. v0's gallery is full of it. Malewicz (who coined "glassmorphism") explicitly calls it out.

Remediation: do not reach for glass by default. Use it only when there is a layered composition that benefits from transparency (one element genuinely hovers over meaningful content behind it). Most dashboards are better with opaque surfaces and strong data hierarchy.

When it's not slop: real layered composition — a panel that genuinely floats over meaningful content the user needs to still perceive — can use transparency to communicate depth; the slop is glass-as-skin on flat purple backgrounds.

How to keep it tasteful: use transparency only when there's meaningful content behind that the user genuinely benefits from continuing to perceive (a nav panel over scrolling content, a modal over a live data view), keep the blur restrained (12-24px, not 60px), and never stack glass over glass — one layer of transparency, not three.

---

## V9 — AI-generated "3D clay" illustrations

Signal: smooth, plastic-looking 3D renders — often a diverse team at a laptop, an abstract geometric object, or a floating UI element. Too symmetric, too soft-shadowed, no physical material logic.

Why it reads as slop: these are the image-model equivalent of the purple gradient. They land in hero sections because the prompt asked for "an illustration" and the model reached for its median output.

Remediation: use the actual product screenshot. If a custom illustration is needed and a designer isn't available, a flat vector in a real illustration system (Figma, a shared style) beats AI 3D clay for distinctiveness almost every time. If the product isn't visually ready to show, say so with words and screenshots of real work, not with a stock-feel 3D render.

When it's not slop: bespoke commissioned illustration, or 3D rendering for a product that genuinely deals in 3D (a CAD tool, a game engine, a 3D modeling app), is fine; the slop is generic AI-rendered 3D clay as filler in a hero that has nothing else to show.

How to keep it tasteful: commission bespoke illustration in a distinctive medium (claymation, isometric line, photographic composite), or limit 3D to products that genuinely deal in 3D space (CAD, game engines, modeling tools); a single weak generic render contaminates the whole page, so if you can't commit to bespoke, use a real product screenshot instead and tell the truth about the visual.
