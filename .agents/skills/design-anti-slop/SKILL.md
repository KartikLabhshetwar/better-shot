---
name: design-anti-slop
description: Detect and fix AI design slop — the convergent look that shows up across AI-generated landing pages and dashboards (purple/indigo gradients, rounded-2xl everywhere, three-box feature grids, bento dashboards, aspirational-but-empty hero copy, etc.). Use this skill whenever the user asks Claude to build/generate/mock up a landing page, dashboard, or SaaS UI, OR when the user shares an existing design (screenshot, URL, code, Figma link) and asks for critique, feedback, "does this look AI-generated?", or "make this less generic." Trigger even if the user does not use the word "slop" — phrases like "build me a hero section," "this looks AI-made," "why does this look like every other SaaS page," or "make this feel more custom" all qualify. Prefer this skill over general design-critique when the concern is specifically convergence, sameness, or AI-generated feel.
---

# design:anti-slop

AI design slop is a statistical problem with aesthetic symptoms. Language models sample near the center of their training distribution, so without specific constraints they produce the same landing page and the same dashboard, over and over. This skill exists to do two things that a banlist of "bad colors" cannot:

- **Force specificity before generation** so the model has something to sample from other than the distribution mean.
- **Audit for convergence after generation** across three layers — visual, structural, and conceptual — and remediate at the deepest layer that is actually broken.

The skill does not own general design taste, accessibility, or copywriting. It owns the slop taxonomy and the three workflows that apply it. For everything else it hands off.

## When to pick a mode

There are three modes. They have different triggers, different UX, and different outputs. Do not merge them.

**Mode A — pre-generation brief enforcer.** Trigger when the user asks Claude to *produce* a landing page, dashboard, or app UI and has not supplied a style brief. Signals: "build a landing page for X," "make me a SaaS homepage," "generate a dashboard," "mock up a hero section," "design an app for Y." If there is no brief, read `workflows/pre-gen-brief.md` and follow it before writing any code.

**Mode B — post-generation audit.** Trigger when the user shares an existing design (screenshot, deployed URL, code file, Figma link, v0/Bolt/Lovable output) and asks for review. Signals: "does this look AI-generated," "critique this design," "what's wrong with this page," "make this less generic," "roast this landing page," or a bare screenshot with no instructions. Read `workflows/post-gen-audit.md` and follow it.

**Mode C — iterative polish.** Trigger when the user has already accepted the page's structure and is asking for depth or richness, not regeneration. Signals: "make this better," "make the assets richer," "add some depth," "this still feels flat," "push it further," "what's missing." Read `workflows/iterative-polish.md`. The protocol is per-asset (inventory → rank → push from data-poor to data-rich → verify), and reactive cosmetic padding is forbidden.

**If the request is ambiguous** — e.g., the user pastes a draft and says "improve this" — default to Mode B. If the user then asks Claude to regenerate from scratch, enter Mode A at that point. If the user accepts the structure and then asks to "go deeper," that's the handoff to Mode C.

**If the request is a throwaway or exploratory** — e.g., "just give me something rough to play with" — skip brief enforcement, generate, but name the defaults you fell back on ("I used indigo because you didn't specify; swap to a semantic palette when you have one") so the user can see what's happening.

## Saved preferences vs. per-project briefs

Durable preferences saved to memory ("user prefers warm/editorial palettes," "user dislikes generic bento grids," "user always wants serif H1s") are **defaults to ECHO and CONFIRM, not constraints to silently enforce.** A preference that was right for last month's marketing site may be wrong for this week's compliance tool, and silently applying it strips the user's chance to redirect.

At brief-time, surface saved prefs explicitly, e.g.:

> Your saved prefs say [warm editorial palette, no bento grids, serif H1] — applying that here unless you want different for this project?

Wait for confirmation (or a redirect) before injecting them into the brief. Treat saved prefs as *priors that bias the default answer to each axis*, not as answers themselves.

## The pattern catalog

All pattern IDs used in audits live in three sibling files. Read the relevant file(s) when you need to look up a pattern's signal, root cause, or remediation — do not try to recall from memory, the entries exist precisely so remediations stay grounded.

- `patterns/visual.md` — V1–V9. The surface layer: colors, typography, radii, shadows, icons, blobs, glass cards, 3D clay illustrations. Fastest to detect, shortest half-life, weakest on its own.
- `patterns/structural.md` — S1–S9. Composition: hero template, three-box feature grid, logo soup, bento grids, KPI card rows, sidebar-with-generic-menu. This is where most slop actually lives and it is the layer most other skills miss.
- `patterns/conceptual.md` — C1–C7. Copy and product truth: aspirational-empty headlines, verb slop, no point of view, abstract demo visuals, invented stats, missing functional states. If layer 3 is broken, layer 1/2 fixes are cosmetic.

The three files are independent; read only the ones you need for the current pass.

## Rank remediations by layer, not by ease

When a design has problems at multiple layers, the instinct is to fix the visual layer first because it is cheapest. Resist that. A design with a great hero claim, a real product screenshot, and Inter + indigo is not slop — it is just undistinctive visually, which may be fine. A design with a perfect custom color system, a beautiful typeface, and "Build the future of work" as its headline *is* slop.

Rank remediations in this order, and tell the user which layer you picked and why:

1. Conceptual fixes (layer 3) first. If the hero claim is hollow or the demo is abstract, fix that before touching styling.
2. Structural fixes (layer 2) next. If the structure is "three-box grid + KPI row + logo soup," fix the composition before repainting it.
3. Visual fixes (layer 1) last. Only reach for these when the deeper layers are sound, or as a quick symptomatic patch the user has explicitly asked for.

Be willing to say "this is fine and not slop." If you flag everything, you lose credibility. A clean audit is a valid result.

## Hand-offs — this skill is narrow on purpose

When the real work belongs to another skill, say so and name the skill. Do not try to do it here.

| Situation | Hand off to |
|---|---|
| Layer-3 copy issues (C1 aspirational-empty hero, C2 verb slop, C6 fake specificity) past spot-fixes | `design:ux-copy` |
| Cross-page consistency / the same uniform-everything problem (S6) recurring across a product | `design:design-system` |
| General design review (hierarchy, spacing, contrast, interaction states not tied to slop patterns) | `design:design-critique` |
| Accessibility concerns surfaced by the audit (partial overlap with C7 missing states) | `design:accessibility-review` |
| User wants alternative *directions* rather than fixes to the current design | `design-ideation` |

The terminal remediation for a team that cares about this long-term is a project-specific design system. Say that out loud when it applies — this skill is a stopgap, not a system.

*If a referenced skill is not installed in this environment, do the spot-fix inline and name the limitation explicitly — e.g. "this is really a `design:ux-copy` job; I'm doing a quick rewrite here, but flagging that the deeper copy pass is out of scope for this skill."*

## Stake calibration — how much of the workflow to run

Anti-goals says "calibrate to stakes." Concretely:

| Surface | Recommended depth |
|---|---|
| Customer-facing landing page (real launch) | Mode A, all 5 axes; full Mode B audit if one already exists |
| Internal admin tool / dashboard mock | Mode A but only Claim + Asset axes — Typography/Color/Avoid are usually template-fine |
| Throwaway exploratory mock ("just show me roughly") | Short-path fallback; do not run the interview |
| One-off marketing experiment | All 5 axes if it'll ship to real users; short-path if it's a thrown-together test |

This table is the answer to "should I run the brief or not?" — do not improvise.

## Anti-goals — what this skill is not

These are load-bearing. If you find yourself drifting toward any of them, re-read this section.

- **Not a taste policeman.** This skill does not prefer serif to sans, brutalism to glassmorphism, or any specific aesthetic. It flags convergence, not fashion.
- **Not a pendulum.** The "anti-slop look" (grain, overflow type, asymmetric chaos) is itself becoming a new attractor. Do not push toward it. Push toward specificity, whatever that specifically is for this user.
- **Not frozen.** Every concrete pattern in the catalog has a half-life. When a pattern stops mattering — because the underlying default shifted, or because the trend cycle moved — flag it and update the file.
- **Not a banlist only.** Negation alone produces uglier slop (ban Inter → model converges on Space Grotesk). Every pattern entry carries a remediation direction, not just "avoid."
- **Not over-eager.** Calibrate to stakes. A quick throwaway mock does not need a five-axis brief. A real customer-facing landing page does.
- **Not a checklist.** The catalog is not a "hit all entries to pass" rubric. One real slop hit beats five borderline ones; if the design exhibits one clear layer-3 issue, flag that and stop, do not pad the audit with every V-layer match you can find.

## One sentence to keep in mind

The goal is not to make AI output look more handcrafted. The goal is to make AI output reflect the specific intent of this specific user for this specific product. If the brief is specific enough, the slop patterns stop appearing on their own.
